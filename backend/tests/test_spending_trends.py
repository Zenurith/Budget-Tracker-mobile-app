from datetime import date
from test_api import client, signup, transaction
from app.domain import planning


def test_trends_category_coverage_year_boundary_and_owner(client, monkeypatch):
    monkeypatch.setattr(planning, 'today_for', lambda _: date(2026, 2, 15))
    headers, _ = signup(client)
    other, _ = signup(client, 'other@example.com')
    for h, data in [
        (headers, transaction(date='2025-12-01', amount=1000)),
        (headers, transaction(date='2026-02-01', amount=2500)),
        (headers, transaction(date='2026-02-01', amount=5000, type='income', category_id='salary')),
        (other, transaction(date='2026-02-01', amount=9999)),
    ]:
        assert client.post('/transactions', headers=h, json=data).status_code == 201
    response = client.get('/reports/summary?month=2026-03', headers=headers)
    assert response.status_code == 200
    months = response.json()['trend']
    assert [m['month'] for m in months] == ['2025-10', '2025-11', '2025-12', '2026-01', '2026-02', '2026-03']
    assert months[3]['record_count'] == 0
    assert months[3]['category_totals'] == {}
    assert months[4]['status'] == 'in_progress'
    assert months[4]['expense'] == 2500
    assert sum(months[4]['category_totals'].values()) == 2500
    assert months[4]['record_count'] == 2
    assert months[4]['recorded_days'] == 1
    assert months[2]['status'] == 'ended'
    assert months[5]['status'] == 'future'
