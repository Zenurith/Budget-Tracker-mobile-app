from datetime import date
from test_api import client, signup, transaction


def test_category_appearance_and_cross_month_combined_filters(client):
    headers, _ = signup(client)
    other, _ = signup(client, 'other@example.com')
    category = client.post('/categories', headers=headers, json={
        'name': 'Books', 'icon': 'work', 'color': '#AC8FC0'}).json()
    edited = client.put('/categories/' + category['id'], headers=headers,
                        json={'name': 'Reading', 'icon': 'movie', 'color': '#6D9DC5'})
    assert edited.json()['icon'] == 'movie'
    assert edited.json()['color'] == '#6D9DC5'
    for when, amount in [('2026-08-31', 100), ('2026-09-01', 200), ('2026-09-02', 300)]:
        assert client.post('/transactions', headers=headers, json=transaction(
            category_id=category['id'], date=when, amount=amount, note='Novel')).status_code == 201
    query = '/transactions?start=2026-08-31&end=2026-09-01&min_amount=100&max_amount=200&q=reading&type=expense&page_size=1'
    first = client.get(query, headers=headers).json()
    second = client.get(query + '&page=2', headers=headers).json()
    assert first['total'] == second['total'] == 2
    assert first['items'][0]['amount'] == 200
    assert second['items'][0]['amount'] == 100
    assert client.get(query, headers=other).json()['total'] == 0
    for query in ('start=2026-09-02&end=2026-09-01', 'min_amount=300&max_amount=100', 'min_amount=-1', 'max_amount=-1'):
        assert client.get('/transactions?' + query, headers=headers).status_code == 422
    assert client.put('/categories/' + category['id'], headers=other,
                      json={'name': 'Stolen', 'color': '#ffffff'}).status_code == 404


def test_monthly_review_separates_overlapping_budgets_and_incomplete_periods(client):
    headers, _ = signup(client)
    other, _ = signup(client, 'other@example.com')
    for amount, when in [(600, '2026-08-01'), (700, '2026-09-01'), (500, '2026-09-02')]:
        client.post('/transactions', headers=headers, json=transaction(amount=amount, date=when))
    for category, limit in [(None, 2000), ('food', 1000)]:
        client.post('/budgets', headers=headers, json={
            'period': '2026-09', 'category_id': category, 'limit_amount': limit})
    review = client.get('/reports/summary?month=2026-09', headers=headers).json()['review']
    assert review['record_count'] == review['recorded_days'] == 2
    assert review['expense_change'] == 600
    assert review['previous_record_count'] == 1
    budgets = {b['category_id']: b for b in review['budget_variances']}
    assert budgets[None]['remaining'] == 800
    assert budgets['food']['remaining'] == -200
    assert client.get('/reports/summary?month=' + date.today().strftime('%Y-%m'), headers=headers).json()['review']['period_status'] == 'in_progress'
    assert client.get('/reports/summary?month=2099-01', headers=headers).json()['review']['period_status'] == 'future'
    assert client.get('/reports/summary?month=2020-01', headers=headers).json()['review']['period_status'] == 'ended'
    empty = client.get('/reports/summary?month=2026-09', headers=other).json()['review']
    assert empty['record_count'] == 0
    assert empty['budget_variances'] == []
    assert 'missing activity' in empty['coverage']
