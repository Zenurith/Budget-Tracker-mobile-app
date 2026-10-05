from concurrent.futures import ThreadPoolExecutor
from datetime import date
from uuid import uuid4
import pytest
from test_api import client, signup, transaction
from app.domain import finance, transaction_sync, funding_state
from app.domain.commands import Transaction
from app.domain.errors import DomainError, ErrorKind
from app.repositories.documents import LocalRepository


def operation(action='create', **kwargs):
    return dict(operation_id=str(uuid4()), action=action, **kwargs)


def test_sync_retries_versions_conflicts_and_deletion(client):
    h, session = signup(client)
    payload = operation(transaction=transaction())
    first = client.post('/transactions/sync', headers=h, json=payload)
    assert first.status_code == 200, first.text
    record = first.json()['transaction']
    assert len(record['version']) == 64
    assert client.post('/transactions/sync', headers=h, json=payload).json() == first.json()
    assert client.get('/transactions', headers=h).json()['total'] == 1
    assert client.get('/transactions/'+record['id'], headers=h).json() == record
    edited = operation('update', transaction_id=record['id'], expected_version=record['version'], transaction=transaction(amount=200))
    saved = client.post('/transactions/sync', headers=h, json=edited).json()['transaction']
    assert saved['amount'] == 200 and saved['version'] != record['version']
    edited['operation_id'] = str(uuid4())
    assert client.post('/transactions/sync', headers=h, json=edited).status_code == 409
    edited['expected_version'] = saved['version']
    assert client.post('/transactions/sync', headers=h, json=edited).status_code == 200
    deleted = operation('delete', transaction_id=record['id'], expected_version=saved['version'])
    result = client.post('/transactions/sync', headers=h, json=deleted)
    assert result.status_code == 200 and result.json()['transaction'] is None
    assert client.post('/transactions/sync', headers=h, json=deleted).json() == result.json()
    # Replaying an old create returns its original result without resurrecting it.
    assert client.post('/transactions/sync', headers=h, json=payload).json() == first.json()
    assert client.get('/transactions', headers=h).json()['total'] == 0
    exported = client.get('/auth/me/export', headers=h).json()
    assert 'transaction_operations' not in exported
    assert client.delete('/auth/me', headers=h).status_code == 204
    assert client.app.state.repo.find('transaction_operations', user_id=session['user']['id']) == []


def test_sync_validation_owner_and_link_guards(client):
    h, session = signup(client)
    other, _ = signup(client, 'other@example.com')
    payload = operation(transaction=transaction())
    record = client.post('/transactions/sync', headers=h, json=payload).json()['transaction']
    payload['transaction']['amount'] = 999
    assert client.post('/transactions/sync', headers=h, json=payload).status_code == 409
    assert client.get('/transactions/'+record['id'], headers=other).status_code == 404
    request = operation('delete', transaction_id=record['id'], expected_version=record['version'])
    assert client.post('/transactions/sync', headers=other, json=request).status_code == 404
    for invalid in [operation('update'), operation('create'), operation('delete', transaction_id=record['id']), operation(transaction=transaction(amount=1.1))]:
        assert client.post('/transactions/sync', headers=h, json=invalid).status_code == 422
    for link in ['wishlist_purchase_id', 'commitment_occurrence_id']:
        repo = client.app.state.repo
        original = repo.get('transactions', id=record['id'])
        linked = dict(original, **{link: 'linked'})
        repo.put('transactions', linked)
        # Even a reviewed current version cannot bypass coordinated link correction.
        request['expected_version'] = client.get('/transactions/'+record['id'], headers=h).json()['version']
        assert client.post('/transactions/sync', headers=h, json=request).status_code == 409
        repo.put('transactions', original)


def exercise_sync_atomicity(first, second, monkeypatch):
    user = dict(id=str(uuid4()), currency='EUR')
    owner = user['id']
    first.put('users', user)
    command = transaction_sync.Operation(operation_id=str(uuid4()), action='create', transaction=Transaction(amount=100, type='expense', category_id='food', date=date.today()))
    try:
        before = funding_state.load(user, first)
        put = type(first).put
        def fail(self, collection, doc):
            result = put(self, collection, doc)
            if collection == 'transaction_operations':
                raise RuntimeError('failure after transaction and replay writes')
            return result
        with monkeypatch.context() as patch:
            patch.setattr(type(first), 'put', fail)
            with pytest.raises(RuntimeError):
                transaction_sync.apply(command, user, first)
        assert second.find('transactions', user_id=owner) == []
        assert funding_state.load(user, second) == before
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda repo: transaction_sync.apply(command, user, repo), [first, second]))
        assert results[0] == results[1]
        assert len(second.find('transactions', user_id=owner)) == 1
        saved = results[0]['transaction']
        def edit(repo):
            op = transaction_sync.Operation(operation_id=str(uuid4()), action='update', transaction_id=saved['id'], expected_version=saved['version'], transaction=Transaction(amount=200, type='expense', category_id='food', date=date.today()))
            try:
                return transaction_sync.apply(op, user, repo)
            except DomainError as e:
                assert e.kind is ErrorKind.CONFLICT
                return None
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(edit, [first, second]))
        assert sum(r is not None for r in results) == 1
        assert funding_state.load(user, second)['cash_revision'] == before['cash_revision'] + 2
    finally:
        for collection in ['transactions', 'transaction_operations', 'funding']:
            first.delete(collection, user_id=owner)
        first.delete('users', id=owner)


def test_sync_atomicity(monkeypatch):
    repo = LocalRepository(':memory:')
    try:
        exercise_sync_atomicity(repo, repo, monkeypatch)
    finally:
        repo.close()
