from datetime import date, timedelta
from uuid import uuid4
from test_api import client, signup, transaction
from test_funding import state, reviewed, cash, plan, goal, move, setup
from test_planning import schedule


def read(c, h):
    r = c.get('/wishlist', headers=h)
    assert r.status_code == 200, r.text
    return r.json()


def item(c, h, id=None, **changes):
    body = dict(expected_revision=state(c, h)['revision'], currency='EUR', name='Camera', target_cost=50000)
    body.update(changes)
    r = c.request('PUT' if id else 'POST', '/wishlist' + ('/' + id if id else ''), headers=h, json=body)
    assert r.status_code == (200 if id else 201), r.text
    return next(i for i in r.json()['wishlist'] if i['id'] == id) if id else next(i for i in r.json()['wishlist'] if i['name'] == body['name'])


def baseline(c, h):
    setup(c, h)
    e = goal(c, h)
    g = goal(c, h, 'Savings', kind='savings')
    plan(c, h, essential_allowances=[dict(name='Essentials', amount=120000)])
    a, b = item(c, h), item(c, h, name='Other')
    for id, amount in [(e, 100000), (g, 30000), (a['id'], 50000), (b['id'], 10000)]:
        assert move(c, h, target_id=id, amount=amount).status_code == 200
    return a['id'], b['id']


def body(c, h, id, **changes):
    s = read(c, h)
    current = next(i for i in s['wishlist'] if i['id'] == id)
    result = dict(reviewed(s), operation_id=str(uuid4()), amount=50000, date=s['as_of'], category_id='shopping',
                  confirmed=True, baseline_effect='subtract_from_prior_snapshot', quote=current['quote'], account_name='Cash')
    result.update(changes)
    return result


def buy(c, h, id, payload=None):
    return c.post(f'/wishlist/{id}/purchases', headers=h, json=payload or body(c, h, id))


def test_wl01_wl09_purchase_retry_excess(client):
    h, _ = signup(client)
    a, b = baseline(client, h)
    s = read(client, h)
    assert s['free_to_allocate'] == 70000
    assert next(i for i in s['wishlist'] if i['id'] == a)['readiness'] == 'Ready under your plan'
    payload = body(client, h, a)
    r = buy(client, h, a, payload)
    assert r.status_code == 200, r.text
    assert buy(client, h, a, payload).json() == r.json()
    s = read(client, h)
    assert (s['liquid_total'], s['wishlist_reserved'], s['free_to_allocate']) == (350000, 10000, 70000)
    assert s['snapshot']['accounts'][0]['amount'] == 350000 and s['usable']
    assert client.get('/transactions', headers=h).json()['total'] == 1
    payload['amount'] += 1
    assert buy(client, h, a, payload).status_code == 409
    item(client, h, b, name='Other', target_cost=5000)
    assert read(client, h)['wishlist_reserved'] == 10000
    assert buy(client, h, b, body(client, h, b, amount=5000)).status_code == 200
    assert read(client, h)['free_to_allocate'] == 75000


def test_wl02_wl05_wl06_forecasts(client):
    h, _ = signup(client)
    a, _ = baseline(client, h)
    start = date(date.fromisoformat(read(client, h)['as_of']).year + 1, 1, 31)
    current = item(client, h, a, target_cost=90000, monthly_contribution=20000, next_contribution_date=start.isoformat())
    assert current['readiness'] == 'Still saving' and current['remaining_target'] == 40000
    assert current['months_needed'] == 2 and current['forecast_date'] == f'{start.year}-02-28'
    assert read(client, h)['free_to_allocate'] == 70000
    item(client, h, name='Competing plan', monthly_contribution=20000, next_contribution_date=start.isoformat())
    assert all(i['forecast_date'] is None for i in read(client, h)['wishlist'])
    for surplus in (0, -100):
        plan(client, h, monthly_forecast_surplus=surplus)
        assert all(i['forecast_date'] is None for i in read(client, h)['wishlist'])


def test_wl04_wl07_wl08(client):
    h, _ = signup(client)
    a, _ = baseline(client, h)
    paused = item(client, h, a, status='paused')
    assert paused['funded_amount'] == 50000 and paused['readiness'] == 'Review your plan'
    assert read(client, h)['wishlist_reserved'] == 60000
    assert move(client, h, target_id=a, amount=1).status_code == 409
    item(client, h, a)
    plan(client, h, essential_allowances=[dict(name='Essentials', amount=220000)])
    s = read(client, h)
    assert s['coverage_shortfall'] == 30000
    assert all(i['readiness'] == 'Review your plan' for i in s['wishlist'])
    client.post('/transactions', headers=h, json=transaction(amount=1))
    assert all(i['readiness'] == 'Needs updated information' for i in read(client, h)['wishlist'])


def test_wl11_reconciled_existing_and_missing(client):
    h, _ = signup(client)
    a, b = baseline(client, h)
    t = client.post('/transactions', headers=h, json=transaction(amount=50000, category_id='shopping', date=read(client, h)['as_of'])).json()
    assert buy(client, h, a, body(client, h, a, baseline_effect='already_reconciled', transaction_id=t['id'])).status_code == 409
    cash(client, h, 350000)
    payload = body(client, h, a, baseline_effect='already_reconciled', transaction_id=t['id'], snapshot_token=read(client, h)['snapshot_token'])
    r = buy(client, h, a, payload)
    assert r.status_code == 200, r.text
    s = read(client, h)
    assert s['liquid_total'] == 350000 and s['free_to_allocate'] == 70000
    assert s['purchases'][0]['readiness'] == 'not_assessed'
    assert client.get('/transactions', headers=h).json()['total'] == 1
    assert buy(client, h, b, body(client, h, b, baseline_effect='already_reconciled', transaction_id=t['id'], snapshot_token=s['snapshot_token'])).status_code == 409
    cash(client, h, 300000)
    assert buy(client, h, b, body(client, h, b, baseline_effect='already_reconciled', snapshot_token=read(client, h)['snapshot_token'])).status_code == 200
    assert read(client, h)['liquid_total'] == 300000
    assert client.get('/transactions', headers=h).json()['total'] == 2


def test_wl14_overdue_quote_and_actual_cost(client):
    h, _ = signup(client)
    a, _ = baseline(client, h)
    old = body(client, h, a)
    item(client, h, a, target_cost=60000)
    assert buy(client, h, a, old).status_code == 409
    assert buy(client, h, a, body(client, h, a, amount=60000)).status_code == 409
    due = (date.fromisoformat(read(client, h)['as_of']) - timedelta(days=1)).isoformat()
    r = client.post('/commitments', headers=h, json=schedule(start_date=due, amount=100, expected_revision=read(client, h)['planning_revision']))
    assert r.status_code == 201, r.text
    plan(client, h)
    current = item(client, h, a)
    assert current['readiness'] == 'Review your plan' and 'overdue' in ' '.join(current['reasons'])


def test_reversal_refund_and_guards(client):
    h, _ = signup(client)
    a, _ = baseline(client, h)
    r = buy(client, h, a).json()
    tid, pid = r['transaction_id'], r['purchase_id']
    assert client.delete('/transactions/' + tid, headers=h).status_code == 409
    assert client.put('/transactions/' + tid, headers=h, json=transaction()).status_code == 409
    assert client.delete('/wishlist/' + a, headers=h, params={'expected_revision': read(client, h)['revision']}).status_code == 409
    payload = dict(expected_revision=read(client, h)['revision'], currency='EUR', operation_id=str(uuid4()),
                   confirmed=True, reason='Partial refund received', amount=20000, date=read(client, h)['as_of'], category_id='other-income')
    url = f'/wishlist-purchases/{pid}/refund'
    r = client.post(url, headers=h, json=payload)
    assert r.status_code == 200, r.text
    assert client.post(url, headers=h, json=payload).json() == r.json()
    assert not read(client, h)['usable']
    cash(client, h, 370000)
    assert read(client, h)['free_to_allocate'] == 90000
    payload.update(expected_revision=read(client, h)['revision'], operation_id=str(uuid4()), amount=40000)
    assert client.post(url, headers=h, json=payload).status_code == 409
    payload = dict(expected_revision=read(client, h)['revision'], currency='EUR', operation_id=str(uuid4()), confirmed=True, reason='Wrong item linked')
    url = f'/wishlist-purchases/{pid}/reverse'
    r = client.post(url, headers=h, json=payload)
    assert r.status_code == 200, r.text
    assert client.post(url, headers=h, json=payload).json() == r.json()
    s = read(client, h)
    assert not s['usable'] and s['wishlist_reserved'] == 10000
    assert client.get('/transactions', headers=h).json()['total'] == 2
    assert client.delete('/transactions/' + tid, headers=h).status_code == 204


def test_ownership_currency_reallocation_validation(client):
    h, _ = signup(client)
    other, _ = signup(client, 'other@example.com')
    a, b = baseline(client, h)
    assert client.put('/wishlist/' + a, headers=other, json=dict(expected_revision=0, currency='EUR', name='No', target_cost=1)).status_code == 404
    assert buy(client, h, a, body(client, h, a, currency='USD')).status_code == 422
    assert move(client, h, 'reallocations', source_id=a, target_id=b, amount=5000).status_code == 200
    assert read(client, h)['wishlist_reserved'] == 60000
    empty = item(client, h, name='Empty')
    assert client.delete('/wishlist/' + empty['id'], headers=h, params={'expected_revision': read(client, h)['revision']}).status_code == 200
    payload = dict(expected_revision=state(client, h)['revision'], currency='EUR', name='Invalid', target_cost=1.5)
    assert client.post('/wishlist', headers=h, json=payload).status_code == 422
    payload.update(target_cost=1, reference_url='javascript:alert(1)')
    assert client.post('/wishlist', headers=h, json=payload).status_code == 422


def test_export_deletion_report_and_stale_snapshot(client):
    from datetime import datetime, timezone
    h, session = signup(client)
    a, _ = baseline(client, h)
    purchase = buy(client, h, a).json()
    exported = client.get('/auth/me/export', headers=h).json()
    assert exported['funding'][0]['purchases'][purchase['purchase_id']]['amount'] == 50000
    assert 'operations' not in exported['funding'][0]
    month = read(client, h)['as_of'][:7]
    report = client.get('/reports/summary', headers=h, params={'month': month})
    assert report.status_code == 200, report.text
    assert report.json()['review']['funding']['purchase_total'] == 50000
    repo = client.app.state.repo
    state_doc = repo.get('funding', id=session['user']['id'])
    state_doc['snapshot']['as_of'] = (datetime.now(timezone.utc) - timedelta(hours=25)).isoformat()
    repo.put('funding', state_doc)
    assert all(i['readiness'] == 'Needs updated information' for i in read(client, h)['wishlist'])
    assert client.delete('/auth/me', headers=h).status_code in (200, 204)
    for collection in ('funding', 'funding_events', 'transactions'):
        assert repo.find(collection, user_id=session['user']['id']) == []
