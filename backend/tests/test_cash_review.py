from test_api import client, signup, transaction
from test_funding import setup, plan, cash


def test_cash_review_requires_started_plan_and_is_owner_scoped(client):
    assert client.get('/notifications/cash-review').status_code == 401
    h, user = signup(client)
    other, _ = signup(client, 'other@example.com')
    def check(headers=h):
        result = client.get('/notifications/cash-review', headers=headers)
        assert result.status_code == 200
        return result.json()
    assert check()['needs_review'] is False
    setup(client, h)
    assert check()['needs_review'] is True  # Cash reviewed, funding plan missing.
    plan(client, h)
    assert check()['needs_review'] is False
    assert 'up to date' in check()['reason']
    assert client.post('/transactions', headers=h, json=transaction()).status_code == 201
    assert check()['needs_review'] is True
    assert check(other)['needs_review'] is False
    assert check()['owner_id'] != check(other)['owner_id']
    assert set(check()) == {'owner_id', 'day', 'needs_review', 'reason'}
    cash(client, h)
    assert check()['needs_review'] is False


def test_cash_review_follows_profile_day_and_snapshot_expiry(client, monkeypatch):
    from datetime import timedelta
    from app.domain import planning, funding
    h, _ = signup(client)
    setup(client, h)
    plan(client, h)
    today = planning.today_for({'profile': {'timezone': 'UTC'}})
    monkeypatch.setattr(planning, 'today_for', lambda _: today + timedelta(days=1))
    result = client.get('/notifications/cash-review', headers=h).json()
    assert result['needs_review'] is True
    assert result['day'] == (today + timedelta(days=1)).isoformat()
    monkeypatch.setattr(planning, 'today_for', lambda _: today)
    original_now = funding.now()
    monkeypatch.setattr(funding, 'now', lambda: original_now + timedelta(hours=25))
    assert client.get('/notifications/cash-review', headers=h).json()['needs_review'] is True
