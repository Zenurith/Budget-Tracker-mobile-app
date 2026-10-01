"""Owner funding aggregate and cash-change marker; callers hold the owner lock."""
from datetime import datetime, timezone
from .errors import DomainError, ErrorKind


def load(user, db):
    if not db.get('users', id=user['id']):
        raise DomainError(ErrorKind.UNAUTHORIZED, 'Account not found.')
    return db.get('funding', id=user['id'], user_id=user['id']) or {
        'id': user['id'], 'user_id': user['id'], 'revision': 0, 'cash_revision': 0,
        'snapshot': None, 'plan': None, 'goals': {}, 'reservations': {}, 'operations': {},
    }


def persist(state, db):
    state['revision'] += 1
    state['updated_at'] = datetime.now(timezone.utc).isoformat()
    db.put('funding', state)


def cash_changed(user, db):
    state = load(user, db)
    state['cash_revision'] += 1
    persist(state, db)
