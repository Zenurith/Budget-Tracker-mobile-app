from datetime import datetime

import pytest

from test_api import client, signup, transaction
from app.domain.commands import UpdateProfile
from app.domain.errors import DomainError, ErrorKind
from app.domain.auth import AuthService


def test_profile_updates_only_own_name_and_survives_login(client):
    headers, session = signup(client)
    other, _ = signup(client, 'other@example.com')
    uid = session['user']['id']
    before = client.app.state.repo.get('users', id=uid)
    response = client.put('/auth/me', headers=headers, json={'name': '  Alex Tan  '})
    assert response.status_code == 200
    assert response.json()['name'] == 'Alex Tan'
    assert 'password_hash' not in response.json()
    assert client.app.state.repo.get('users', id=uid) == dict(before, name='Alex Tan')
    assert client.get('/auth/me', headers=other).json()['name'] == 'Alex'
    login = client.post('/auth/login', json={'email': 'alex@example.com', 'password': 'correct-horse-123'})
    assert login.json()['user']['name'] == 'Alex Tan'
    assert login.json()['user']['currency'] == 'EUR'


@pytest.mark.parametrize('body', [
    {}, {'name': ''}, {'name': '  '}, {'name': 'a' * 81},
    {'name': 'Valid', 'currency': 'USD'}, {'name': 'Valid', 'id': 'other'},
    {'name': 'Valid', 'email': 'new@example.com'},
    {'name': 'Valid', 'password_hash': 'injected'},
])
def test_profile_rejects_invalid_and_protected_fields(client, body):
    headers, session = signup(client)
    before = client.app.state.repo.get('users', id=session['user']['id'])
    assert client.put('/auth/me', headers=headers, json=body).status_code == 422
    assert client.app.state.repo.get('users', id=before['id']) == before


def test_profile_domain_validates_without_transport(client):
    _, session = signup(client)
    repo = client.app.state.repo
    user = repo.get('users', id=session['user']['id'])
    service = AuthService(None, None)
    for name in (' ', 'a' * 81):
        with pytest.raises(DomainError) as error:
            service.update_profile(UpdateProfile(name=name), user, repo)
        assert error.value.kind is ErrorKind.INVALID_INPUT


def test_export_is_complete_owner_scoped_and_excludes_credentials(client):
    headers, session = signup(client)
    other, _ = signup(client, 'other@example.com')
    for h in (headers, other):
        client.post('/categories', headers=h, json={'name': 'Books'})
        client.post('/budgets', headers=h, json={'period': '2026-09', 'limit_amount': 10000})
        client.post('/transactions', headers=h, json=transaction())
    # More than one API page, including history outside the selected month.
    repo = client.app.state.repo
    for i in range(105):
        repo.put('transactions', dict(transaction(date='2025-01-01'), id=f'history-{i}', user_id=session['user']['id']))
    response = client.get('/auth/me/export', headers=headers)
    assert response.status_code == 200
    assert response.headers['cache-control'] == 'no-store'
    assert 'attachment' in response.headers['content-disposition']
    data = response.json()
    assert data['schema_version'] == 1
    assert data['money_unit'] == 'minor_units'
    assert datetime.fromisoformat(data['exported_at']).tzinfo is not None
    assert data['account'] == session['user']
    assert len(data['transactions']) == 106
    assert len(data['budgets']) == 1
    assert len(data['categories']) == 10  # Nine default definitions plus own custom category.
    for collection in ('transactions', 'budgets', 'categories'):
        assert all(d.get('user_id') in (None, session['user']['id']) for d in data[collection])
    for secret in ('password_hash', 'sessions', session['access_token'], session['refresh_token']):
        assert secret not in response.text
    assert client.get('/auth/me/export').status_code == 401
    assert client.put('/auth/me', json={'name': 'Alex'}).status_code == 401
    client.delete('/auth/me', headers=headers)
    assert client.get('/auth/me/export', headers=headers).status_code == 401
