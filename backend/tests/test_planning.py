from datetime import date
from concurrent.futures import ThreadPoolExecutor
from uuid import uuid4

import pytest

from test_api import client, signup, transaction
from app.domain.planning import dates, pay
from app.domain.planning_commands import Payment


def profile(revision=0, **changes):
    return dict({'expected_revision': revision, 'currency': 'EUR', 'timezone': 'UTC',
        'income_sources': [{'name': 'Salary', 'currency': 'EUR', 'gross': 600000,
            'net': 500000, 'frequency': 'monthly', 'start_date': '2020-01-01'}],
        'debt_confirmation': 'none', 'confirmed': True}, **changes)


def schedule(revision=0, **changes):
    return dict({'expected_revision': revision, 'currency': 'EUR', 'name': 'Rent',
        'amount': 10000, 'frequency': 'monthly', 'start_date': '2026-01-31',
        'category_id': 'bills'}, **changes)


def test_profile_unknown_zero_currency_review_and_revision(client):
    h, _ = signup(client)
    assert client.get('/financial-profile', headers=h).json()['complete'] is False
    saved = client.put('/financial-profile', headers=h, json=profile()).json()
    assert saved['complete'] is True
    assert saved['profile']['reviewed_at']
    assert saved['revision'] == 1
    assert client.put('/financial-profile', headers=h, json=profile()).status_code == 409
    bad = profile(1, currency='USD')
    assert client.put('/financial-profile', headers=h, json=bad).status_code == 422
    bad = profile(1, timezone='not/a-zone')
    assert client.put('/financial-profile', headers=h, json=bad).status_code == 422
    bad = profile(1)
    bad['income_sources'][0]['net'] = 700000
    assert client.put('/financial-profile', headers=h, json=bad).status_code == 422
    bad['income_sources'][0]['notes'] = 'Net includes a separately defined allowance.'
    assert client.put('/financial-profile', headers=h, json=bad).status_code == 200
    partial = profile(2)
    partial['income_sources'][0]['gross'] = None
    result = client.put('/financial-profile', headers=h, json=partial).json()
    assert result['complete'] is False
    zero = profile(3)
    zero['income_sources'][0].update(gross=0, net=0)
    assert client.put('/financial-profile', headers=h, json=zero).json()['complete'] is True


def test_variable_income_and_schedule_validation(client):
    h, _ = signup(client)
    data = profile()
    data['income_sources'][0].update(basis='monthly_estimate', notes='')
    assert client.put('/financial-profile', headers=h, json=data).status_code == 422
    data['income_sources'][0]['notes'] = 'Conservative monthly freelance estimate.'
    assert client.put('/financial-profile', headers=h, json=data).status_code == 200
    for changes in ({'amount': -1}, {'currency': 'MYR'}, {'frequency': 'daily'},
                    {'debt_type': 'credit_card'}, {'frequency': 'twice_monthly'},
                    {'status': 'closed'}, {'end_date': '2025-01-01'}):
        assert client.post('/debts', headers=h, json=schedule(1, **changes)).status_code == 422
    assert client.post('/commitments', headers=h, json=schedule(1, amount=None)).status_code == 422
    assert client.post('/debts', headers=h, json=schedule(1, amount=None)).status_code == 201
    plan = client.get('/financial-profile', headers=h).json()
    assert plan['profile']['reviewed_at'] is None
    assert plan['profile']['debt_confirmation'] == 'unknown'
    assert client.put('/financial-profile', headers=h, json=profile(2)).status_code == 422


@pytest.mark.parametrize('start,frequency,second,expected', [
    ('2024-01-31', 'monthly', None, ['2024-02-29', '2024-03-31']),
    ('2024-01-30', 'monthly', None, ['2024-02-29', '2024-03-30']),
    ('2024-02-01', 'weekly', None, ['2024-02-01', '2024-02-08', '2024-02-15', '2024-02-22', '2024-02-29', '2024-03-07', '2024-03-14', '2024-03-21', '2024-03-28']),
    ('2024-01-15', 'twice_monthly', 31, ['2024-02-15', '2024-02-29', '2024-03-15', '2024-03-31']),
    ('2024-01-31', 'quarterly', None, []),
])
def test_recurrence_keeps_original_anchor(start, frequency, second, expected):
    record = {'start_date': start, 'end_date': None, 'frequency': frequency, 'second_day': second}
    assert [d.isoformat() for d in dates(record, date(2024, 2, 1), date(2024, 3, 31))] == expected


def test_payment_partial_retry_unlink_and_no_double_counting(client):
    h, session = signup(client)
    client.put('/financial-profile', headers=h, json=profile())
    client.post('/debts', headers=h, json=schedule(1, name='Car', amount=10000, extra_payment=2000))
    client.put('/financial-profile', headers=h, json=profile(2, debt_confirmation='complete'))
    before = client.get('/financial-profile', headers=h).json()
    occurrences = client.get('/commitment-occurrences?start=2026-02-01&end=2026-02-28', headers=h).json()
    due = occurrences['items'][0]
    assert due['expected_amount'] == 12000
    assert due['paid_amount'] == 0
    payment = {'expected_revision': 3, 'operation_id': str(uuid4()), 'amount': 4000, 'date': '2026-02-28'}
    route = '/commitment-occurrences/' + due['id'] + '/payments'
    result = client.post(route, headers=h, json=payment)
    assert result.status_code == 200, result.text
    assert client.post(route, headers=h, json=payment).json() == result.json()
    assert client.post(route, headers=h, json=dict(payment, amount=5000)).status_code == 409
    txid = result.json()['transaction_id']
    assert client.get('/transactions', headers=h).json()['total'] == 1
    after = client.get('/financial-profile', headers=h).json()
    assert after['debts'] == before['debts']
    assert after['profile'] == before['profile']
    due_after = client.get('/commitment-occurrences?start=2026-02-01&end=2026-02-28', headers=h).json()['items'][0]
    assert due_after['remaining_amount'] == 8000
    assert due_after['state'] == 'partially_paid'
    assert client.delete('/transactions/' + txid, headers=h).status_code == 409
    assert client.put('/transactions/' + txid, headers=h, json=transaction()).status_code == 409
    second = client.post('/transactions', headers=h, json=transaction(amount=8000, date='2026-02-28')).json()
    linked = {'expected_revision': 4, 'operation_id': str(uuid4()), 'transaction_id': second['id']}
    assert client.post(route, headers=h, json=linked).status_code == 200
    assert client.get('/transactions', headers=h).json()['total'] == 2
    paid = client.get('/commitment-occurrences?start=2026-02-01&end=2026-02-28', headers=h).json()['items'][0]
    assert paid['state'] == 'paid'
    assert paid['remaining_amount'] == 0
    assert client.delete(route + '/' + txid + '?expected_revision=5', headers=h).status_code == 200
    assert client.delete('/transactions/' + txid, headers=h).status_code == 204
    # Replaying a previously completed operation after unlink must not recreate it.
    assert client.post(route, headers=h, json=payment).json() == result.json()
    assert client.get('/transactions', headers=h).json()['total'] == 1
    assert 'planning' in client.get('/auth/me/export', headers=h).json()
    assert client.delete('/auth/me', headers=h).status_code == 204
    assert client.app.state.repo.find('planning', user_id=session['user']['id']) == []


def test_foreign_links_stale_mutations_and_linked_schedule_guards(client):
    h, _ = signup(client)
    other, _ = signup(client, 'other@example.com')
    saved = client.post('/commitments', headers=h, json=schedule()).json()
    id = saved['commitments'][0]['id']
    assert client.get('/commitments', headers=other).json()['items'] == []
    assert client.put('/commitments/' + id, headers=other, json=schedule()).status_code == 404
    assert client.delete('/commitments/' + id + '?expected_revision=0', headers=other).status_code == 404
    due = client.get('/commitment-occurrences?start=2026-02-01&end=2026-02-28', headers=h).json()['items'][0]
    foreign = client.post('/transactions', headers=other, json=transaction()).json()
    route = '/commitment-occurrences/' + due['id'] + '/payments'
    body = {'expected_revision': 1, 'operation_id': str(uuid4()), 'transaction_id': foreign['id']}
    assert client.post(route, headers=h, json=body).status_code == 404
    body = {'expected_revision': 1, 'operation_id': str(uuid4()), 'amount': 10001, 'date': '2026-02-28'}
    assert client.post(route, headers=h, json=body).status_code == 422
    body['amount'] = 5000
    assert client.post(route, headers=h, json=body).status_code == 200
    assert client.delete('/commitments/' + id + '?expected_revision=2', headers=h).status_code == 409
    assert client.put('/commitments/' + id, headers=h, json=schedule(2, amount=7000)).status_code == 409
    assert client.put('/commitments/' + id, headers=h, json=schedule(2, status='closed', end_date='2026-02-28')).status_code == 200
    assert client.get('/commitment-occurrences?start=2026-03-01&end=2026-03-31', headers=h).json()['items'] == []


def test_atomic_rollback_and_concurrent_retry(client, monkeypatch):
    h, session = signup(client)
    client.post('/commitments', headers=h, json=schedule())
    due = client.get('/commitment-occurrences?start=2026-02-01&end=2026-02-28', headers=h).json()['items'][0]
    repo = client.app.state.repo
    user = repo.get('users', id=session['user']['id'])
    data = Payment(expected_revision=1, operation_id=str(uuid4()), amount=10000, date=date(2026, 2, 28))
    original = repo.put
    def failing(collection, doc):
        if collection == 'planning':
            raise RuntimeError('simulated write failure')
        return original(collection, doc)
    monkeypatch.setattr(repo, 'put', failing)
    with pytest.raises(RuntimeError):
        pay(due['id'], data, user, repo)
    assert repo.find('transactions', user_id=user['id']) == []
    assert repo.get('planning', id=user['id'])['revision'] == 1
    monkeypatch.setattr(repo, 'put', original)
    with ThreadPoolExecutor(max_workers=2) as executor:
        results = list(executor.map(lambda _: pay(due['id'], data, user, repo), range(2)))
    assert results[0] == results[1]
    assert len(repo.find('transactions', user_id=user['id'])) == 1
