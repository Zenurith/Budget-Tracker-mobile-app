"""Owner-scoped transaction undo with version and linked-record safeguards."""
from copy import deepcopy
from datetime import datetime, timedelta, timezone
from uuid import uuid4
from .errors import DomainError, ErrorKind


def now():
    return datetime.now(timezone.utc)


def remember(before, after, user, db):
    return db.put('transaction_history', {
        'id': str(uuid4()), 'user_id': user['id'], 'transaction_id': (after or before)['id'],
        'action': 'create' if before is None else 'delete' if after is None else 'update',
        'before': deepcopy(before), 'after': deepcopy(after), 'undone': False,
        'created_at': now().isoformat(), 'expires_at': (now() + timedelta(days=30)).isoformat(),
    })


def history(user, db, page=1):
    rows = [r for r in db.find('transaction_history', user_id=user['id']) if r['expires_at'] >= now().isoformat()]
    rows.sort(key=lambda r: (r['created_at'], r['id']), reverse=True)
    return {'items': rows[(page - 1) * 50:page * 50], 'total': len(rows), 'page': page}


def undo(id, user, db):
    from . import finance
    from .funding_state import cash_changed
    with db.atomic(user['id']) as tx:
        event = finance.owned('transaction_history', id, user, tx)
        if event['undone']:
            return {'ok': True, 'already_undone': True}
        if event['expires_at'] < now().isoformat():
            raise DomainError(ErrorKind.CONFLICT, 'The 30-day undo period has expired.')
        current = tx.get('transactions', id=event['transaction_id'], user_id=user['id'])
        if current != event['after']:
            raise DomainError(ErrorKind.CONFLICT, 'This transaction changed after that action. Undo newer changes first.')
        if any((doc or {}).get(link) for doc in (current, event['before'])
               for link in ('wishlist_purchase_id', 'commitment_occurrence_id')):
            raise DomainError(ErrorKind.CONFLICT, 'Correct the purchase or payment link before undoing this transaction.')
        if event['before']:
            previous = event['before']
            finance.check_category(previous['category_id'], previous['type'], user, tx)
            tx.put('transactions', previous)
        else:
            tx.delete('transactions', id=event['transaction_id'], user_id=user['id'])
        tx.put('transaction_history', dict(event, undone=True, undone_at=now().isoformat()))
        cash_changed(user, tx)
        return {'ok': True, 'already_undone': False}
