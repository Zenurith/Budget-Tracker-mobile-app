from uuid import uuid4
from test_api import client, signup, transaction


def create(client, h, name, amount=10000):
    payload = dict(name=name, opening_date='2020-01-01', opening_amount=amount, operation_id=str(uuid4()))
    result = client.post('/money-accounts', headers=h, json=payload)
    assert result.status_code == 201, result.text
    assert client.post('/money-accounts', headers=h, json=payload).json()['id'] == result.json()['id']
    return result.json()['id']


def test_accounts_assignment_transfer_totals_and_replay(client):
    h, _ = signup(client)
    a, b = create(client, h, 'Bank'), create(client, h, 'Cash', 0)
    assert client.post('/transactions', headers=h, json=transaction(amount=1500, account_id=a)).status_code == 201
    assert client.post('/transactions', headers=h, json=transaction(amount=700)).status_code == 201
    before = client.get('/reports/summary?month=2026-09', headers=h).json()
    body = dict(operation_id=str(uuid4()), from_account=a, to_account=b, amount=2000, date='2026-01-02', note='ATM')
    first = client.post('/account-transfers', headers=h, json=body)
    assert first.status_code == 201, first.text
    assert client.post('/account-transfers', headers=h, json=body).json()['id'] == first.json()['id']
    assert client.post('/account-transfers', headers=h, json=dict(body, amount=2001)).status_code == 409
    data = client.get('/money-accounts', headers=h).json()
    balances = {r['id']: r['balance'] for r in data['items']}
    assert balances == {a: 6500, b: 2000}
    assert data['unassigned_count'] == 1
    assert len(data['transfers']) == 1
    after = client.get('/reports/summary?month=2026-09', headers=h).json()
    for field in ('income', 'expenses', 'net', 'category_breakdown'):
        assert before[field] == after[field]
    check = dict(operation_id=str(uuid4()), account_id=b, actual=1800)
    response = client.post('/money-accounts/reconcile', headers=h, json=check)
    assert response.status_code == 201
    assert response.json()['difference'] == -200
    assert client.post('/money-accounts/reconcile', headers=h, json=check).json()['id'] == response.json()['id']
    assert client.get('/money-accounts', headers=h).json()['items'] == data['items']


def test_accounts_isolation_invalid_dates_and_transfer_validation(client):
    h, _ = signup(client)
    other, _ = signup(client, 'other@example.com')
    a, b = create(client, h, 'Bank'), create(client, h, 'Wallet')
    foreign = create(client, other, 'Private')
    assert client.post('/transactions', headers=h, json=transaction(account_id=foreign)).status_code == 422
    assert client.post('/transactions', headers=h, json=transaction(account_id=a, date='2019-01-01')).status_code == 422
    for changes in ({'to_account': a}, {'to_account': foreign}, {'amount': 0}, {'date': '2099-01-01'}, {'date': '2019-01-01'}):
        payload = dict(operation_id=str(uuid4()), from_account=a, to_account=b, amount=100, date='2026-01-02')
        payload.update(changes)
        assert client.post('/account-transfers', headers=h, json=payload).status_code == 422
    assert client.get('/money-accounts', headers=other).json()['transfers'] == []
    assert client.get('/money-accounts').status_code == 401


def test_account_management_revision_archive_and_opening_guards(client):
    h, _ = signup(client)
    other, _ = signup(client, 'other@example.com')
    a, b = create(client, h, 'Bank'), create(client, h, 'Cash', 0)
    entry = client.post('/transactions', headers=h, json=transaction(account_id=a, date='2026-01-02')).json()
    payload = dict(operation_id=str(uuid4()), account_id=a, expected_revision=0,
                   name='Main bank', opening_date='2020-01-01', opening_amount=12000, archived=True)
    assert client.post('/money-accounts/update', headers=other, json=payload).status_code == 422
    response = client.post('/money-accounts/update', headers=h, json=payload)
    assert response.status_code == 200, response.text
    assert response.json()['revision'] == 1
    assert client.post('/money-accounts/update', headers=h, json=payload).json() == response.json()
    assert client.post('/money-accounts/update', headers=h, json=dict(payload, name='Changed')).status_code == 409
    stale = dict(payload, operation_id=str(uuid4()))
    assert client.post('/money-accounts/update', headers=h, json=stale).status_code == 409
    assert client.post('/transactions', headers=h, json=transaction(account_id=a)).status_code == 422
    assert client.put('/transactions/' + entry['id'], headers=h, json=transaction(account_id=a, date='2026-01-02')).status_code == 200
    transfer = dict(operation_id=str(uuid4()), from_account=a, to_account=b, amount=100, date='2026-01-02')
    assert client.post('/account-transfers', headers=h, json=transfer).status_code == 422
    current = dict(payload, operation_id=str(uuid4()), expected_revision=1, archived=False)
    assert client.post('/money-accounts/update', headers=h, json=dict(current, opening_date='2026-01-03')).status_code == 409
    assert client.post('/money-accounts/update', headers=h, json=dict(current, name='Cash')).status_code == 422
    assert client.post('/money-accounts/update', headers=h, json=current).status_code == 200
    assert client.post('/account-transfers', headers=h, json=transfer).status_code == 201
    # Destination has only transfer history; moving its start past that transfer is still rejected.
    later = dict(current, operation_id=str(uuid4()), account_id=b, expected_revision=0, name='Cash', opening_date='2026-01-03')
    assert client.post('/money-accounts/update', headers=h, json=later).status_code == 409
    data = client.get('/money-accounts', headers=h).json()
    assert len(data['changes']) == 2
    assert data['changes'][-1]['before']['name'] == 'Bank'
    assert data['changes'][0]['after']['archived'] is False


def test_opening_correction_guards_undo_and_preserves_old_checks(client):
    h, _ = signup(client)
    a = create(client, h, 'Bank')
    entry = client.post('/transactions', headers=h, json=transaction(account_id=a, date='2020-02-01')).json()
    check = client.post('/money-accounts/reconcile', headers=h, json=dict(operation_id=str(uuid4()), account_id=a, actual=9000)).json()
    assert client.delete('/transactions/' + entry['id'], headers=h).status_code == 204
    history = client.get('/transaction-history', headers=h).json()['items']
    deletion = next(e for e in history if e['action'] == 'delete')
    payload = dict(operation_id=str(uuid4()), account_id=a, expected_revision=0,
                   name='Bank', opening_date='2021-01-01', opening_amount=20000, archived=False)
    assert client.post('/money-accounts/update', headers=h, json=payload).status_code == 200
    assert client.post('/transaction-history/' + deletion['id'] + '/undo', headers=h).status_code == 422
    data = client.get('/money-accounts', headers=h).json()
    assert data['checks'][0] == check
    assert data['items'][0]['balance'] == 20000


def test_reconciliation_review_arithmetic_and_owner_scope(client):
    h, _ = signup(client)
    a, b = create(client, h, 'Bank'), create(client, h, 'Cash', 0)
    client.post('/transactions', headers=h, json=transaction(amount=1500, account_id=a))
    client.post('/transactions', headers=h, json=transaction(amount=700))
    client.post('/account-transfers', headers=h, json=dict(operation_id=str(uuid4()), from_account=a, to_account=b, amount=2000, date='2026-01-02', note='ATM'))
    data = client.get('/money-accounts', headers=h).json()
    bank = next(x for x in data['items'] if x['id'] == a)
    review = bank['review']
    assert review['expenses'] == 1500 and review['transfers_out'] == 2000
    assert review['income'] == 0 and review['transfers_in'] == 0
    assert bank['balance'] == bank['opening_amount'] + sum(e['amount'] for e in review['activity'])
    assert review['activity_count'] == 2
    assert data['unassigned_review'][0]['amount'] == -700
    other, _ = signup(client, 'other@example.com')
    isolated = client.get('/money-accounts', headers=other).json()
    assert isolated['items'] == [] and isolated['unassigned_review'] == []
