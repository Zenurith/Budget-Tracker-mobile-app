from datetime import date
import pytest
from fastapi.testclient import TestClient
from app.main import create_app
from app.repositories.documents import LocalRepository


@pytest.fixture
def client():
    repo = LocalRepository(':memory:')
    with TestClient(create_app(repo, secret='test-secret-that-is-at-least-32-characters')) as c:
        yield c
    repo.close()


def signup(client, email='alex@example.com'):
    response = client.post('/auth/register', json={'name':'Alex','email':email,'password':'correct-horse-123','currency':'EUR'})
    assert response.status_code == 201, response.text
    tokens = response.json()
    return {'Authorization': 'Bearer '+tokens['access_token']}, tokens


def transaction(**overrides):
    return dict({'amount':1550,'type':'expense','category_id':'food','date':'2026-09-27','note':'Lunch'}, **overrides)


def test_auth_refresh_rotation_and_logout(client):
    headers, tokens = signup(client)
    assert 'password_hash' not in tokens['user']
    assert client.get('/auth/me',headers=headers).json()['name']=='Alex'
    assert client.get('/auth/me').status_code==401
    assert client.post('/auth/login',json={'email':'alex@example.com','password':'wrong'}).status_code==401
    login=client.post('/auth/login',json={'email':'ALEX@example.com','password':'correct-horse-123'})
    assert login.status_code==200
    refresh=client.post('/auth/refresh',json={'refresh_token':tokens['refresh_token']})
    assert refresh.status_code==200
    assert client.post('/auth/refresh',json={'refresh_token':tokens['refresh_token']}).status_code==401
    assert client.post('/auth/refresh',json={'refresh_token':tokens['access_token']}).status_code==401
    new=refresh.json()['refresh_token']
    assert client.post('/auth/logout',json={'refresh_token':new}).status_code==200
    assert client.post('/auth/refresh',json={'refresh_token':new}).status_code==401
    assert client.get('/auth/me',headers={'Authorization':'Bearer invalid'}).status_code==401
    assert client.post('/auth/register',json={'name':'Other','email':'alex@example.com','password':'password1','currency':'EUR'}).status_code==409


def test_transaction_crud_filters_and_isolation(client):
    h,_=signup(client)
    other,_=signup(client,'other@example.com')
    created=client.post('/transactions',headers=h,json=transaction()).json()
    id=created['id']
    assert created['amount']==1550
    assert client.get('/transactions',headers=other).json()['items']==[]
    assert client.put(f'/transactions/{id}',headers=other,json=transaction()).status_code==404
    assert client.delete(f'/transactions/{id}',headers=other).status_code==404
    edited=client.put(f'/transactions/{id}',headers=h,json=transaction(amount=2200))
    assert edited.json()['amount']==2200
    for query,total in [('q=lunch',1),('q=dinner',0),('start=2026-09-28',0),('end=2026-09-26',0),('min_amount=2300',0),('max_amount=2000',0),('category_id=bills',0),('type=income',0),('page=2&page_size=1',1)]:
        assert client.get('/transactions?'+query,headers=h).json()['total']==total
    assert client.get('/transactions?page=0',headers=h).status_code==422
    for changes in [{'amount':1.5},{'amount':0},{'amount':-100},{'category_id':'salary'},{'date':'bad'}]:
        assert client.post('/transactions',headers=h,json=transaction(**changes)).status_code==422
    assert client.delete(f'/transactions/{id}',headers=h).status_code==204
    assert client.get('/transactions',headers=h).json()['total']==0


def test_budgets_reports_and_month_boundaries(client):
    h,_=signup(client)
    for changes in [{},{'amount':450,'category_id':'transport'},{'amount':10000,'type':'income','category_id':'salary'},{'date':'2026-08-31','amount':200}]:
        assert client.post('/transactions',headers=h,json=transaction(**changes)).status_code==201
    body={'period':'2026-09','limit_amount':1000,'category_id':None,'alert_threshold':80}
    b=client.post('/budgets',headers=h,json=body).json()
    assert client.post('/budgets',headers=h,json=dict(body,limit_amount=1500)).json()['id']==b['id']
    client.post('/budgets',headers=h,json=dict(body,category_id='food'))
    budgets=client.get('/budgets?period=2026-09',headers=h).json()['items']
    assert len(budgets)==2
    overall = next(b for b in budgets if b['category_id'] is None)
    food = next(b for b in budgets if b['category_id'] == 'food')
    assert overall['spent']==2000
    assert overall['remaining']==-500
    assert food['spent']==1550
    assert client.post('/budgets',headers=h,json=dict(body,category_id='salary')).status_code==422
    summary=client.get('/reports/summary?month=2026-09',headers=h).json()
    assert summary['income']==10000
    assert summary['expenses']==2000
    assert summary['balance']==7800
    assert summary['net']==8000
    assert summary['daily_expenses']=={'2026-09-27':2000}
    assert summary['trend'][-2]['expense']==200
    assert client.get('/reports/summary?month=2026-13',headers=h).status_code==422
    assert client.delete('/budgets/'+b['id'],headers=h).status_code==204


def test_custom_categories_account_deletion(client):
    h,tokens=signup(client)
    cat=client.post('/categories',headers=h,json={'name':'Books'}).json()
    id=cat['id']
    assert len(client.get('/categories',headers=h).json()['items'])==10
    assert client.put('/categories/'+id,headers=h,json={'name':'Reading'}).json()['name']=='Reading'
    tx=client.post('/transactions',headers=h,json=transaction(category_id=id)).json()
    assert client.delete('/categories/'+id,headers=h).status_code==409
    assert client.put('/categories/'+id,headers=h,json={'name':'Reading','type':'income'}).status_code==409
    assert client.delete('/categories/food',headers=h).status_code==404
    client.delete('/transactions/'+tx['id'],headers=h)
    assert client.delete('/categories/'+id,headers=h).status_code==204
    assert client.post('/categories',headers=h,json={'name':'   '}).status_code==422
    client.post('/transactions',headers=h,json=transaction())
    assert client.delete('/auth/me',headers=h).status_code==204
    assert client.get('/auth/me',headers=h).status_code==401
    assert client.post('/auth/refresh',json={'refresh_token':tokens['refresh_token']}).status_code==401
    assert client.app.state.repo.find('transactions')==[]


@pytest.mark.parametrize('text,amount,category,kind,day',[
    ('Spent 15 on lunch yesterday',1500,'food','expense','2026-09-27'),
    ('Received salary 4,800 today',480000,'salary','income','2026-09-28'),
    ('Grab 18.50 on 2026-09-24',1850,'transport','expense','2026-09-24'),
    ('Coffee 5.25 last Friday',525,'food','expense','2026-09-25'),
    ('rent 1200 tomorrow',120000,'bills','expense','2026-09-29'),
    ('Something 10',1000,'other-expense','expense','2026-09-28'),
    ('Received refund 20 today',2000,'other-income','income','2026-09-28'),
])
def test_parser(client,text,amount,category,kind,day):
    h,_=signup(client)
    result=client.post('/nlp/parse',headers=h,json={'text':text,'reference_date':'2026-09-28'})
    assert result.status_code==200, result.text
    tx=result.json()['transaction']
    assert (tx['amount'],tx['category_id'],tx['type'],tx['date'])==(amount,category,kind,day)
    assert client.get('/transactions',headers=h).json()['total']==0
    assert client.post('/transactions',headers=h,json=tx).status_code==201


@pytest.mark.parametrize('text',['Lunch','Lunch 10 and taxi 20','Spent 0 on food','Spent -15 on lunch','Spent 10.555 on food','Lunch 15 on 2026-02-30'])
def test_parser_rejects_ambiguous_input(client,text):
    h,_=signup(client)
    assert client.post('/nlp/parse',headers=h,json={'text':text}).status_code==422


def test_demo_and_rate_limit(client):
    assert client.get('/health').json()['status']=='ok'
    demo=client.post('/auth/demo', json={'currency':'USD'}).json()
    h={'Authorization':'Bearer '+demo['access_token']}
    assert client.get('/transactions',headers=h).json()['total']==8
    assert len(client.get('/budgets?period='+date.today().strftime('%Y-%m'),headers=h).json()['items'])==3
    for _ in range(20):
        response=client.post('/auth/login',json={'email':'no@example.com','password':'no'})
    assert response.status_code==429


def test_local_persistence(tmp_path):
    path=str(tmp_path/'db.sqlite')
    db=LocalRepository(path)
    db.put('transactions',{'id':'one','amount':100,'user_id':'a'})
    db.close()
    db=LocalRepository(path)
    assert db.get('transactions',id='one')['amount']==100
    assert db.consume('transactions','one')['id']=='one'
    assert db.consume('transactions','one') is None
    db.close()


@pytest.mark.parametrize('endpoint', ['/auth/register', '/auth/demo'])
@pytest.mark.parametrize('currency', [None, '', 'JPY', 'usd', 123])
def test_onboarding_rejects_invalid_currency_without_writes(client, endpoint, currency):
    body = {'name': 'Alex', 'email': 'alex@example.com', 'password': 'correct-horse-123'} if endpoint.endswith('register') else {}
    if currency is not None:
        body['currency'] = currency
    response = client.post(endpoint, json=body)
    assert response.status_code == 422
    assert 'currency' in response.json()['error']['message']
    for collection in ('users', 'sessions', 'transactions', 'budgets'):
        assert client.app.state.repo.find(collection) == []


@pytest.mark.parametrize('currency', ['EUR', 'GBP', 'MYR', 'SGD', 'USD'])
@pytest.mark.parametrize('endpoint', ['/auth/register', '/auth/demo'])
def test_onboarding_preserves_selected_currency(client, endpoint, currency):
    body = {'currency': currency}
    if endpoint.endswith('register'):
        body.update(name='Alex', email='alex@example.com', password='correct-horse-123')
    response = client.post(endpoint, json=body)
    assert response.status_code in (200, 201)
    session = response.json()
    assert session['user']['currency'] == currency
    headers = {'Authorization': 'Bearer ' + session['access_token']}
    assert client.get('/auth/me', headers=headers).json()['currency'] == currency
    refreshed = client.post('/auth/refresh', json={'refresh_token': session['refresh_token']})
    assert refreshed.json()['user']['currency'] == currency
    if endpoint.endswith('demo'):
        assert client.get('/transactions', headers=headers).json()['total'] == 8


def test_demo_requires_body_and_remains_disabled_in_mongo(monkeypatch):
    repo = LocalRepository(':memory:')
    try:
        with TestClient(create_app(repo, secret='test-secret-that-is-at-least-32-characters')) as client:
            assert client.post('/auth/demo').status_code == 422
        monkeypatch.setenv('DATABASE_MODE', 'mongo')
        with TestClient(create_app(repo, secret='test-secret-that-is-at-least-32-characters')) as client:
            assert client.post('/auth/demo', json={'currency': 'USD'}).status_code == 404
            assert repo.find('users') == []
    finally:
        repo.close()
