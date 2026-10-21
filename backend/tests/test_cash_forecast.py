from datetime import date, timedelta
from test_api import client, signup, transaction
from test_funding import setup, plan, state, cash
from test_planning import schedule


def forecast(client, h, **changes):
    return client.post('/funding/forecast', headers=h, json=dict(daily_spending=100, buffer=1000, **changes))


def test_projection_is_read_only_and_isolated(client):
    h, _ = signup(client)
    setup(client, h)
    before = plan(client, h)
    today = before['as_of']
    result = forecast(client, h, income_date=today, income_amount=10000,
                      extra_expense_date=today, extra_expense_amount=5000).json()
    assert result['ready']
    assert result['ending_balance'] == 402000
    assert result['minimum_balance'] == 394900
    assert len(result['events']) == 32
    assert state(client, h) == before
    assert client.get('/transactions', headers=h).json()['total'] == 0
    other, _ = signup(client, 'other@example.com')
    blocked = forecast(client, other).json()
    assert not blocked['ready'] and 'events' not in blocked
    assert client.post('/funding/forecast', json={'daily_spending': 0, 'buffer': 0}).status_code == 401


def test_same_day_shortfall_and_stale_cash(client):
    h, _ = signup(client)
    setup(client, h)
    today = plan(client, h)['as_of']
    result = forecast(client, h, income_date=today, income_amount=500000,
                      extra_expense_date=today, extra_expense_amount=450000).json()
    assert result['minimum_balance'] == -50100
    assert result['first_negative'] == today
    assert result['first_below_buffer'] == today
    assert result['ending_balance'] > 0
    client.post('/transactions', headers=h, json=transaction())
    blocked = forecast(client, h).json()
    assert not blocked['ready'] and 'ending_balance' not in blocked


def test_event_validation_and_overdue_obligation(client):
    h, _ = signup(client)
    setup(client, h)
    today = date.fromisoformat(state(client, h)['as_of'])
    yesterday = (today - timedelta(days=1)).isoformat()
    assert client.post('/commitments', headers=h, json=schedule(
        1, amount=10000, start_date=yesterday, end_date=yesterday)).status_code == 201
    cash(client, h)
    plan(client, h)
    result = forecast(client, h).json()
    assert result['ready']
    obligation = next(e for e in result['events'] if e['kind'] == 'obligation')
    assert obligation['overdue'] and obligation['date'] == today.isoformat()
    assert result['ending_balance'] == 387000
    for changes in [
        {'income_amount': 100},
        {'income_date': today.isoformat()},
        {'income_date': (today + timedelta(days=30)).isoformat(), 'income_amount': 100},
        {'income_date': yesterday, 'income_amount': 100},
        {'income_date': today.isoformat(), 'income_amount': 0},
    ]:
        assert forecast(client, h, **changes).status_code == 422


def test_multiple_events_and_validation(client):
    h, _ = signup(client)
    setup(client, h)
    today = date.fromisoformat(plan(client, h)['as_of'])
    events = [dict(name='Salary', kind='income', amount=100000, date=today.isoformat()),
              dict(name='Repair', kind='expense', amount=450000, date=today.isoformat()),
              dict(name='Freelance', kind='income', amount=20000, date=(today+timedelta(days=29)).isoformat())]
    result = forecast(client, h, events=events).json()
    assert result['ready'] and result['ending_balance'] == 67000
    assert result['minimum_balance'] == -50100 and result['first_negative'] == today.isoformat()
    assert len(result['events']) == 33
    assert any(e['name'] == 'Freelance' for e in result['events'])
    assert forecast(client, h, events=events, income_date=today.isoformat(), income_amount=100).status_code == 422
    for bad in [events * 11, [dict(events[0], amount=0)], [dict(events[0], name=' ')],
                [dict(events[0], date=(today+timedelta(days=30)).isoformat())]]:
        assert forecast(client, h, events=bad).status_code == 422
