from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, timedelta, timezone
from uuid import uuid4

import pytest
from test_api import client, signup, transaction
from test_planning import profile, schedule
from app.domain import funding, funding_state
from app.domain.funding_commands import Allocation
from app.domain.errors import DomainError, ErrorKind


def state(client, h):
    r = client.get('/funding/availability', headers=h)
    assert r.status_code == 200, r.text
    return r.json()


def reviewed(s):
    return {'expected_revision': s['revision'], 'expected_planning_revision': s['planning_revision'], 'currency': 'EUR'}


def cash(client, h, amount=400000, **changes):
    body = dict(reviewed(state(client, h)), accounts=[{'name': 'Cash', 'amount': amount}],
                as_of=datetime.now(timezone.utc).isoformat(), confirmed=True, **changes)
    r = client.put('/funding/snapshot', headers=h, json=body)
    assert r.status_code == 200, r.text
    return r.json()


def plan(client, h, **changes):
    body = dict(reviewed(state(client, h)), next_income_date=None, buffer_amount=20000,
                monthly_forecast_surplus=30000, essential_allowances=[], confirmed=True)
    body.update(changes)
    r = client.put('/funding/plan', headers=h, json=body)
    assert r.status_code == 200, r.text
    return r.json()


def goal(client, h, name='Emergency', **changes):
    body = {'expected_revision': state(client, h)['revision'], 'currency': 'EUR', 'name': name,
            'kind': 'emergency', 'target_amount': 100000, 'included_in_cash': True, **changes}
    r = client.post('/goals', headers=h, json=body)
    assert r.status_code == 201, r.text
    return r.json()['goals'][-1]['id']


def move(client, h, kind='allocations', **changes):
    body = dict(reviewed(state(client, h)), operation_id=str(uuid4()), **changes)
    return client.post('/funding/' + kind, headers=h, json=body)


def setup(client, h):
    assert client.put('/financial-profile', headers=h, json=profile()).status_code == 200
    cash(client, h)


def test_missing_is_not_zero_and_confirmation_required(client):
    h, _ = signup(client)
    initial = state(client, h)
    assert not initial['usable']
    assert initial['liquid_total'] is None
    assert initial['free_to_allocate'] is None
    r = client.put('/funding/snapshot', headers=h, json=dict(reviewed(initial), accounts=[], as_of=datetime.now(timezone.utc).isoformat(), confirmed=True))
    assert r.status_code == 422
    body = dict(reviewed(initial), accounts=[{'name': 'Cash', 'amount': 0}], as_of=datetime.now(timezone.utc).isoformat(), confirmed=False)
    assert client.put('/funding/snapshot', headers=h, json=body).status_code == 422
    client.put('/financial-profile', headers=h, json=profile())
    cash(client, h, 0)
    result = plan(client, h, buffer_amount=0, monthly_forecast_surplus=0)
    assert result['usable'] and result['free_to_allocate'] == 0
    assert result['snapshot']['liquid_total'] == 0


def test_cash_essentials_reserves_and_future_income_are_distinct(client):
    h, _ = signup(client)
    setup(client, h)
    emergency = goal(client, h)
    savings = goal(client, h, 'Trip', kind='savings')
    outside = goal(client, h, 'Outside savings', included_in_cash=False, excluded_balance=500000)
    today = date.fromisoformat(state(client, h)['as_of'])
    result = plan(client, h, next_income_date=(today+timedelta(days=1)).isoformat(),
                  monthly_forecast_surplus=900000, essential_allowances=[{'name': 'Essentials', 'amount': 120000}])
    assert result['free_to_allocate'] == 260000
    assert move(client, h, amount=100000, target_id=emergency).status_code == 200
    assert move(client, h, amount=30000, target_id=savings).status_code == 200
    result = state(client, h)
    assert result['emergency_reserved'] == 100000
    assert result['savings_reserved'] == 30000
    assert result['free_to_allocate'] == 130000
    assert result['liquid_total'] == 400000
    assert move(client, h, amount=1, target_id=outside).status_code == 422
    assert client.get('/transactions', headers=h).json()['total'] == 0
    assert client.get('/funding/events', headers=h).json()['total'] == 2
    assert client.get('/funding/events?page_size=1&page=2', headers=h).json()['items'][0]['amount'] == 100000


def test_required_savings_move_from_obligations_into_reserves_once(client):
    h, _ = signup(client)
    setup(client, h)
    today = state(client, h)['as_of']
    id = goal(client, h, required_amount=100000, required_by=today)
    before = plan(client, h)
    assert before['required_savings'] == 100000
    assert before['has_unfunded_required_savings']
    assert move(client, h, amount=40000, target_id=id).status_code == 200
    partial = state(client, h)
    assert partial['required_savings'] == 60000
    assert partial['emergency_reserved'] == 40000
    assert partial['free_to_allocate'] == before['free_to_allocate']
    assert move(client, h, amount=60000, target_id=id).status_code == 200
    full = state(client, h)
    assert full['required_savings'] == 0
    assert not full['has_unfunded_required_savings']
    assert full['free_to_allocate'] == before['free_to_allocate']
    assert move(client, h, 'releases', amount=20000, source_id=id).status_code == 200
    assert state(client, h)['required_savings'] == 20000
    assert state(client, h)['free_to_allocate'] == before['free_to_allocate']


def test_linked_allowance_partial_payment_reconcile_and_overdue(client):
    h, _ = signup(client)
    setup(client, h)
    today = date.fromisoformat(state(client, h)['as_of'])
    yesterday = (today-timedelta(days=1)).isoformat()
    r = client.post('/commitments', headers=h, json=schedule(1, amount=10000, frequency='monthly', start_date=yesterday, end_date=yesterday)).json()
    id = r['commitments'][0]['id']
    before = plan(client, h, essential_allowances=[{'name': 'Housing total', 'amount': 15000, 'schedule_ids': ['commitments:'+id]}])
    assert before['scheduled_obligations'] == 10000
    assert before['essential_allowances'] == 5000
    assert before['obligations_total'] == 15000
    assert before['has_overdue_obligations']
    due = before['occurrences'][0]['id']
    payment = {'expected_revision': 2, 'operation_id': str(uuid4()), 'amount': 4000, 'date': yesterday}
    assert client.post('/commitment-occurrences/'+due+'/payments', headers=h, json=payment).status_code == 200
    stale = state(client, h)
    assert not stale['usable']
    assert stale['scheduled_obligations'] == 6000
    cash(client, h, 396000)
    after = plan(client, h, essential_allowances=[{'name': 'Housing total', 'amount': 11000, 'schedule_ids': ['commitments:'+id]}])
    assert after['free_to_allocate'] == before['free_to_allocate']
    assert after['scheduled_obligations'] == 6000
    assert after['essential_allowances'] == 5000
    duplicate = dict(reviewed(after), next_income_date=None, buffer_amount=0, monthly_forecast_surplus=0, confirmed=True,
        essential_allowances=[{'name': n, 'amount': 10000, 'schedule_ids': ['commitments:'+id]} for n in ('One','Two')])
    assert client.put('/funding/plan', headers=h, json=duplicate).status_code == 422


def test_revisions_transactions_and_snapshot_age_block_new_allocations(client, monkeypatch):
    h, session = signup(client)
    setup(client, h)
    id = goal(client, h)
    before = plan(client, h)
    body = dict(reviewed(before), operation_id=str(uuid4()), amount=100, target_id=id)
    tx = client.post('/transactions', headers=h, json=transaction()).json()
    assert not state(client, h)['usable']
    assert client.post('/funding/allocations', headers=h, json=body).status_code == 409
    assert move(client, h, amount=100, target_id=id).status_code == 409
    cash(client, h)
    assert state(client, h)['usable']
    assert client.put('/transactions/'+tx['id'], headers=h, json=transaction(amount=500)).status_code == 200
    assert not state(client, h)['usable']
    cash(client, h)
    assert client.delete('/transactions/'+tx['id'], headers=h).status_code == 204
    assert not state(client, h)['usable']
    cash(client, h)
    original = funding.now
    monkeypatch.setattr(funding, 'now', lambda: original()+timedelta(hours=25))
    assert not state(client, h)['usable']
    assert move(client, h, amount=100, target_id=id).status_code == 409


def test_reallocation_release_shortfall_and_goal_deletion_guards(client):
    h, _ = signup(client)
    setup(client, h)
    a = goal(client, h)
    b = goal(client, h, 'Savings', kind='savings')
    plan(client, h)
    assert move(client, h, amount=100000, target_id=a).status_code == 200
    assert move(client, h, 'reallocations', amount=30000, source_id=a, target_id=b).status_code == 200
    assert state(client, h)['emergency_reserved'] == 70000
    assert state(client, h)['savings_reserved'] == 30000
    s = state(client, h)
    assert client.delete(f"/goals/{a}?expected_revision={s['revision']}", headers=h).status_code == 409
    cash(client, h, 50000)  # Truthful reconciliation can reveal uncovered protected funds.
    assert state(client, h)['coverage_shortfall'] == 70000
    assert move(client, h, amount=100, target_id=b).status_code == 409
    assert move(client, h, 'releases', amount=70000, source_id=a).status_code == 200
    assert state(client, h)['coverage_shortfall'] == 0
    s = state(client, h)
    assert client.delete(f"/goals/{a}?expected_revision={s['revision']}", headers=h).status_code == 200
    assert not state(client, h)['usable']  # Goal changes require a new plan review.


def test_retry_owner_currency_export_and_delete(client):
    h, session = signup(client)
    other, _ = signup(client, 'other@example.com')
    setup(client, h)
    id = goal(client, h)
    s = plan(client, h)
    body = dict(reviewed(s), operation_id=str(uuid4()), amount=10000, target_id=id)
    saved = client.post('/funding/allocations', headers=h, json=body)
    assert saved.status_code == 200
    assert client.post('/funding/allocations', headers=h, json=body).json() == saved.json()
    assert client.post('/funding/allocations', headers=h, json=dict(body, amount=20000)).status_code == 409
    assert move(client, h, amount=100, target_id=id, currency='USD').status_code == 422
    assert move(client, other, amount=100, target_id=id).status_code == 404
    assert client.get('/funding/events', headers=other).json()['items'] == []
    assert client.get('/funding/availability').status_code == 401
    exported = client.get('/auth/me/export', headers=h).json()
    assert exported['funding'][0]['reservations'][id] == 10000
    assert len(exported['funding_events']) == 1
    assert 'operations' not in exported['funding'][0]
    assert client.delete('/auth/me', headers=h).status_code == 204
    assert not client.app.state.repo.find('funding', user_id=session['user']['id'])
    assert not client.app.state.repo.find('funding_events', user_id=session['user']['id'])


def test_competing_allocations_and_atomic_ledger_rollback(client, monkeypatch):
    h, session = signup(client)
    setup(client, h)
    id = goal(client, h)
    cash(client, h, 70000)
    s = plan(client, h, buffer_amount=0)
    db = client.app.state.repo
    user = db.get('users', id=session['user']['id'])
    def reserve(_):
        try:
            return funding.allocate('allocate', Allocation(**reviewed(s), operation_id=str(uuid4()), amount=50000, target_id=id), user, db)
        except DomainError as error:
            assert error.kind is ErrorKind.CONFLICT
            return None
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(reserve, range(2)))
    assert sum(r is not None for r in results) == 1
    assert state(client, h)['free_to_allocate'] == 20000
    s = state(client, h)
    original = db.put
    def fail(collection, doc):
        if collection == 'funding':
            raise RuntimeError('failure after ledger write')
        return original(collection, doc)
    monkeypatch.setattr(db, 'put', fail)
    with pytest.raises(RuntimeError):
        funding.allocate('allocate', Allocation(**reviewed(s), operation_id=str(uuid4()), amount=10000, target_id=id), user, db)
    assert state(client, h)['free_to_allocate'] == 20000
    assert len(db.find('funding_events', user_id=user['id'])) == 1


def test_invalid_dates_amounts_and_incomplete_obligations(client):
    h, _ = signup(client)
    setup(client, h)
    s = state(client, h)
    for timestamp in ((datetime.now(timezone.utc)-timedelta(hours=25)).isoformat(), (datetime.now(timezone.utc)+timedelta(hours=1)).isoformat(), '2026-01-01T12:00:00'):
        body = dict(reviewed(s), accounts=[{'name':'Cash','amount':0}], as_of=timestamp, confirmed=True)
        assert client.put('/funding/snapshot', headers=h, json=body).status_code == 422
    today = date.fromisoformat(s['as_of'])
    assert client.post('/debts', headers=h, json=schedule(1, amount=None, start_date=today.isoformat())).status_code == 201
    client.put('/financial-profile', headers=h, json=profile(2, debt_confirmation='complete'))
    result = plan(client, h)
    assert not result['complete']
    assert result['free_to_allocate'] is None
    assert result['coverage_shortfall'] is None
    assert any('required amount' in m for m in result['missing_inputs'])
    assert result['horizon_end'] == (today+timedelta(days=29)).isoformat()


def test_goal_edits_foreign_links_horizon_and_explicit_plan_fields(client, monkeypatch):
    h, _ = signup(client)
    setup(client, h)
    id = goal(client, h)
    s = plan(client, h)
    assert move(client, h, amount=10000, target_id=id).status_code == 200
    s = state(client, h)
    changed = {'expected_revision': s['revision'], 'currency': 'EUR', 'name': 'Outside', 'kind': 'emergency',
               'target_amount': 20000, 'included_in_cash': False, 'excluded_balance': 10000}
    assert client.put('/goals/'+id, headers=h, json=changed).status_code == 409
    assert client.put('/goals/foreign', headers=h, json=changed).status_code == 404
    changed.update(included_in_cash=True, excluded_balance=0)
    assert client.put('/goals/'+id, headers=h, json=changed).status_code == 200
    assert not state(client, h)['usable']
    s = plan(client, h)
    body = dict(reviewed(s), next_income_date=None, buffer_amount=0, monthly_forecast_surplus=0, essential_allowances=[], confirmed=True)
    today = date.fromisoformat(s['as_of'])
    for on in (today-timedelta(days=1), today+timedelta(days=367)):
        assert client.put('/funding/plan', headers=h, json=dict(body, next_income_date=on.isoformat())).status_code == 422
    assert client.put('/funding/plan', headers=h, json=dict(body, confirmed=False)).status_code == 422
    assert client.put('/funding/plan', headers=h, json=dict(body, essential_allowances=[{'name':'Rent', 'amount':1, 'schedule_ids':['commitments:foreign']}])).status_code == 404
    del body['monthly_forecast_surplus']
    assert client.put('/funding/plan', headers=h, json=body).status_code == 422
    monkeypatch.setattr(funding.planning, 'today_for', lambda _: today+timedelta(days=1))
    assert not state(client, h)['usable']
    assert any('today' in reason for reason in state(client, h)['stale_reasons'])


def test_duplicate_accounts_invalid_goals_and_cash_replay(client):
    h, _ = signup(client)
    setup(client, h)
    s = state(client, h)
    body = dict(reviewed(s), as_of=datetime.now(timezone.utc).isoformat(), confirmed=True,
                accounts=[{'name':'Bank', 'amount':10}, {'name':' bank ', 'amount':20}])
    assert client.put('/funding/snapshot', headers=h, json=body).status_code == 422
    body['accounts'] = [{'name':'Cash', 'amount':0}]
    assert client.put('/funding/snapshot', headers=h, json=body).status_code == 200
    assert client.put('/funding/snapshot', headers=h, json=body).status_code == 409
    s = state(client, h)
    new_goal = {'expected_revision':s['revision'], 'currency':'EUR', 'name':'Reserve', 'kind':'savings',
                'target_amount':10000, 'included_in_cash':True}
    for changes in ({'name':' '}, {'required_amount':100}, {'required_by':s['as_of']},
                    {'excluded_balance':100}, {'included_in_cash':False, 'required_amount':100, 'required_by':s['as_of']}):
        assert client.post('/goals', headers=h, json=dict(new_goal, **changes)).status_code == 422
