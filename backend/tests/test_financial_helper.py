from copy import deepcopy
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
from concurrent.futures import ThreadPoolExecutor
from uuid import uuid4
import pytest
from test_api import client, signup
from test_planning import profile, schedule
from app.domain import financial_helper as helper
from app.domain.errors import DomainError


def baseline(client, h, **body):
    r = client.post('/financial-helper/calculate', headers=h, json=body)
    assert r.status_code == 200, r.text
    return r.json()


def setup(client, h, amounts=(80000, 20000, 10000), **income):
    for revision, amount in enumerate(amounts):
        assert client.post('/debts', headers=h, json=schedule(revision, amount=amount, start_date='2020-01-01')).status_code == 201
    data = profile(len(amounts), debt_confirmation='complete' if amounts else 'none')
    data['income_sources'][0].update(income)
    assert client.put('/financial-profile', headers=h, json=data).status_code == 200
    return len(amounts) + 1


def test_fh01_fh02_scenario_and_explicit_snapshot(client):
    h, _ = signup(client)
    revision = setup(client, h)
    before = client.get('/financial-profile', headers=h).json()
    result = baseline(client, h)
    assert result['complete']
    assert result['ratios']['dsr']['value'] == '22.00'
    assert result['ratios']['dti']['value'] == '18.33'
    assert result['income_after_debt'] == '390000'
    assumptions = {'currency': 'EUR', 'additional_debt_monthly': 40000}
    scenario = client.post('/financial-helper/scenarios', headers=h, json={'expected_revision': revision, 'assumptions': assumptions}).json()
    assert scenario['scenario']['ratios']['dsr']['value'] == '30.00'
    assert scenario['scenario']['ratios']['dti']['value'] == '25.00'
    assert scenario['baseline']['ratios'] == result['ratios']
    assert client.get('/financial-profile', headers=h).json() == before
    assert client.get('/transactions', headers=h).json()['total'] == 0
    assert client.get('/financial-helper/snapshots', headers=h).json()['total'] == 0
    body = {'name': 'Car what-if', 'expected_revision': revision, 'effective_date': result['effective_date'], 'operation_id': str(uuid4()), 'assumptions': assumptions}
    saved = client.post('/financial-helper/snapshots', headers=h, json=body)
    assert saved.status_code == 201, saved.text
    assert saved.json()['result']['ratios'] == scenario['scenario']['ratios']
    assert client.post('/financial-helper/snapshots', headers=h, json=body).json() == saved.json()
    assert client.post('/financial-helper/snapshots', headers=h, json=dict(body, name='Different')).status_code == 409
    assert client.get('/financial-profile', headers=h).json() == before
    assert client.get('/financial-helper/snapshots', headers=h).json()['total'] == 1


@pytest.mark.parametrize('amounts,gross,net,dsr,dti,complete', [
    ((), 600000, 500000, '0.00', '0.00', True),
    ((110000,), None, 500000, '22.00', None, False),
    ((), 0, 0, None, None, False),
    ((110000,), 0, 0, None, None, False),
    ((150000,), 120000, 100000, '150.00', '125.00', True),
    ((None,), 600000, 500000, None, None, False),
])
def test_fh03_04_05_06_10_availability(client, amounts, gross, net, dsr, dti, complete):
    h, _ = signup(client)
    setup(client, h, amounts, gross=gross, net=net)
    result = baseline(client, h)
    assert result['ratios']['dsr']['value'] == dsr
    assert result['ratios']['dti']['value'] == dti
    assert result['complete'] == complete
    if dsr is None:
        assert result['ratios']['dsr']['reasons']


def test_unknown_profile_not_zero(client):
    h, _ = signup(client)
    result = baseline(client, h)
    assert result['debt_monthly'] is None
    assert result['ratios']['dsr']['value'] is None
    assert not result['complete']


def test_fh07_paid_fh08_extra_and_snapshot_freshness(client):
    h, _ = signup(client)
    client.post('/debts', headers=h, json=schedule(amount=110000, extra_payment=20000))
    client.put('/financial-profile', headers=h, json=profile(1, debt_confirmation='complete'))
    before = baseline(client, h)
    snapshot = {'name': 'Before payment', 'expected_revision': 2, 'effective_date': before['effective_date'], 'operation_id': str(uuid4())}
    assert client.post('/financial-helper/snapshots', headers=h, json=snapshot).status_code == 201
    route = '/commitment-occurrences?start=2026-02-01&end=2026-02-28'
    due = client.get(route, headers=h).json()['items'][0]
    assert due['expected_amount'] == 130000
    assert client.post(f"/commitment-occurrences/{due['id']}/payments", headers=h, json={
        'expected_revision': 2, 'operation_id': str(uuid4()), 'amount': 130000, 'date': '2026-02-28'}).status_code == 200
    after = baseline(client, h)
    assert after['ratios'] == before['ratios']
    assert after['debt_monthly'] == '110000'
    assert not client.get('/financial-helper/snapshots', headers=h).json()['items'][0]['outdated']
    assert client.get(route, headers=h).json()['items'][0]['remaining_amount'] == 0


def test_fh09_normalization_and_half_up(client):
    h, _ = signup(client)
    setup(client, h, (110000,), gross=100000, net=100000, frequency='weekly')
    result = baseline(client, h)
    assert abs(Decimal(result['net_monthly']) - Decimal('433333.3333333333333333333333')) < Decimal('1e-20')
    assert result['ratios']['dsr']['value'] == '25.38'
    assert helper.rounded(Decimal('18.325')) == '18.33'
    for frequency, amount in {'weekly': '5200', 'fortnightly': '2600', 'twice_monthly': '2400', 'monthly': '1200', 'quarterly': '400', 'annually': '100'}.items():
        assert helper.normalized(1200, frequency) == Decimal(amount)


def test_fh11_owner_currency_revision_validation(client):
    h, session = signup(client)
    other, _ = signup(client, 'other@example.com')
    revision = setup(client, h)
    debt_id = client.get('/debts', headers=h).json()['items'][0]['id']
    foreign = {'expected_revision': 0, 'assumptions': {'currency': 'EUR', 'debt_payments': [{'id': debt_id, 'monthly_payment': 100}]}}
    assert client.post('/financial-helper/scenarios', headers=other, json=foreign).status_code == 404
    for changes in ({'currency': 'USD'}, {'net_monthly': -1}, {'gross_monthly': True}, {'net_monthly': 700000}, {'user_id': session['user']['id']}):
        assert client.post('/financial-helper/scenarios', headers=h, json={'expected_revision': revision, 'assumptions': {'currency': 'EUR', **changes}}).status_code == 422
    assert client.post('/financial-helper/calculate', headers=h, json={'expected_revision': revision-1}).status_code == 409
    assert client.post('/financial-helper/calculate', json={}).status_code == 401
    assert client.get('/financial-helper/snapshots', headers=other).json()['items'] == []
    assert client.post('/financial-helper/scenarios', headers=h, json={'expected_revision': revision, 'assumptions': {'currency': 'EUR', 'net_monthly': 700000, 'notes': 'Includes differently defined allowances.'}}).status_code == 200
    plan = client.app.state.repo.get('planning', id=session['user']['id'])
    plan['profile']['income_sources'][0]['currency'] = 'USD'
    with pytest.raises(DomainError, match='account currency'):
        helper.calculate_plan(plan, 'EUR')


def test_fh12_effective_dates_and_debt_override(client):
    h, _ = signup(client)
    client.post('/debts', headers=h, json=schedule(amount=10000, start_date='2026-01-01', end_date='2026-06-30', status='closed'))
    client.post('/debts', headers=h, json=schedule(1, amount=20000, start_date='2027-01-01'))
    client.put('/financial-profile', headers=h, json=profile(2, debt_confirmation='complete'))
    assert baseline(client, h, effective_date='2026-10-01')['debt_monthly'] == '0'
    assert baseline(client, h, effective_date='2026-02-01')['debt_monthly'] == '10000'
    result = baseline(client, h, effective_date='2027-02-01')
    assert result['debt_monthly'] == '20000'
    request = {'expected_revision': 3, 'effective_date': '2027-02-01', 'assumptions': {'currency': 'EUR', 'debt_payments': [{'id': result['debts'][0]['id'], 'monthly_payment': 5000}]}}
    preview = client.post('/financial-helper/scenarios', headers=h, json=request).json()
    assert preview['scenario']['debt_monthly'] == '5000'
    assert preview['baseline']['debt_monthly'] == '20000'
    request['effective_date'] = '2026-10-01'
    assert client.post('/financial-helper/scenarios', headers=h, json=request).status_code == 422


def test_snapshot_staleness_export_delete_pagination(client):
    h, session = signup(client)
    revision = setup(client, h)
    result = baseline(client, h)
    body = {'name': 'Baseline', 'expected_revision': revision, 'effective_date': result['effective_date'], 'operation_id': str(uuid4())}
    saved = client.post('/financial-helper/snapshots', headers=h, json=body).json()
    assert not saved['outdated']
    client.post('/financial-helper/snapshots', headers=h, json=dict(body, operation_id=str(uuid4()), name='Second'))
    assert client.get('/financial-helper/snapshots?page_size=1&page=2', headers=h).json()['items'][0]['id'] == saved['id']
    updated = profile(revision, debt_confirmation='complete')
    updated['income_sources'][0]['net'] = 400000
    client.put('/financial-profile', headers=h, json=updated)
    history = client.get('/financial-helper/snapshots', headers=h).json()
    assert all(s['outdated'] for s in history['items'])
    assert history['items'][0]['result']['ratios']['dsr']['value'] == '22.00'
    assert client.post('/financial-helper/snapshots', headers=h, json=dict(body, operation_id=str(uuid4()))).status_code == 409
    exported = client.get('/auth/me/export', headers=h).json()['calculation_snapshots']
    assert len(exported) == 2
    assert 'request_hash' not in exported[0]
    assert exported[0]['result']['inputs']
    assert client.delete('/auth/me', headers=h).status_code == 204
    assert not client.app.state.repo.find('calculation_snapshots', user_id=session['user']['id'])


def test_stale_review_repeatability_no_mutation(client):
    h, session = signup(client)
    setup(client, h)
    plan = client.app.state.repo.get('planning', id=session['user']['id'])
    plan['profile']['reviewed_at'] = (datetime.now(timezone.utc) - timedelta(days=31)).isoformat()
    original = deepcopy(plan)
    a = helper.calculate_plan(plan, 'EUR', date(2026, 10, 1))
    b = helper.calculate_plan(plan, 'EUR', date(2026, 10, 1))
    assert a['review_due']
    a.pop('calculated_at'); b.pop('calculated_at')
    assert a == b
    assert plan == original


def test_concurrent_snapshot_retry_and_rollback(client, monkeypatch):
    h, session = signup(client)
    revision = setup(client, h)
    db = client.app.state.repo
    user = db.get('users', id=session['user']['id'])
    args = dict(expected_revision=revision, effective_date=date(2026, 10, 1), scenario=None, operation_id=str(uuid4()), name='Concurrent')
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda _: helper.save_snapshot(user, db, **args), range(2)))
    assert results[0]['id'] == results[1]['id']
    assert len(db.find('calculation_snapshots', user_id=user['id'])) == 1
    original = db.put
    def fail(collection, doc):
        original(collection, doc)
        raise RuntimeError('after snapshot write')
    monkeypatch.setattr(db, 'put', fail)
    with pytest.raises(RuntimeError):
        helper.save_snapshot(user, db, **dict(args, operation_id=str(uuid4())))
    assert len(db.find('calculation_snapshots', user_id=user['id'])) == 1


def test_personal_targets_and_monthly_review(client):
    h, _ = signup(client)
    revision = setup(client, h)
    data = profile(revision, debt_confirmation='complete', dsr_target='20', dti_target='25.00')
    assert client.put('/financial-profile', headers=h, json=data).status_code == 200
    result = baseline(client, h)
    assert result['ratios']['dsr']['distance_to_target'] == '2.00'
    assert result['ratios']['dti']['distance_to_target'] == '-6.67'
    review = client.get('/reports/summary?month=2026-09', headers=h).json()['review']['debt_ratios']
    assert review['effective_date'] == '2026-09-30'
    assert review['ratios'] == result['ratios']
    data.update(expected_revision=revision+1, dsr_target='-1')
    assert client.put('/financial-profile', headers=h, json=data).status_code == 422


def test_scenario_preserves_existing_explained_income_basis(client):
    h, _ = signup(client)
    revision = setup(client, h, net=700000, notes='Net includes separately defined allowances.')
    result = client.post('/financial-helper/scenarios', headers=h, json={
        'expected_revision': revision, 'assumptions': {'currency': 'EUR', 'additional_debt_monthly': 40000}})
    assert result.status_code == 200
    assert result.json()['scenario']['ratios']['dsr']['value'] == '21.43'
    assert any('allowances' in warning for warning in result.json()['scenario']['warnings'])
