from datetime import date, datetime, timezone
from uuid import uuid4
from concurrent.futures import ThreadPoolExecutor
import pytest
from test_api import client, signup, transaction
from test_funding import cash
from app.domain import record_history


def opening(**changes):
    return dict({'operation_id': str(uuid4()), 'expected_revision': 0, 'currency': 'EUR',
                 'as_of': '2026-01-01', 'accounts': [{'name': 'Cash', 'amount': 100000}], 'confirmed': True}, **changes)


CSV = 'date,type,amount,category,note\n2026-10-01,expense,12.50,Food,Lunch\n2026-10-02,income,100.00,Salary,Pay\n'


def test_opening_balance_is_not_income_and_revision_history_is_preserved(client):
    h, session = signup(client)
    client.post('/transactions', headers=h, json=transaction(date='2025-12-31', amount=999))
    client.post('/transactions', headers=h, json=transaction(date='2026-01-01', amount=1250))
    payload = opening()
    first = client.put('/balances/opening', headers=h, json=payload)
    assert first.status_code == 200, first.text
    assert client.put('/balances/opening', headers=h, json=payload).json() == first.json()
    summary = client.get('/reports/summary?month=2026-01', headers=h).json()
    assert summary['balance'] == 98750
    assert summary['income'] == 0 and summary['expenses'] == 1250
    assert len(client.get('/balances', headers=h).json()['items']) == 1
    assert client.put('/balances/opening', headers=h, json=opening()).status_code == 409
    changed = opening(expected_revision=1, accounts=[{'name': 'Cash', 'amount': 0}, {'name': 'Bank', 'amount': -200}])
    assert client.put('/balances/opening', headers=h, json=changed).status_code == 200
    rows = client.get('/balances', headers=h).json()['items']
    assert rows[0]['before']['total'] == 100000
    assert rows[0]['after']['total'] == -200
    assert rows[1]['after']['total'] == 100000
    exported = client.get('/auth/me/export', headers=h).json()
    assert len(exported['opening_balances']) == 1
    assert len(exported['balance_history']) == 2


def test_reconciliation_records_expected_difference_without_posting_adjustments(client):
    h, _ = signup(client)
    assert client.put('/balances/opening', headers=h, json=opening()).status_code == 200
    cash(client, h, 120000)
    rows = client.get('/balances', headers=h).json()['items']
    event = rows[0]
    assert event['kind'] == 'reconciliation'
    assert event['recorded']['balance'] == 100000
    assert event['difference'] == 20000
    assert client.get('/transactions', headers=h).json()['total'] == 0
    cash(client, h, 125000)
    rows = client.get('/balances', headers=h).json()['items']
    assert rows[0]['before']['liquid_total'] == 120000
    assert rows[1] == event


def test_opening_input_and_owner_guards(client):
    h, _ = signup(client)
    other, _ = signup(client, 'other@example.com')
    assert client.put('/balances/opening', headers=h, json=opening(currency='USD')).status_code == 422
    assert client.put('/balances/opening', headers=h, json=opening(confirmed=False)).status_code == 422
    assert client.put('/balances/opening', headers=h, json=opening(accounts=[{'name': 'Cash', 'amount': 0}, {'name': ' cash ', 'amount': 0}])).status_code == 422
    assert client.put('/balances/opening', headers=h, json=opening()).status_code == 200
    assert client.get('/balances', headers=other).json()['opening'] is None


def test_csv_preview_selection_duplicates_and_retry(client):
    h, _ = signup(client)
    preview = client.post('/imports/csv/preview', headers=h, json={'contents': CSV}).json()
    assert preview['items'][0]['transaction']['amount'] == 1250
    assert not preview['items'][0]['duplicate']
    assert client.get('/transactions', headers=h).json()['total'] == 0
    payload = {'contents': CSV, 'operation_id': str(uuid4()), 'rows': [1, 2], 'allow_duplicates': []}
    response = client.post('/imports/csv/commit', headers=h, json=payload)
    assert response.status_code == 200, response.text
    assert response.json()['imported'] == 2
    assert client.post('/imports/csv/commit', headers=h, json=payload).json() == response.json()
    assert client.get('/transactions', headers=h).json()['total'] == 2
    preview = client.post('/imports/csv/preview', headers=h, json={'contents': CSV}).json()
    assert all(r['duplicate'] for r in preview['items'])
    payload['operation_id'] = str(uuid4())
    assert client.post('/imports/csv/commit', headers=h, json=payload).status_code == 409
    payload['allow_duplicates'] = [1, 2]
    assert client.post('/imports/csv/commit', headers=h, json=payload).status_code == 200
    payload['rows'] = [1]
    assert client.post('/imports/csv/commit', headers=h, json=payload).status_code == 409


def test_csv_validation_bom_quotes_in_file_duplicates_and_owner_scope(client):
    h, _ = signup(client)
    other, _ = signup(client, 'other@example.com')
    text = '\ufeffdate,type,amount,category,note,currency\r\n2026-10-01,expense,1.25,Food,"Lunch, tea",EUR\r\n2026-10-01,expense,1.25,Food,"Lunch, tea",EUR\r\n2026-02-30,expense,5,Food,Invalid,EUR\r\n2026-10-01,expense,1.001,Food,Rounding,EUR\r\n2026-10-01,expense,1,Food,Currency,USD\r\n'
    response = client.post('/imports/csv/preview', headers=h, json={'contents': text})
    assert response.status_code == 200, response.text
    rows = response.json()['items']
    assert rows[0]['transaction']['note'] == 'Lunch, tea'
    assert rows[1]['duplicate']
    assert all(r['error'] for r in rows[2:])
    payload = {'contents': text, 'operation_id': str(uuid4()), 'rows': [1, 3], 'allow_duplicates': []}
    assert client.post('/imports/csv/commit', headers=h, json=payload).status_code == 422
    assert client.get('/transactions', headers=h).json()['total'] == 0
    payload['rows'] = [1]
    assert client.post('/imports/csv/commit', headers=h, json=payload).status_code == 200
    assert not client.post('/imports/csv/preview', headers=other, json={'contents': text}).json()['items'][0]['duplicate']
    assert client.post('/imports/csv/preview', headers=h, json={'contents': 'wrong,headers\n1,2'}).status_code == 422


def test_undo_create_edit_delete_conflicts_links_expiry_and_retries(client, monkeypatch):
    h, account = signup(client)
    other, _ = signup(client, 'other@example.com')
    saved = client.post('/transactions', headers=h, json=transaction()).json()
    create = client.get('/transaction-history', headers=h).json()['items'][0]
    assert client.post(f"/transaction-history/{create['id']}/undo", headers=other).status_code == 404
    client.put('/transactions/' + saved['id'], headers=h, json=transaction(amount=333))
    edit = client.get('/transaction-history', headers=h).json()['items'][0]
    assert client.post(f"/transaction-history/{create['id']}/undo", headers=h).status_code == 409
    assert client.post(f"/transaction-history/{edit['id']}/undo", headers=h).status_code == 200
    assert client.get('/transactions/' + saved['id'], headers=h).json()['amount'] == 1550
    client.delete('/transactions/' + saved['id'], headers=h)
    deleted = client.get('/transaction-history', headers=h).json()['items'][0]
    assert client.post(f"/transaction-history/{deleted['id']}/undo", headers=h).status_code == 200
    assert client.post(f"/transaction-history/{deleted['id']}/undo", headers=h).json()['already_undone']
    assert client.get('/transactions', headers=h).json()['total'] == 1
    db = client.app.state.repo
    db.put('transactions', dict(saved, commitment_occurrence_id='linked'))
    assert client.post(f"/transaction-history/{create['id']}/undo", headers=h).status_code == 409
    db.put('transactions', saved)
    monkeypatch.setattr(record_history, 'now', lambda: datetime(2099, 1, 1, tzinfo=timezone.utc))
    assert client.post(f"/transaction-history/{create['id']}/undo", headers=h).status_code == 409


def test_new_record_collections_deleted_with_account(client):
    h, session = signup(client)
    client.put('/balances/opening', headers=h, json=opening())
    client.post('/imports/csv/commit', headers=h, json={'contents': CSV, 'operation_id': str(uuid4()), 'rows': [1], 'allow_duplicates': []})
    assert client.delete('/auth/me', headers=h).status_code == 204
    for collection in ('opening_balances', 'balance_history', 'csv_imports', 'transaction_history', 'access_sessions'):
        assert client.app.state.repo.find(collection, user_id=session['user']['id']) == []


def test_csv_failed_commit_rolls_back_all_writes_and_concurrent_imports_deduplicate(client, monkeypatch):
    h, _ = signup(client)
    db = client.app.state.repo
    payload = {'contents': CSV, 'operation_id': str(uuid4()), 'rows': [1, 2], 'allow_duplicates': []}
    original = db.put
    def fail(collection, doc):
        if collection == 'csv_imports':
            raise RuntimeError('after transaction writes')
        return original(collection, doc)
    with monkeypatch.context() as patch:
        patch.setattr(db, 'put', fail)
        with pytest.raises(RuntimeError):
            client.post('/imports/csv/commit', headers=h, json=payload)
    assert client.get('/transactions', headers=h).json()['total'] == 0
    assert client.get('/transaction-history', headers=h).json()['total'] == 0
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda _: client.post('/imports/csv/commit', headers=h, json=payload), range(2)))
    assert all(r.status_code == 200 for r in results)
    assert results[0].json() == results[1].json()
    assert client.get('/transactions', headers=h).json()['total'] == 2


def test_opening_and_undo_failures_rollback_with_their_audit_records(client, monkeypatch):
    h, _ = signup(client)
    db = client.app.state.repo
    original = db.put
    def fail_history(collection, doc):
        if collection == 'balance_history':
            raise RuntimeError('history unavailable')
        return original(collection, doc)
    with monkeypatch.context() as patch:
        patch.setattr(db, 'put', fail_history)
        with pytest.raises(RuntimeError):
            client.put('/balances/opening', headers=h, json=opening())
    assert client.get('/balances', headers=h).json()['opening'] is None
    saved = client.post('/transactions', headers=h, json=transaction()).json()
    event = client.get('/transaction-history', headers=h).json()['items'][0]
    def fail_cash(collection, doc):
        if collection == 'funding':
            raise RuntimeError('cash marker unavailable')
        return original(collection, doc)
    with monkeypatch.context() as patch:
        patch.setattr(db, 'put', fail_cash)
        with pytest.raises(RuntimeError):
            client.post(f"/transaction-history/{event['id']}/undo", headers=h)
    assert client.get('/transactions/' + saved['id'], headers=h).status_code == 200
    assert not client.get('/transaction-history', headers=h).json()['items'][0]['undone']
