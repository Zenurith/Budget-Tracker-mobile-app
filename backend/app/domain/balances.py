"""Declared opening balances and immutable reconciliation observations."""
from datetime import date, datetime, timezone
from hashlib import sha256
import json
from uuid import uuid4
from zoneinfo import ZoneInfo
from .errors import DomainError, ErrorKind
from .funding_state import cash_changed


def opening(user, db):
    return db.get('opening_balances', id=user['id'], user_id=user['id'])


def expected(on, user, db):
    baseline = opening(user, db)
    if not baseline or baseline['as_of'] > on.isoformat():
        return None
    movements = sum(d['amount'] * (1 if d['type'] == 'income' else -1)
                    for d in db.find('transactions', user_id=user['id'])
                    if baseline['as_of'] <= d['date'] <= on.isoformat())
    return {'opening_total': baseline['total'], 'movement': movements,
            'balance': baseline['total'] + movements, 'opening_revision': baseline['revision'],
            'as_of': on.isoformat()}


def overview(user, db, page=1):
    rows = db.find('balance_history', user_id=user['id'])
    rows.sort(key=lambda r: (r['created_at'], r['id']), reverse=True)
    return {'opening': opening(user, db), 'recorded': expected(date.today(), user, db),
            'items': rows[(page - 1) * 50:page * 50], 'total': len(rows), 'page': page}


def save(data, user, db):
    accounts = data['accounts']
    if data['currency'] != user['currency'] or not data['confirmed']:
        raise DomainError(ErrorKind.INVALID_INPUT, 'Confirm the starting balances in your account currency.')
    if data['as_of'] > date.today():
        raise DomainError(ErrorKind.INVALID_INPUT, 'Choose today or an earlier opening date.')
    names = [a['name'].strip().casefold() for a in accounts]
    if any(not n for n in names) or len(names) != len(set(names)):
        raise DomainError(ErrorKind.INVALID_INPUT, 'Use distinct account names.')
    fingerprint = sha256(json.dumps(data, sort_keys=True, default=str).encode()).hexdigest()
    key = sha256(f"{user['id']}:{data['operation_id']}".encode()).hexdigest()
    with db.atomic(user['id']) as tx:
        prior = tx.get('balance_history', id=key, user_id=user['id'])
        if prior:
            if prior['fingerprint'] != fingerprint:
                raise DomainError(ErrorKind.CONFLICT, 'This request ID was used for different balances.')
            return prior['after']
        old = opening(user, tx)
        revision = (old or {}).get('revision', 0)
        if revision != data['expected_revision']:
            raise DomainError(ErrorKind.CONFLICT, 'Opening balances changed. Reload and review them.')
        record = {'id': user['id'], 'user_id': user['id'], 'revision': revision + 1,
                  'currency': user['currency'], 'as_of': data['as_of'].isoformat(),
                  'accounts': accounts, 'total': sum(a['amount'] for a in accounts)}
        tx.put('opening_balances', record)
        tx.put('balance_history', {'id': key, 'user_id': user['id'], 'kind': 'opening',
                                  'before': old, 'after': record, 'fingerprint': fingerprint,
                                  'created_at': datetime.now(timezone.utc).isoformat()})
        cash_changed(user, tx)
        return record


def record_reconciliation(snapshot, previous, plan, user, db):
    timezone_name = (plan.get('profile') or {}).get('timezone', 'UTC')
    on = datetime.fromisoformat(snapshot['as_of']).astimezone(ZoneInfo(timezone_name)).date()
    recorded = expected(on, user, db)
    baseline = opening(user, db)
    same_accounts = baseline is not None and {a['name'].strip().casefold() for a in baseline['accounts']} == {a['name'].strip().casefold() for a in snapshot['accounts']}
    if not same_accounts:
        recorded = None
    db.put('balance_history', {'id': str(uuid4()), 'user_id': user['id'], 'kind': 'reconciliation',
                              'created_at': datetime.now(timezone.utc).isoformat(),
                              'before': previous, 'after': snapshot, 'recorded': recorded,
                              'timezone': timezone_name,
                              'comparison_note': 'Includes all recorded transactions dated through this day; check same-day timing and missing activity.' if recorded else 'Set opening balances for the same named accounts to compare recorded activity.',
                              'difference': snapshot['liquid_total'] - recorded['balance'] if recorded else None})
