"""Bounded CSV preview and atomic, replay-safe import with explicit duplicate review."""
import csv
from datetime import date, datetime, timezone
from decimal import Decimal, InvalidOperation
from hashlib import sha256
import io
import json
import re
from . import finance
from .commands import Transaction
from .errors import DomainError, ErrorKind


def signature(doc):
    return (doc['date'], doc['type'], doc['amount'], ' '.join(doc.get('note', '').casefold().split()))


def parse(contents, user, db):
    if len(contents.encode('utf-8')) > 1_000_000:
        raise DomainError(ErrorKind.INVALID_INPUT, 'CSV files must be at most 1 MB.')
    reader = csv.DictReader(io.StringIO(contents.lstrip('\ufeff')), strict=True)
    required = {'date', 'type', 'amount', 'category'}
    allowed = required | {'note', 'payment_method', 'currency'}
    try:
        fields = reader.fieldnames
    except csv.Error:
        raise DomainError(ErrorKind.INVALID_INPUT, 'Malformed CSV header.') from None
    if not fields or not required.issubset(fields) or not set(fields).issubset(allowed) or len(fields) != len(set(fields)):
        raise DomainError(ErrorKind.INVALID_INPUT, 'Use CSV headers date,type,amount,category and optional note,payment_method,currency.')
    categories = finance.categories(user, db)
    rows, seen = [], set()
    existing = {signature(d) for d in db.find('transactions', user_id=user['id'])}
    try:
        for index, row in enumerate(reader, 1):
            if index > 1000:
                raise DomainError(ErrorKind.INVALID_INPUT, 'Import at most 1,000 rows at a time.')
            result = {'row': index, 'error': None, 'duplicate': False, 'duplicate_reason': None}
            try:
                if None in row or any(value is None for value in row.values()):
                    raise ValueError('The number of fields does not match the headers.')
                when, kind, amount, category = (row[k].strip() for k in ('date', 'type', 'amount', 'category'))
                if not re.fullmatch(r'\d{4}-\d{2}-\d{2}', when):
                    raise ValueError('Use dates in YYYY-MM-DD format.')
                date.fromisoformat(when)
                if kind not in ('income', 'expense'):
                    raise ValueError('Type must be income or expense.')
                if not re.fullmatch(r'\d+(\.\d{1,2})?', amount):
                    raise ValueError('Use positive decimal amounts with at most two decimal places, without currency symbols.')
                cents = int(Decimal(amount) * 100)
                if not 0 < cents <= 100_000_000_000:
                    raise ValueError('Amount is outside the supported range.')
                matches = [c for c in categories if c['type'] == kind and (c['id'] == category or c['name'].casefold() == category.casefold())]
                if len(matches) != 1:
                    raise ValueError('Use an existing category name or ID matching the type.')
                if row.get('currency', user['currency']).strip() != user['currency']:
                    raise ValueError('Currency must match your Pocketwise account.')
                note, method = row.get('note', ''), row.get('payment_method', 'Cash')
                if len(note) > 500 or len(method) > 40:
                    raise ValueError('Note or payment method is too long.')
                doc = dict(date=when, type=kind, amount=cents, category_id=matches[0]['id'], note=note, payment_method=method, source='manual')
                key = signature(doc)
                reason = 'Matches an existing transaction' if key in existing else 'Repeated row in this file' if key in seen else None
                seen.add(key)
                result.update(transaction=doc, duplicate=reason is not None, duplicate_reason=reason)
            except (ValueError, InvalidOperation) as error:
                result['error'] = str(error)
            rows.append(result)
    except csv.Error:
        raise DomainError(ErrorKind.INVALID_INPUT, 'Malformed CSV. Check quotes and comma separators.') from None
    if not rows:
        raise DomainError(ErrorKind.INVALID_INPUT, 'The CSV has no transaction rows.')
    return {'items': rows, 'currency': user['currency'], 'total': len(rows)}


def commit(data, user, db):
    key = sha256(f"{user['id']}:{data['operation_id']}".encode()).hexdigest()
    fingerprint = sha256(json.dumps(data, sort_keys=True).encode()).hexdigest()
    with db.atomic(user['id']) as tx:
        previous = tx.get('csv_imports', id=key, user_id=user['id'])
        if previous:
            if previous['fingerprint'] != fingerprint:
                raise DomainError(ErrorKind.CONFLICT, 'This request ID was already used for another import.')
            return previous['result']
        preview = parse(data['contents'], user, tx)
        selected, approved = set(data['rows']), set(data['allow_duplicates'])
        if not selected or not selected.issubset({r['row'] for r in preview['items']}) or not approved.issubset(selected):
            raise DomainError(ErrorKind.INVALID_INPUT, 'Select valid rows to import.')
        picked = [row for row in preview['items'] if row['row'] in selected]
        if any(row['error'] for row in picked):
            raise DomainError(ErrorKind.INVALID_INPUT, 'Fix or deselect invalid rows before importing.')
        if any(row['duplicate'] and row['row'] not in approved for row in picked):
            raise DomainError(ErrorKind.CONFLICT, 'Possible duplicates found. Preview again and explicitly confirm any duplicates you want to keep.')
        ids = []
        for row in picked:
            values = dict(row['transaction'], date=date.fromisoformat(row['transaction']['date']))
            record = finance.add_transaction(Transaction(**values), user, tx)
            ids.append(record['id'])
        result = {'imported': len(ids), 'transaction_ids': ids}
        tx.put('csv_imports', {'id': key, 'user_id': user['id'], 'fingerprint': fingerprint,
                               'result': result, 'created_at': datetime.now(timezone.utc).isoformat()})
        return result
