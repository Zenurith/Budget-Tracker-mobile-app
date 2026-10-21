from uuid import uuid4
from test_api import client, signup, transaction
from test_money_accounts import create


def test_split_totals_budgets_search_accounts_and_edit(client):
    h, _ = signup(client)
    account = create(client, h, 'Bank', 20000)
    parts = [{'category_id': 'food', 'amount': 9000}, {'category_id': 'shopping', 'amount': 6000}]
    payload = transaction(amount=15000, category_id='food', date='2026-09-10', account_id=account, splits=parts)
    saved = client.post('/transactions', headers=h, json=payload)
    assert saved.status_code == 201, saved.text
    for category in (None, 'food', 'shopping'):
        assert client.post('/budgets', headers=h, json=dict(period='2026-09', limit_amount=20000, category_id=category, alert_threshold=80)).status_code in (200, 201)
    summary = client.get('/reports/summary?month=2026-09', headers=h).json()
    assert summary['expenses'] == 15000
    assert summary['category_breakdown'] == {'food': 9000, 'shopping': 6000}
    assert summary['trend'][-1]['category_totals'] == summary['category_breakdown']
    budgets = client.get('/budgets?period=2026-09', headers=h).json()['items']
    assert {b['category_id']: b['spent'] for b in budgets} == {None: 15000, 'food': 9000, 'shopping': 6000}
    assert client.get('/transactions?category_id=shopping', headers=h).json()['total'] == 1
    assert client.get('/money-accounts', headers=h).json()['items'][0]['balance'] == 5000
    assert client.put('/transactions/' + saved.json()['id'], headers=h, json=dict(payload, splits=[])).status_code == 200
    assert client.get('/reports/summary?month=2026-09', headers=h).json()['category_breakdown'] == {'food': 15000}


def test_split_validation_and_sync_replay(client):
    h, _ = signup(client)
    good = transaction(amount=100, category_id='food', splits=[{'category_id': 'food', 'amount': 40}, {'category_id': 'shopping', 'amount': 60}])
    for splits in ([{'category_id': 'food', 'amount': 100}], [{'category_id': 'food', 'amount': 40}, {'category_id': 'shopping', 'amount': 50}], [{'category_id': 'food', 'amount': 40}, {'category_id': 'food', 'amount': 60}], [{'category_id': 'food', 'amount': 40}, {'category_id': 'salary', 'amount': 60}], [{'category_id': 'food', 'amount': 100}, {'category_id': 'shopping', 'amount': 0}]):
        assert client.post('/transactions', headers=h, json=dict(good, splits=splits)).status_code == 422
    operation = dict(operation_id=str(uuid4()), action='create', transaction=good)
    response = client.post('/transactions/sync', headers=h, json=operation)
    assert response.status_code == 200, response.text
    assert client.post('/transactions/sync', headers=h, json=operation).json() == response.json()
    assert client.get('/transactions', headers=h).json()['total'] == 1
