"""Opt-in test against a disposable Supabase project with the migration applied."""
import os
from concurrent.futures import ThreadPoolExecutor
from uuid import uuid4

import pytest

from app.domain.ports import DuplicateRecordError
from app.repositories.supabase import SupabaseRepository
from fastapi.testclient import TestClient
from app.main import create_app


def test_supabase_persistence_isolation_uniqueness_and_atomic_consume():
    url = os.getenv('TEST_SUPABASE_DB_URL')
    if not url:
        pytest.skip('Set TEST_SUPABASE_DB_URL to a migrated disposable Supabase project.')
    first = SupabaseRepository(url)
    second = None
    prefix = str(uuid4())
    try:
        second = SupabaseRepository(url)
        owner = prefix + '-owner'
        doc = {'id': prefix + '-user', 'email': prefix + '@example.com', 'test_run': prefix}
        first.put('users', doc)
        assert second.get('users', id=doc['id']) == doc
        with pytest.raises(DuplicateRecordError):
            first.put('users', dict(doc, id=prefix + '-duplicate'))
        assert first.get('users', id=doc['id']) == doc
        transaction = {'id': prefix + '-tx', 'user_id': owner, 'amount': 120, 'test_run': prefix}
        first.put('transactions', transaction)
        assert second.find('transactions', user_id=owner) == [transaction]
        assert second.get('transactions', id=transaction['id'], user_id='other') is None
        assert second.delete('transactions', id=transaction['id'], user_id='other') == 0
        transaction['amount'] = 240
        second.put('transactions', transaction)
        assert first.get('transactions', id=transaction['id'])['amount'] == 240
        budget = {'id': prefix + '-budget', 'user_id': owner, 'period': '2026-09',
                  'category_id': 'food', 'test_run': prefix}
        first.put('budgets', budget)
        with pytest.raises(DuplicateRecordError):
            second.put('budgets', dict(budget, id=prefix + '-duplicate-budget'))
        overall = dict(budget, id=prefix + '-overall', category_id=None)
        first.put('budgets', overall)
        with pytest.raises(DuplicateRecordError):
            second.put('budgets', dict(overall, id=prefix + '-duplicate-overall'))
        token = {'id': prefix + '-session', 'user_id': owner, 'test_run': prefix}
        first.put('sessions', token)
        with ThreadPoolExecutor(max_workers=2) as executor:
            futures = [executor.submit(repo.consume, 'sessions', token['id']) for repo in (first, second)]
            results = [future.result() for future in futures]
        assert results.count(token) == 1
        assert results.count(None) == 1
        assert first.consume('sessions', token['id']) is None
        assert second.delete('transactions', user_id=owner) == 1
        assert first.find('transactions', user_id=owner) == []
    finally:
        try:
            for collection in ('users', 'transactions', 'budgets', 'sessions'):
                first.delete(collection, test_run=prefix)
        finally:
            first.close()
            if second:
                second.close()


def test_supabase_api_profile_export_and_account_isolation(monkeypatch):
    url = os.getenv('TEST_SUPABASE_DB_URL')
    if not url:
        pytest.skip('Set TEST_SUPABASE_DB_URL to a migrated disposable Supabase project.')
    monkeypatch.setenv('DATABASE_MODE', 'supabase')
    prefix = str(uuid4())
    emails = [f'{prefix}-{i}@example.com' for i in range(2)]
    repo = SupabaseRepository(url)
    second = None
    secret = 'integration-test-only-secret-' + prefix
    try:
        with TestClient(create_app(repo, secret=secret)) as client:
            accounts = []
            for email in emails:
                response = client.post('/auth/register', json={
                    'name': 'Integration check', 'email': email,
                    'password': 'test-only-' + prefix, 'currency': 'EUR',
                })
                assert response.status_code == 201
                accounts.append(response.json())
            headers, other = [{'Authorization': 'Bearer ' + a['access_token']} for a in accounts]
            assert client.get('/health').json()['storage'] == 'supabase'
            assert client.put('/auth/me', headers=headers, json={'name': 'Updated name'}).status_code == 200
            transaction = {'amount': 1234, 'type': 'expense', 'category_id': 'food',
                           'date': '2026-09-30', 'note': 'Temporary integration check'}
            response = client.post('/transactions', headers=headers, json=transaction)
            assert response.status_code == 201
            txid = response.json()['id']
            assert client.get('/transactions', headers=other).json()['items'] == []
            assert client.delete('/transactions/' + txid, headers=other).status_code == 404
            assert client.put('/transactions/' + txid, headers=other, json=transaction).status_code == 404
            category = client.post('/categories', headers=headers,
                                   json={'name': 'Books', 'icon': 'movie', 'color': '#AC8FC0'}).json()
            assert category['icon'] == 'movie'
            assert category['color'] == '#AC8FC0'
            previous = client.post('/transactions', headers=headers,
                                   json=dict(transaction, date='2026-08-31', amount=2345,
                                             category_id=category['id'])).json()
            query = '/transactions?start=2026-08-31&end=2026-09-30&page_size=1'
            assert client.get(query, headers=headers).json()['total'] == 2
            assert client.get(query + '&page=2', headers=headers).json()['items'][0]['id'] == previous['id']
            assert client.get(query + '&max_amount=1234', headers=headers).json()['total'] == 1
            assert client.get(query + '&q=books', headers=headers).json()['items'][0]['id'] == previous['id']
            review = client.get('/reports/summary?month=2026-09', headers=headers).json()['review']
            assert review['expense_change'] == 1234 - 2345
            assert review['previous_record_count'] == 1
        # A separate API instance and pool must observe the persisted account/data.
        second = SupabaseRepository(url)
        with TestClient(create_app(second, secret=secret)) as client:
            exported = client.get('/auth/me/export', headers=headers)
            assert exported.status_code == 200
            assert exported.json()['account']['name'] == 'Updated name'
            assert {t['id'] for t in exported.json()['transactions']} == {txid, previous['id']}
            assert any(c['id'] == category['id'] and c['color'] == '#AC8FC0'
                       for c in exported.json()['categories'])
            assert 'password_hash' not in exported.text
            assert client.get('/auth/me/export', headers=other).json()['transactions'] == []
            assert client.delete('/auth/me', headers=headers).status_code == 204
            assert client.get('/auth/me/export', headers=headers).status_code == 401
            assert client.get('/auth/me', headers=other).status_code == 200
            assert second.find('transactions', user_id=accounts[0]['user']['id']) == []
    finally:
        try:
            for email in emails:
                user = repo.get('users', email=email)
                if user:
                    for collection in ('transactions', 'budgets', 'categories', 'sessions'):
                        repo.delete(collection, user_id=user['id'])
                    repo.delete('users', id=user['id'])
        finally:
            repo.close()
            if second:
                second.close()


def test_supabase_planning_atomic_rollback_and_concurrent_payments(monkeypatch):
    from datetime import date
    from app.domain import planning
    from app.domain.planning_commands import Schedule, Payment
    from app.domain.errors import DomainError, ErrorKind
    url = os.getenv('TEST_SUPABASE_DB_URL')
    if not url:
        pytest.skip('Set TEST_SUPABASE_DB_URL to a migrated disposable Supabase project.')
    first = SupabaseRepository(url)
    second = None
    owner = str(uuid4())
    user = {'id': owner, 'email': owner + '@example.com', 'currency': 'EUR'}
    try:
        second = SupabaseRepository(url)
        first.put('users', user)
        saved = planning.save_schedule('commitments', Schedule(expected_revision=0,
            name='Atomic test', currency='EUR', amount=100, frequency='monthly',
            start_date=date(2026, 1, 31), category_id='bills'), user, first)
        id = saved['commitments'][0]['id']
        due = f'commitments:{id}:2026-01-31'
        payment = Payment(expected_revision=1, operation_id=str(uuid4()), amount=100, date=date(2026, 1, 31))
        original = SupabaseRepository.put
        def failing(self, collection, doc):
            if collection == 'planning':
                raise RuntimeError('simulated second-write failure')
            return original(self, collection, doc)
        with monkeypatch.context() as patch:
            patch.setattr(SupabaseRepository, 'put', failing)
            with pytest.raises(RuntimeError):
                planning.pay(due, payment, user, first)
        assert second.find('transactions', user_id=owner) == []
        assert second.get('planning', id=owner)['revision'] == 1
        with ThreadPoolExecutor(max_workers=2) as executor:
            futures = [executor.submit(planning.pay, due, payment, user, repo) for repo in (first, second)]
            results = [f.result() for f in futures]
        assert results[0] == results[1]
        assert len(first.find('transactions', user_id=owner)) == 1
        def competing(repo):
            try:
                return planning.pay(f'commitments:{id}:2026-02-28',
                    Payment(expected_revision=2, operation_id=str(uuid4()), amount=60,
                            date=date(2026, 2, 28)), user, repo)
            except DomainError as error:
                assert error.kind is ErrorKind.CONFLICT
                return None
        with ThreadPoolExecutor(max_workers=2) as executor:
            results = list(executor.map(competing, (first, second)))
        assert sum(r is not None for r in results) == 1
        items = planning.list_occurrences(date(2026, 2, 1), date(2026, 2, 28), user, first)['items']
        assert items[0]['paid_amount'] == 60
        assert items[0]['remaining_amount'] == 40
        assert len(second.find('transactions', user_id=owner)) == 2
    finally:
        try:
            for collection in ('planning', 'transactions'):
                first.delete(collection, user_id=owner)
            first.delete('users', id=owner)
        finally:
            first.close()
            if second:
                second.close()
