from uuid import uuid4
from test_api import client, signup
from test_planning import profile, schedule


def scenario():
    return dict(operation_id=str(uuid4()), name='Extra payment', currency='EUR', first_month='2026-11', extra=10000,
                debts=[dict(name='Loan', balance=200000, rate=1200, minimum=10000)])


def test_scenario_retry_owner_export_delete(client):
    h, session = signup(client)
    other, _ = signup(client, 'other@example.com')
    payload = scenario()
    first = client.post('/debt-scenarios', headers=h, json=payload)
    assert first.status_code == 201, first.text
    saved = first.json()
    assert client.post('/debt-scenarios', headers=h, json=payload).json() == saved
    assert client.post('/debt-scenarios', headers=h, json=dict(payload, extra=1)).status_code == 409
    assert client.get('/debt-planner', headers=other).json()['scenarios'] == []
    client.delete('/debt-scenarios/' + saved['id'], headers=other)
    assert len(client.get('/debt-planner', headers=h).json()['scenarios']) == 1
    assert client.get('/auth/me/export', headers=h).json()['debt_scenarios'][0]['id'] == saved['id']
    assert client.get('/transactions', headers=h).json()['total'] == 0
    client.delete('/auth/me', headers=h)
    assert client.app.state.repo.find('debt_scenarios', user_id=session['user']['id']) == []


def test_import_preserves_unknowns_and_scenario_validation(client):
    h, _ = signup(client)
    client.put('/financial-profile', headers=h, json=profile())
    assert client.post('/debts', headers=h, json=schedule(1, outstanding_balance=200000, frequency='weekly')).status_code == 201
    data = client.get('/debt-planner', headers=h).json()
    assert data['debts'][0]['balance'] == 200000
    assert data['debts'][0]['minimum'] is None and data['debts'][0]['rate'] is None
    payload = scenario()
    for change in ({'debts': []}, {'first_month': '2026-13'}, {'first_month': '9999-01'}, {'extra': -1}):
        assert client.post('/debt-scenarios', headers=h, json=dict(payload, **change)).status_code == 422
    assert client.post('/debt-scenarios', headers=h, json=dict(payload, currency='MYR')).status_code == 422
    assert client.get('/debt-planner').status_code == 401
    saved = client.post('/debt-scenarios', headers=h, json=payload).json()
    assert client.delete('/debt-scenarios/' + saved['id'], headers=h).status_code == 204
    assert client.get('/debt-planner', headers=h).json()['scenarios'] == []
