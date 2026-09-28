import hashlib
import sqlite3
from datetime import datetime, timezone
from uuid import uuid4
from pymongo.errors import DuplicateKeyError
from ..models import Login, Refresh, Register
from ..infrastructure.security import password_hash, DUMMY_HASH
from .errors import DomainError

class AuthService:
    def __init__(self, tokens):
        self.tokens = tokens

    def user_for_token(self, value, db):
        uid = self.tokens.decode(value, 'access')['sub']
        user = db.get('users', id=uid)
        if not user:
            raise DomainError(401, 'Account not found.')
        return user

    def public(self, user):
        return {k: v for k, v in user.items() if k != 'password_hash'}

    def session(self, user, db):
        refresh_token = self.tokens.token(user['id'], 'refresh', 30 * 86400)
        digest = hashlib.sha256(refresh_token.encode()).hexdigest()
        db.put('sessions', {'id': digest, 'user_id': user['id']})
        return {'access_token': self.tokens.token(user['id'], 'access', 900), 'refresh_token': refresh_token, 'token_type': 'bearer', 'user': self.public(user)}

    def register(self, data: Register, db=None):
        email = str(data.email).lower()
        if db.get('users', email=email):
            raise DomainError(409, 'An account with this email already exists.')
        user = {'id': str(uuid4()), 'name': data.name.strip() or 'Friend', 'email': email, 'currency': data.currency, 'password_hash': password_hash.hash(data.password), 'created_at': datetime.now(timezone.utc).isoformat()}
        try:
            db.put('users', user)
        except (DuplicateKeyError, sqlite3.IntegrityError):
            raise DomainError(409, 'An account with this email already exists.')
        return self.session(user, db)

    def login(self, data: Login, db=None):
        user = db.get('users', email=str(data.email).lower())
        valid = password_hash.verify(data.password, user['password_hash'] if user else DUMMY_HASH)
        if not user or not valid:
            raise DomainError(401, 'Email or password is incorrect.')
        return self.session(user, db)

    def refresh(self, data: Refresh, db=None):
        payload = self.tokens.decode(data.refresh_token, 'refresh')
        stored = db.consume('sessions', hashlib.sha256(data.refresh_token.encode()).hexdigest())
        user = db.get('users', id=payload['sub'])
        if not stored or not user or stored['user_id'] != user['id']:
            raise DomainError(401, 'Please sign in again.')
        return self.session(user, db)

    def logout(self, data: Refresh, db=None):
        db.delete('sessions', id=hashlib.sha256(data.refresh_token.encode()).hexdigest())
        return {'ok': True}

    def me(self, user=None):
        return self.public(user)

    def delete_account(self, user=None, db=None):
        for collection in ('transactions', 'budgets', 'categories', 'sessions'):
            db.delete(collection, user_id=user['id'])
        db.delete('users', id=user['id'])
