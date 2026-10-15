from datetime import datetime, timezone
from uuid import uuid4
from test_api import client, signup
from test_planning import profile, schedule
from app.domain.bill_reminders import upcoming


def add(client, h, **changes):
    revision = client.get('/financial-profile', headers=h).json()['revision']
    r = client.post('/commitments', headers=h, json=schedule(revision, **changes))
    assert r.status_code == 201, r.text
    return r.json()['commitments'][-1]['id']


def test_owner_scope_validation_and_missing_timezone(client):
    h, tokens = signup(client)
    assert client.get('/notifications/bills').status_code == 401
    initial = client.get('/notifications/bills', headers=h).json()
    assert not initial['ready'] and initial['items'] == []
    assert initial['owner_id'] == tokens['user']['id']
    assert client.get('/notifications/bills?lead_days=2', headers=h).status_code == 422
    client.put('/financial-profile', headers=h, json=profile())
    add(client, h, frequency='daily', start_date='2020-01-01')
    assert client.get('/notifications/bills', headers=h).json()['items']
    other, _ = signup(client, 'other@example.com')
    assert client.get('/notifications/bills', headers=other).json()['items'] == []


def test_grouping_partial_payment_and_removal(client):
    h, tokens = signup(client)
    client.put('/financial-profile', headers=h, json=profile(timezone='Asia/Kuala_Lumpur'))
    one = add(client, h, start_date='2026-10-20', end_date='2026-10-20')
    two = add(client, h, name='Internet', start_date='2026-10-20', end_date='2026-10-20')
    user, db = tokens['user'], client.app.state.repo
    now = datetime(2026, 10, 14, tzinfo=timezone.utc)
    def reminders(): return upcoming(1, user, db, now=now)['items']
    first = reminders()
    assert len(first) == 1 and first[0]['count'] == 2
    assert first[0]['fire_at'] == '2026-10-19T01:00:00+00:00'
    def pay(id, amount):
        revision = client.get('/financial-profile', headers=h).json()['revision']
        r = client.post(f'/commitment-occurrences/commitments:{id}:2026-10-20/payments', headers=h,
            json={'expected_revision': revision, 'operation_id': str(uuid4()), 'amount': amount, 'date': '2026-10-14'})
        assert r.status_code == 200, r.text
    pay(one, 5000)
    assert reminders() == first
    pay(one, 5000)
    assert reminders()[0]['count'] == 1
    assert reminders()[0]['id'] == first[0]['id']
    revision = client.get('/financial-profile', headers=h).json()['revision']
    assert client.delete(f'/commitments/{two}?expected_revision={revision}', headers=h).status_code == 200
    assert reminders() == []


def test_timezone_dst_window_and_missed_times(client):
    h, tokens = signup(client)
    client.put('/financial-profile', headers=h, json=profile(timezone='America/New_York'))
    add(client, h, frequency='daily', start_date='2020-01-01')
    user, db = tokens['user'], client.app.state.repo
    data = upcoming(1, user, db, now=datetime(2026, 10, 31, 12, tzinfo=timezone.utc))
    assert len(data['items']) == 60
    assert data['items'][0]['fire_at'] == '2026-10-31T13:00:00+00:00'
    assert data['items'][1]['fire_at'] == '2026-11-01T14:00:00+00:00'
    assert len({i['id'] for i in data['items']}) == 60
    later = upcoming(1, user, db, now=datetime(2026, 10, 31, 14, tzinfo=timezone.utc))
    assert len(later['items']) == 59
    assert later['items'][0]['due_date'] == '2026-11-02'
