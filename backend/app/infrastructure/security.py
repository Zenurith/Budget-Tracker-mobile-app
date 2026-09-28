import secrets
from datetime import datetime, timedelta, timezone
from uuid import uuid4
import jwt
from pwdlib import PasswordHash
from ..domain.errors import DomainError

password_hash = PasswordHash.recommended()
DUMMY_HASH = password_hash.hash(secrets.token_urlsafe(24))

class TokenService:
    def __init__(self, secret):
        self.secret = secret

    def token(self, uid, kind, seconds):
        now = datetime.now(timezone.utc)
        return jwt.encode({'sub': uid, 'type': kind, 'jti': str(uuid4()), 'iat': now, 'exp': now + timedelta(seconds=seconds)}, self.secret, algorithm='HS256')

    def decode(self, value, kind):
        try:
            data = jwt.decode(value, self.secret, algorithms=['HS256'], options={'require': ['exp', 'iat', 'sub', 'jti', 'type']})
            if data['type'] != kind:
                raise ValueError()
            return data
        except (jwt.InvalidTokenError, ValueError):
            raise DomainError(401, 'Your session has expired. Please sign in again.')
