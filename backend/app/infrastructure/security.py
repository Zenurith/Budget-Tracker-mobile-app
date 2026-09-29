import secrets
from datetime import datetime, timedelta, timezone
from uuid import uuid4
import jwt
from pwdlib import PasswordHash
from ..domain.errors import DomainError, ErrorKind

class Argon2PasswordHasher:
    def __init__(self):
        self._hasher = PasswordHash.recommended()
        self._dummy_hash = self._hasher.hash(secrets.token_urlsafe(24))

    @property
    def dummy_hash(self) -> str:
        return self._dummy_hash

    def hash(self, value: str) -> str:
        return self._hasher.hash(value)

    def verify(self, value: str, hashed: str) -> bool:
        return self._hasher.verify(value, hashed)

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
            raise DomainError(ErrorKind.UNAUTHORIZED, 'Your session has expired. Please sign in again.')
