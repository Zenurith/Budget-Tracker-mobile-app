"""Dependency gates and domain behavior with no framework/storage adapters."""
import ast
import hashlib
import sys
from copy import deepcopy
from datetime import date
from pathlib import Path

import pytest

from app.domain.auth import AuthService
from app.domain.commands import Login, Refresh, Register, Transaction
from app.domain.errors import DomainError, ErrorKind
from app.domain.finance import add_transaction, edit_transaction
from app.domain.ports import DuplicateRecordError


def test_domain_imports_only_standard_library_and_domain_modules():
    root = Path(__file__).resolve().parents[1] / 'app' / 'domain'
    for path in root.glob('*.py'):
        for node in ast.walk(ast.parse(path.read_text())):
            if isinstance(node, ast.Import):
                modules = [alias.name for alias in node.names]
            elif isinstance(node, ast.ImportFrom):
                if node.level:
                    assert node.level == 1, f'{path.name}: domain cannot import outer layers'
                    continue
                modules = [node.module or '']
            else:
                continue
            for module in modules:
                assert module.split('.')[0] in sys.stdlib_module_names or module.startswith('app.domain'), (path.name, module)
                assert module.split('.')[0] != 'sqlite3', (path.name, module)


class MemoryRepository:
    def __init__(self):
        self.docs = {}

    def find(self, collection, **query):
        return [deepcopy(doc) for (name, _), doc in self.docs.items()
                if name == collection and all(doc.get(k) == v for k, v in query.items())]

    def get(self, collection, **query):
        return next(iter(self.find(collection, **query)), None)

    def put(self, collection, doc):
        self.docs[collection, doc['id']] = deepcopy(doc)
        return doc

    def consume(self, collection, id):
        return self.docs.pop((collection, id), None)

    def delete(self, collection, **query):
        docs = self.find(collection, **query)
        for doc in docs:
            del self.docs[collection, doc['id']]
        return len(docs)


class FakePasswords:
    dummy_hash = 'hashed:unknown-random-password'

    def __init__(self):
        self.checked = []

    def hash(self, value):
        return 'hashed:' + value

    def verify(self, value, hashed):
        self.checked.append(hashed)
        return hashed == self.hash(value)


class FakeTokens:
    def __init__(self):
        self.issued = {}

    def token(self, uid, kind, seconds):
        value = f'{kind}-{len(self.issued)}'
        self.issued[value] = {'sub': uid, 'type': kind}
        return value

    def decode(self, value, kind):
        data = self.issued[value]
        assert data['type'] == kind
        return data


def test_auth_uses_injected_adapters_and_refresh_is_single_use():
    db, passwords = MemoryRepository(), FakePasswords()
    auth = AuthService(FakeTokens(), passwords)
    session = auth.register(Register(name='Alex', email='ALEX@example.com', password='password1', currency='EUR'), db)
    assert session['user']['email'] == 'alex@example.com'
    assert 'password_hash' not in session['user']
    assert db.get('users', id=session['user']['id'])['password_hash'] == 'hashed:password1'
    assert auth.login(Login(email='alex@example.com', password='password1'), db)['user'] == session['user']
    request = Refresh(refresh_token=session['refresh_token'])
    rotated = auth.refresh(request, db)
    assert rotated['refresh_token'] != request.refresh_token
    assert db.get('sessions', id=hashlib.sha256(request.refresh_token.encode()).hexdigest()) is None
    with pytest.raises(DomainError) as error:
        auth.refresh(request, db)
    assert error.value.kind == ErrorKind.UNAUTHORIZED


def test_missing_user_still_verifies_dummy_hash():
    passwords = FakePasswords()
    auth = AuthService(FakeTokens(), passwords)
    with pytest.raises(DomainError) as error:
        auth.login(Login(email='missing@example.com', password='wrong'), MemoryRepository())
    assert error.value.kind == ErrorKind.UNAUTHORIZED
    assert passwords.checked == [passwords.dummy_hash]


def test_registration_race_uses_repository_error_contract():
    class RacingRepository(MemoryRepository):
        def put(self, collection, doc):
            raise DuplicateRecordError()

    db = RacingRepository()
    auth = AuthService(FakeTokens(), FakePasswords())
    with pytest.raises(DomainError) as error:
        auth.register(Register(name='Alex', email='alex@example.com', password='password1', currency='USD'), db)
    assert error.value.kind == ErrorKind.CONFLICT
    assert db.docs == {}


def test_transaction_commands_preserve_dates_and_owner_checks():
    db = MemoryRepository()
    user = {'id': 'owner'}
    command = Transaction(amount=1550, type='expense', category_id='food', date=date(2026, 9, 29))
    saved = add_transaction(command, user, db)
    assert saved['date'] == '2026-09-29'
    assert saved['amount'] == 1550
    assert saved['source'] == 'manual'
    assert edit_transaction(saved['id'], command, user, db) == saved
    with pytest.raises(DomainError) as error:
        edit_transaction(saved['id'], command, {'id': 'other'}, db)
    assert error.value.kind == ErrorKind.NOT_FOUND
