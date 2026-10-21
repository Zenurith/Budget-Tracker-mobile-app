"""Owner-scoped account ledger; transfers never become income or expenses."""
from datetime import datetime, timezone
from hashlib import sha256
import json
from .errors import DomainError, ErrorKind
from .funding_state import cash_changed


def check(account_id, user, db, on=None, allow_archived=False):
    if account_id is None:
        return None
    account = db.get('money_accounts', id=account_id, user_id=user['id'])
    if not account:
        raise DomainError(ErrorKind.INVALID_INPUT, 'Choose one of your accounts.')
    if account.get('archived', False) and not allow_archived:
        raise DomainError(ErrorKind.INVALID_INPUT, 'Restore this archived account before assigning activity or recording transfers.')
    if on and on < account['opening_date']:
        raise DomainError(ErrorKind.INVALID_INPUT, 'Transaction date must be on or after the account opening date.')
    return account


def overview(user, db):
    from .planning import load, today_for
    with db.atomic(user['id']) as tx:
        today = today_for(load(user, tx)).isoformat()
        accounts = tx.find('money_accounts', user_id=user['id'])
        entries = tx.find('transactions', user_id=user['id'])
        transfers = tx.find('account_transfers', user_id=user['id'])
        for account in accounts:
            aid = account['id']
            movement = sum(e['amount'] * (1 if e['type'] == 'income' else -1)
                           for e in entries if e.get('account_id') == aid and e['date'] <= today)
            movement += sum(t['amount'] * (1 if t['to_account'] == aid else -1)
                            for t in transfers if aid in (t['from_account'], t['to_account']) and t['date'] <= today)
            account['balance'] = account['opening_amount'] + movement
            assigned = [e for e in entries if e.get('account_id') == aid and e['date'] <= today]
            incoming = [t for t in transfers if t['to_account'] == aid and t['date'] <= today]
            outgoing = [t for t in transfers if t['from_account'] == aid and t['date'] <= today]
            activity = [dict(id=e['id'], date=e['date'], kind=e['type'],
                             amount=e['amount'] * (1 if e['type'] == 'income' else -1),
                             note=e.get('note', '')) for e in assigned]
            activity += [dict(id=t['id'], date=t['date'], kind='transfer_in', amount=t['amount'], note=t.get('note', '')) for t in incoming]
            activity += [dict(id=t['id'], date=t['date'], kind='transfer_out', amount=-t['amount'], note=t.get('note', '')) for t in outgoing]
            account['review'] = {
                'income': sum(e['amount'] for e in assigned if e['type'] == 'income'),
                'expenses': sum(e['amount'] for e in assigned if e['type'] == 'expense'),
                'transfers_in': sum(t['amount'] for t in incoming),
                'transfers_out': sum(t['amount'] for t in outgoing),
                'activity_count': len(activity),
                'activity': sorted(activity, key=lambda e: (e['date'], e['id']), reverse=True)[:30],
            }
        transfers.sort(key=lambda t: (t['date'], t['created_at'], t['id']), reverse=True)
        return {'changes': sorted(tx.find('account_changes', user_id=user['id']), key=lambda r: r['created_at'], reverse=True)[:30], 'items': accounts, 'transfers': transfers, 'as_of': today,
                'checks': sorted(tx.find('account_reconciliations', user_id=user['id']), key=lambda r: r['created_at'], reverse=True)[:30],
                'unassigned_count': sum(not e.get('account_id') for e in entries),
                'unassigned_review': [dict(id=e['id'], date=e['date'], kind=e['type'],
                    amount=e['amount'] * (1 if e['type'] == 'income' else -1), note=e.get('note', ''))
                    for e in sorted(entries, key=lambda e: (e['date'], e['id']), reverse=True)
                    if not e.get('account_id') and e['date'] <= today][:30]}


def create(data, user, db):
    from .planning import load, today_for
    name = data['name'].strip()
    if not name:
        raise DomainError(ErrorKind.INVALID_INPUT, 'Enter an account name.')
    key = sha256(f"account:{user['id']}:{data['operation_id']}".encode()).hexdigest()
    record = {k: v for k, v in data.items() if k != 'operation_id'}
    record.update(name=name, opening_date=data['opening_date'].isoformat())
    digest = sha256(json.dumps(record, sort_keys=True).encode()).hexdigest()
    with db.atomic(user['id']) as tx:
        previous = tx.get('money_accounts', id=key, user_id=user['id'])
        if previous:
            if previous['fingerprint'] != digest:
                raise DomainError(ErrorKind.CONFLICT, 'This request was already used for a different account.')
            return previous
        if data['opening_date'] > today_for(load(user, tx)):
            raise DomainError(ErrorKind.INVALID_INPUT, 'Choose today or an earlier opening date.')
        accounts = tx.find('money_accounts', user_id=user['id'])
        if len(accounts) >= 30 or any(a['name'].casefold() == name.casefold() for a in accounts):
            raise DomainError(ErrorKind.INVALID_INPUT, 'Use a unique account name (up to 30 accounts).')
        record.update(id=key, user_id=user['id'], fingerprint=digest)
        tx.put('money_accounts', record)
        return record


def transfer(data, user, db):
    from .planning import load, today_for
    key = sha256(f"transfer:{user['id']}:{data['operation_id']}".encode()).hexdigest()
    record = {k: v for k, v in data.items() if k != 'operation_id'}
    record['date'] = data['date'].isoformat()
    digest = sha256(json.dumps(record, sort_keys=True).encode()).hexdigest()
    with db.atomic(user['id']) as tx:
        prior = tx.get('account_transfers', id=key, user_id=user['id'])
        if prior:
            if prior['fingerprint'] != digest:
                raise DomainError(ErrorKind.CONFLICT, 'This request was already used for a different transfer.')
            return prior
        if data['from_account'] == data['to_account']:
            raise DomainError(ErrorKind.INVALID_INPUT, 'Choose two different accounts.')
        if data['date'] > today_for(load(user, tx)):
            raise DomainError(ErrorKind.INVALID_INPUT, 'Record only transfers already made.')
        for field in ('from_account', 'to_account'):
            check(data[field], user, tx, record['date'])
        record.update(id=key, user_id=user['id'], fingerprint=digest,
                      created_at=datetime.now(timezone.utc).isoformat())
        tx.put('account_transfers', record)
        cash_changed(user, tx)
        return record


def reconcile(data, user, db):
    key = sha256(f"account-check:{user['id']}:{data['operation_id']}".encode()).hexdigest()
    digest = sha256(json.dumps({k: v for k, v in data.items() if k != 'operation_id'}, sort_keys=True).encode()).hexdigest()
    with db.atomic(user['id']) as tx:
        previous = tx.get('account_reconciliations', id=key, user_id=user['id'])
        if previous:
            if previous['fingerprint'] != digest:
                raise DomainError(ErrorKind.CONFLICT, 'This request was already used for a different cash check.')
            return previous
        check(data['account_id'], user, tx)
        view = overview(user, tx)
        recorded = next(a['balance'] for a in view['items'] if a['id'] == data['account_id'])
        record = dict(id=key, user_id=user['id'], account_id=data['account_id'],
                      actual=data['actual'], recorded=recorded, difference=data['actual'] - recorded,
                      as_of=view['as_of'], created_at=datetime.now(timezone.utc).isoformat(), fingerprint=digest)
        tx.put('account_reconciliations', record)
        return record


def update(data, user, db):
    from .planning import load, today_for
    key = sha256(f"account-change:{user['id']}:{data['operation_id']}".encode()).hexdigest()
    payload = {k: v for k, v in data.items() if k != 'operation_id'}
    payload['opening_date'] = data['opening_date'].isoformat()
    digest = sha256(json.dumps(payload, sort_keys=True).encode()).hexdigest()
    with db.atomic(user['id']) as tx:
        prior = tx.get('account_changes', id=key, user_id=user['id'])
        if prior:
            if prior['fingerprint'] != digest:
                raise DomainError(ErrorKind.CONFLICT, 'This request was already used for a different account change.')
            return prior['after']
        old = check(data['account_id'], user, tx, allow_archived=True)
        if old.get('revision', 0) != data['expected_revision']:
            raise DomainError(ErrorKind.CONFLICT, 'This account changed. Reload and review before saving.')
        name = data['name'].strip()
        if not name or any(a['id'] != old['id'] and a['name'].casefold() == name.casefold()
                           for a in tx.find('money_accounts', user_id=user['id'])):
            raise DomainError(ErrorKind.INVALID_INPUT, 'Use a unique nonempty account name.')
        if data['opening_date'] > today_for(load(user, tx)):
            raise DomainError(ErrorKind.INVALID_INPUT, 'Choose today or an earlier opening date.')
        earlier_entries = any(e.get('account_id') == old['id'] and e['date'] < payload['opening_date']
                              for e in tx.find('transactions', user_id=user['id']))
        earlier_transfers = any(old['id'] in (t['from_account'], t['to_account']) and t['date'] < payload['opening_date']
                                for t in tx.find('account_transfers', user_id=user['id']))
        if earlier_entries or earlier_transfers:
            raise DomainError(ErrorKind.CONFLICT, 'The opening date cannot exclude existing transactions or transfers.')
        new = dict(old, name=name, opening_amount=data['opening_amount'],
                   opening_date=payload['opening_date'], archived=data['archived'],
                   revision=old.get('revision', 0) + 1)
        tx.put('money_accounts', new)
        tx.put('account_changes', dict(id=key, user_id=user['id'], account_id=old['id'],
                                      before=old, after=new, fingerprint=digest,
                                      created_at=datetime.now(timezone.utc).isoformat()))
        return new
