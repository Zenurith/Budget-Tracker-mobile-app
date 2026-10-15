from datetime import datetime, timezone
from test_api import client, signup, transaction
from test_planning import profile
from app.domain.budget_alerts import current


def test_auth_timezone_and_owner_scope(client):
    h, tokens = signup(client)
    assert client.get('/notifications/budgets').status_code == 401
    data = client.get('/notifications/budgets', headers=h).json()
    assert data['owner_id'] == tokens['user']['id']
    assert not data['ready'] and data['items'] == []
    client.put('/financial-profile', headers=h, json=profile(timezone='Asia/Kuala_Lumpur'))
    client.post('/budgets', headers=h, json={'period': '2026-11', 'limit_amount': 100})
    client.post('/transactions', headers=h, json=transaction(date='2026-11-01', amount=80))
    now = datetime(2026, 10, 31, 16, tzinfo=timezone.utc)
    data = current(tokens['user'], client.app.state.repo, now=now)
    assert data['period'] == '2026-11' and len(data['items']) == 1
    other, other_tokens = signup(client, 'other@example.com')
    client.put('/financial-profile', headers=other, json=profile(timezone='America/New_York'))
    theirs = current(other_tokens['user'], client.app.state.repo, now=now)
    assert theirs['period'] == '2026-10' and theirs['items'] == []
    assert client.get('/notifications/budgets', headers=h).status_code == 200


def test_exact_threshold_category_income_and_corrections(client):
    h, tokens = signup(client)
    client.put('/financial-profile', headers=h, json=profile())
    def check(): return current(tokens['user'], client.app.state.repo, now=datetime(2026, 9, 28, tzinfo=timezone.utc))['items']
    body = {'period': '2026-09', 'limit_amount': 1001, 'alert_threshold': 80}
    overall = client.post('/budgets', headers=h, json=body).json()
    food = client.post('/budgets', headers=h, json=dict(body, category_id='food', limit_amount=1000, alert_threshold=100)).json()
    expense = client.post('/transactions', headers=h, json=transaction(amount=800)).json()
    client.post('/transactions', headers=h, json=transaction(type='income', category_id='salary', amount=10000))
    client.post('/transactions', headers=h, json=transaction(date='2026-08-31', amount=10000))
    assert check() == []
    client.post('/transactions', headers=h, json=transaction(amount=1, category_id='transport'))
    assert check() == [{'id': overall['id']}]
    client.put('/transactions/'+expense['id'], headers=h, json=transaction(amount=1000))
    assert {i['id'] for i in check()} == {overall['id'], food['id']}
    client.delete('/transactions/'+expense['id'], headers=h)
    assert check() == []
    client.post('/budgets', headers=h, json=dict(body, limit_amount=1, alert_threshold=100))
    assert check() == [{'id': overall['id']}]
    client.delete('/budgets/'+overall['id'], headers=h)
    assert check() == []
