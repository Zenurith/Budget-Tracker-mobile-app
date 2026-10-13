from datetime import datetime, timedelta

from test_api import client, signup, transaction
from test_funding import cash, goal, move, plan, setup, state


def dashboard(client, headers, month='2000-01'):
    response = client.get('/reports/summary', params={'month': month}, headers=headers)
    assert response.status_code == 200, response.text
    return response.json()['dashboard']


def test_setup_unknown_and_zero_are_distinct_and_reads_do_not_save(client):
    h, _ = signup(client)
    first = dashboard(client, h)
    assert not first['setup']['complete']
    assert not any(step['done'] for step in first['setup']['steps'])
    assert first['availability']['free_to_allocate'] is None
    before = state(client, h)
    assert dashboard(client, h) == first
    assert state(client, h) == before
    setup(client, h)
    cash(client, h, 0)
    plan(client, h, buffer_amount=0)
    result = dashboard(client, h)
    assert result['availability']['usable']
    assert result['availability']['free_to_allocate'] == 0
    assert next(s for s in result['setup']['steps'] if s['id'] == 'cash')['done']


def test_dashboard_uses_existing_funding_arithmetic_and_invalidates_after_spend(client):
    h, _ = signup(client)
    setup(client, h)
    emergency = goal(client, h)
    today = state(client, h)['as_of']
    payday = (datetime.fromisoformat(today) + timedelta(days=7)).date().isoformat()
    plan(client, h, next_income_date=payday,
         essential_allowances=[{'name': 'Food', 'amount': 120000}],
         monthly_forecast_surplus=900000)
    assert move(client, h, amount=100000, target_id=emergency).status_code == 200
    result = dashboard(client, h)['availability']
    assert result['free_to_allocate'] == 160000
    assert result['next_income_date'] == payday
    assert result['horizon_end'] == payday
    assert result['usable']
    assert result['cash_reviewed_at']
    assert datetime.fromisoformat(result['expires_at']) > datetime.fromisoformat(result['cash_reviewed_at'])
    response = client.post('/transactions', headers=h, json=transaction(date=today))
    assert response.status_code == 201, response.text
    assert not dashboard(client, h)['availability']['usable']


def test_setup_is_owner_scoped_and_budget_uses_current_month_not_report_month(client):
    h, _ = signup(client)
    setup(client, h)
    plan(client, h)
    period = dashboard(client, h)['setup']['budget_month']
    response = client.post('/budgets', headers=h, json={
        'period': period, 'limit_amount': 100000, 'alert_threshold': 80})
    assert response.status_code == 201, response.text
    result = dashboard(client, h)
    assert result['setup']['complete']
    assert not next(s for s in result['setup']['steps'] if s['id'] == 'savings')['done']
    other, _ = signup(client, email='other@example.com')
    assert not dashboard(client, other)['setup']['complete']
    assert dashboard(client, other)['availability']['liquid_total'] is None
