from datetime import datetime, timezone
from test_api import client, signup, transaction
from test_planning import profile
from app.domain.budget_review import review


def test_review_ownership_and_missing_timezone(client):
    h, tokens = signup(client)
    assert client.get('/budgets/review?period=2026-10').status_code == 401
    assert client.get('/budgets/review?period=2026-13', headers=h).status_code == 422
    client.post('/budgets', headers=h, json={'period': '2026-10', 'limit_amount': 10000})
    data = client.get('/budgets/review?period=2026-10', headers=h).json()
    assert data['owner_id'] == tokens['user']['id']
    assert data['items'][0]['daily_guide'] is None and data['days_remaining'] is None
    other, _ = signup(client, 'other@example.com')
    assert client.get('/budgets/review?period=2026-10', headers=other).json()['items'] == []


def test_review_guide_contributions_and_edits(client):
    h, tokens = signup(client)
    client.put('/financial-profile', headers=h, json=profile(timezone='Asia/Kuala_Lumpur'))
    overall = client.post('/budgets', headers=h, json={'period': '2026-10', 'limit_amount': 10000}).json()
    client.post('/budgets', headers=h, json={'period': '2026-10', 'category_id': 'food', 'limit_amount': 500})
    for changes in [{'amount': 600}, {'amount': 300, 'category_id': 'transport'}, {'type': 'income', 'category_id': 'salary', 'amount': 99999}]:
        client.post('/transactions', headers=h, json=transaction(date='2026-10-01', **changes))
    def check(now): return review('2026-10', tokens['user'], client.app.state.repo, now=now)
    data = check(datetime(2026, 10, 15, tzinfo=timezone.utc))
    assert data['days_remaining'] == 17
    budget = next(b for b in data['items'] if b['id'] == overall['id'])
    assert budget['spent'] == 900 and budget['remaining'] == 9100
    assert budget['daily_guide'] == 535
    assert budget['top_categories'] == [{'name': 'Food', 'amount': 600}, {'name': 'Transport', 'amount': 300}]
    food = next(b for b in data['items'] if b['category_id'] == 'food')
    assert food['daily_guide'] == 0 and food['remaining'] == -100 and food['threshold_reached']
    client.post('/budgets', headers=h, json={'period': '2026-10', 'limit_amount': 20000})
    assert next(b for b in check(datetime(2026, 10, 31, 15, 59, tzinfo=timezone.utc))['items'] if b['id'] == overall['id'])['daily_guide'] == 19100
    assert all(b['daily_guide'] is None for b in check(datetime(2026, 10, 31, 16, tzinfo=timezone.utc))['items'])
    client.delete('/budgets/'+overall['id'], headers=h)
    assert len(check(datetime(2026, 10, 15, tzinfo=timezone.utc))['items']) == 1


def test_review_expiry_at_local_midnight_and_leap_year(client):
    h, tokens = signup(client)
    client.put('/financial-profile', headers=h, json=profile(timezone='America/New_York'))
    client.post('/budgets', headers=h, json={'period': '2028-02', 'limit_amount': 300})
    data = review('2028-02', tokens['user'], client.app.state.repo, now=datetime(2028, 2, 29, 4, 59, tzinfo=timezone.utc))
    assert data['days_remaining'] == 2 and data['items'][0]['daily_guide'] == 150
    assert data['expires_at'] == '2028-02-29T05:00:00+00:00'
