"""Single-use password recovery. Delivery is an injected infrastructure port."""
from datetime import datetime, timedelta, timezone
from hashlib import sha256
import secrets
from .errors import DomainError, ErrorKind
from .ports import ResetMailer


def now():
    return datetime.now(timezone.utc)


def request(email, db, mailer: ResetMailer):
    user = db.get('users', email=email.lower())
    if not user:
        return
    with db.atomic(user['id']) as tx:
        user = tx.get('users', id=user['id'])
        if not user:
            return
        previous = tx.find('password_resets', user_id=user['id'])
        if any(p['created_at'] > (now() - timedelta(minutes=1)).isoformat() for p in previous):
            return
        token = secrets.token_urlsafe(32)
        digest = sha256(token.encode()).hexdigest()
        tx.delete('password_resets', user_id=user['id'])
        tx.put('password_resets', {'id': digest, 'user_id': user['id'],
                                  'created_at': now().isoformat(),
                                  'expires_at': (now() + timedelta(minutes=30)).isoformat()})
        # Do not commit an unusable reset if SMTP rejects delivery. No token logs.
        mailer.send_reset(user['email'], token)


def reset(token, password, db, passwords):
    if not 8 <= len(password) <= 128:
        raise DomainError(ErrorKind.INVALID_INPUT, 'Use a password between 8 and 128 characters.')
    digest = sha256(token.encode()).hexdigest()
    record = db.get('password_resets', id=digest)
    if not record:
        raise DomainError(ErrorKind.INVALID_INPUT, 'This reset code is invalid or expired. Request a new email.')
    with db.atomic(record['user_id']) as tx:
        current = tx.get('password_resets', id=digest, user_id=record['user_id'])
        user = tx.get('users', id=record['user_id'])
        if not current or not user or current['expires_at'] < now().isoformat():
            raise DomainError(ErrorKind.INVALID_INPUT, 'This reset code is invalid or expired. Request a new email.')
        tx.put('users', dict(user, password_hash=passwords.hash(password)))
        for collection in ('password_resets', 'sessions', 'access_sessions'):
            tx.delete(collection, user_id=user['id'])
    return {'ok': True}
