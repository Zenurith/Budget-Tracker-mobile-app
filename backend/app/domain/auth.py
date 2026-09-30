import hashlib
from datetime import datetime, timezone
from uuid import uuid4
from .commands import Login, Refresh, Register, UpdateProfile
from .ports import DocumentRepository, DuplicateRecordError, PasswordHasher, TokenProvider
from .errors import DomainError, ErrorKind
from .finance import categories

class AuthService:
    def __init__(self, tokens: TokenProvider, passwords: PasswordHasher):
        self.tokens = tokens
        self.passwords = passwords

    def user_for_token(self, value, db: DocumentRepository):
        uid = self.tokens.decode(value, 'access')['sub']
        user = db.get('users', id=uid)
        if not user:
            raise DomainError(ErrorKind.UNAUTHORIZED, 'Account not found.')
        return user

    def public(self, user):
        return {k: user[k] for k in ('id', 'name', 'email', 'currency', 'created_at') if k in user}

    def session(self, user, db: DocumentRepository):
        refresh_token = self.tokens.token(user['id'], 'refresh', 30 * 86400)
        digest = hashlib.sha256(refresh_token.encode()).hexdigest()
        db.put('sessions', {'id': digest, 'user_id': user['id']})
        return {'access_token': self.tokens.token(user['id'], 'access', 900), 'refresh_token': refresh_token, 'token_type': 'bearer', 'user': self.public(user)}

    def register(self, data: Register, db: DocumentRepository = None):
        email = str(data.email).lower()
        if db.get('users', email=email):
            raise DomainError(ErrorKind.CONFLICT, 'An account with this email already exists.')
        user = {'id': str(uuid4()), 'name': data.name.strip() or 'Friend', 'email': email, 'currency': data.currency, 'password_hash': self.passwords.hash(data.password), 'created_at': datetime.now(timezone.utc).isoformat()}
        try:
            db.put('users', user)
        except DuplicateRecordError:
            raise DomainError(ErrorKind.CONFLICT, 'An account with this email already exists.')
        return self.session(user, db)

    def login(self, data: Login, db: DocumentRepository = None):
        user = db.get('users', email=str(data.email).lower())
        valid = self.passwords.verify(data.password, user['password_hash'] if user else self.passwords.dummy_hash)
        if not user or not valid:
            raise DomainError(ErrorKind.UNAUTHORIZED, 'Email or password is incorrect.')
        return self.session(user, db)

    def refresh(self, data: Refresh, db: DocumentRepository = None):
        payload = self.tokens.decode(data.refresh_token, 'refresh')
        stored = db.consume('sessions', hashlib.sha256(data.refresh_token.encode()).hexdigest())
        user = db.get('users', id=payload['sub'])
        if not stored or not user or stored['user_id'] != user['id']:
            raise DomainError(ErrorKind.UNAUTHORIZED, 'Please sign in again.')
        return self.session(user, db)

    def logout(self, data: Refresh, db: DocumentRepository = None):
        db.delete('sessions', id=hashlib.sha256(data.refresh_token.encode()).hexdigest())
        return {'ok': True}

    def me(self, user=None):
        return self.public(user)

    def update_profile(self, data: UpdateProfile, user, db: DocumentRepository):
        name = data.name.strip()
        if not name or len(name) > 80:
            raise DomainError(ErrorKind.INVALID_INPUT, 'Enter a name between 1 and 80 characters.')
        updated = dict(user, name=name)
        db.put('users', updated)
        return self.public(updated)

    def export_data(self, user, db: DocumentRepository):
        return {
            'schema_version': 1,
            'exported_at': datetime.now(timezone.utc).isoformat(),
            'money_unit': 'minor_units',
            'account': self.public(user),
            'categories': categories(user, db),
            'planning': [{k: v for k, v in p.items() if k != 'operations'}
                         for p in db.find('planning', user_id=user['id'])],
            **{collection: db.find(collection, user_id=user['id'])
               for collection in ('transactions', 'budgets')},
        }

    def delete_account(self, user=None, db: DocumentRepository = None):
        with db.atomic(user['id']) as tx:
            for collection in ('transactions', 'budgets', 'categories', 'sessions', 'planning'):
                tx.delete(collection, user_id=user['id'])
            tx.delete('users', id=user['id'])
