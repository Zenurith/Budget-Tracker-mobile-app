"""Budget tracking use cases. No HTTP or UI dependencies."""
import hashlib
from dataclasses import asdict
from collections import defaultdict
from datetime import date, datetime, timezone
from uuid import uuid4
from .commands import Budget, Category, ParseRequest, Transaction
from .errors import DomainError, ErrorKind
from .nlp import parse
from .ports import DocumentRepository
from .funding_state import cash_changed

DEFAULTS = [('food', 'Food', 'expense', 'restaurant', '#E3A25F'), ('transport', 'Transport', 'expense', 'directions_car', '#6D9DC5'), ('shopping', 'Shopping', 'expense', 'shopping_bag', '#AC8FC0'), ('bills', 'Bills', 'expense', 'receipt_long', '#D88679'), ('entertainment', 'Entertainment', 'expense', 'movie', '#7DB7A5'), ('health', 'Health', 'expense', 'favorite', '#D48FA6'), ('other-expense', 'Other expenses', 'expense', 'category', '#9AA6A0'), ('salary', 'Salary', 'income', 'work', '#4D8B70'), ('other-income', 'Other income', 'income', 'payments', '#79A897')]
CATEGORIES = [dict(id=i, name=n, type=t, icon=ic, color=c, user_id=None) for i, n, t, ic, c in DEFAULTS]

def categories(user, db: DocumentRepository):
    return CATEGORIES + db.find('categories', user_id=user['id'])

def check_category(cid, kind, user, db: DocumentRepository):
    if not any((c['id'] == cid and (kind is None or c['type'] == kind) for c in categories(user, db))):
        raise DomainError(ErrorKind.INVALID_INPUT, 'Select a valid category matching the transaction type.')

def owned(collection, id, user, db: DocumentRepository):
    doc = db.get(collection, id=id, user_id=user['id'])
    if not doc:
        raise DomainError(ErrorKind.NOT_FOUND, 'Item not found.')
    return doc

def list_categories(user=None, db: DocumentRepository = None):
    return {'items': categories(user, db)}

def add_category(data: Category, user=None, db: DocumentRepository = None):
    return db.put('categories', dict(asdict(data), id=str(uuid4()), user_id=user['id']))

def edit_category(id: str, data: Category, user=None, db: DocumentRepository = None):
    with db.atomic(user['id']) as db:
        plan = db.get('planning', id=user['id'], user_id=user['id']) or {}
        if data.type != 'expense' and any(s['category_id'] == id for kind in ('debts', 'commitments') for s in plan.get(kind, {}).values()):
            raise DomainError(ErrorKind.CONFLICT, 'This category is used by an obligation; keep its expense type.')
        old = owned('categories', id, user, db)
        if old['type'] != data.type and (db.find('transactions', user_id=user['id'], category_id=id) or db.find('budgets', user_id=user['id'], category_id=id)):
            raise DomainError(ErrorKind.CONFLICT, 'The type of a category in use cannot be changed.')
        return db.put('categories', dict(asdict(data), id=id, user_id=user['id']))

def delete_category(id: str, user=None, db: DocumentRepository = None):
    with db.atomic(user['id']) as db:
        plan = db.get('planning', id=user['id'], user_id=user['id']) or {}
        if any(s['category_id'] == id for kind in ('debts', 'commitments') for s in plan.get(kind, {}).values()):
            raise DomainError(ErrorKind.CONFLICT, 'This category is used by a debt or commitment schedule.')
        owned('categories', id, user, db)
        if db.find('transactions', user_id=user['id'], category_id=id) or db.find('budgets', user_id=user['id'], category_id=id):
            raise DomainError(ErrorKind.CONFLICT, 'Move transactions and remove budgets using this category first.')
        db.delete('categories', id=id, user_id=user['id'])

def list_transactions(start: date | None=None, end: date | None=None, category_id: str | None=None, type: str | None=None, q: str='', min_amount: int | None=None, max_amount: int | None=None, page: int=1, page_size: int=50, user=None, db: DocumentRepository = None):
    if start and end and start > end:
        raise DomainError(ErrorKind.INVALID_INPUT, 'Start date must be on or before end date.')
    if ((min_amount is not None and min_amount < 0) or (max_amount is not None and max_amount < 0)
            or (min_amount is not None and max_amount is not None and min_amount > max_amount)):
        raise DomainError(ErrorKind.INVALID_INPUT, 'Enter a valid minimum and maximum amount.')
    names = {c['id']: c['name'].lower() for c in categories(user, db)}
    docs = db.find('transactions', user_id=user['id'])
    docs = [d for d in docs if (not start or d['date'] >= start.isoformat()) and (not end or d['date'] <= end.isoformat()) and (not category_id or d['category_id'] == category_id) and (not type or d['type'] == type) and (q.lower() in d['note'].lower() or q.lower() in names.get(d['category_id'], '')) and (min_amount is None or d['amount'] >= min_amount) and (max_amount is None or d['amount'] <= max_amount)]
    docs.sort(key=lambda d: (d['date'], d['created_at'], d['id']), reverse=True)
    return {'items': docs[(page - 1) * page_size:page * page_size], 'total': len(docs), 'page': page, 'page_size': page_size}

def add_transaction(data: Transaction, user=None, db: DocumentRepository = None):
    with db.atomic(user['id']) as db:
        check_category(data.category_id, data.type, user, db)
        record = db.put('transactions', dict(dict(asdict(data), date=data.date.isoformat()), id=str(uuid4()), user_id=user['id'], created_at=datetime.now(timezone.utc).isoformat()))
        cash_changed(user, db)
        return record

def edit_transaction(id: str, data: Transaction, user=None, db: DocumentRepository = None):
    with db.atomic(user['id']) as db:
        if owned('transactions', id, user, db).get('commitment_occurrence_id'):
            raise DomainError(ErrorKind.CONFLICT, 'Unlink this payment from its obligation before editing or deleting the expense.')
        old = owned('transactions', id, user, db)
        check_category(data.category_id, data.type, user, db)
        record = db.put('transactions', dict(old, **dict(asdict(data), date=data.date.isoformat())))
        cash_changed(user, db)
        return record

def delete_transaction(id: str, user=None, db: DocumentRepository = None):
    with db.atomic(user['id']) as db:
        if owned('transactions', id, user, db).get('commitment_occurrence_id'):
            raise DomainError(ErrorKind.CONFLICT, 'Unlink this payment from its obligation before editing or deleting the expense.')
        owned('transactions', id, user, db)
        db.delete('transactions', id=id, user_id=user['id'])
        cash_changed(user, db)

def list_budgets(period: str=None, user=None, db: DocumentRepository = None):
    transactions = [d for d in db.find('transactions', user_id=user['id']) if d['date'].startswith(period) and d['type'] == 'expense']
    items = []
    for budget in db.find('budgets', user_id=user['id'], period=period):
        spent = sum((d['amount'] for d in transactions if not budget['category_id'] or d['category_id'] == budget['category_id']))
        items.append(dict(budget, spent=spent, remaining=budget['limit_amount'] - spent))
    return {'items': items}

def set_budget(data: Budget, user=None, db: DocumentRepository = None):
    if data.category_id:
        check_category(data.category_id, 'expense', user, db)
    id = hashlib.sha256(f"{user['id']}:{data.period}:{data.category_id}".encode()).hexdigest()
    return db.put('budgets', dict(asdict(data), id=id, user_id=user['id']))

def delete_budget(id: str, user=None, db: DocumentRepository = None):
    owned('budgets', id, user, db)
    db.delete('budgets', id=id, user_id=user['id'])

def summary(month: str=None, user=None, db: DocumentRepository = None):
    docs = db.find('transactions', user_id=user['id'])
    monthly = [d for d in docs if d['date'].startswith(month)]
    income = sum((d['amount'] for d in monthly if d['type'] == 'income'))
    expense = sum((d['amount'] for d in monthly if d['type'] == 'expense'))
    by_category = defaultdict(int)
    daily = defaultdict(int)
    for d in monthly:
        if d['type'] == 'expense':
            by_category[d['category_id']] += d['amount']
            daily[d['date']] += d['amount']
    trend = []
    year, number = map(int, month.split('-'))
    for offset in range(5, -1, -1):
        y, m = divmod(year * 12 + number - 1 - offset, 12)
        period = f'{y:04d}-{m + 1:02d}'
        group = [d for d in docs if d['date'].startswith(period)]
        trend.append({'month': period, 'income': sum((d['amount'] for d in group if d['type'] == 'income')), 'expense': sum((d['amount'] for d in group if d['type'] == 'expense'))})
    today = date.today()
    current = today.strftime('%Y-%m')
    review = {
        'period_status': 'in_progress' if month == current else 'future' if month > current else 'ended',
        'record_count': len(monthly),
        'recorded_days': len({d['date'] for d in monthly}),
        'coverage': 'Recorded entries only; missing activity cannot be detected.',
        'expense_change': expense - trend[-2]['expense'],
        'previous_month': trend[-2]['month'],
        'previous_record_count': sum(d['date'].startswith(trend[-2]['month']) for d in docs),
        'budget_variances': list_budgets(month, user, db)['items'],
    }
    return {'month': month, 'income': income, 'expenses': expense, 'balance': sum((d['amount'] * (1 if d['type'] == 'income' else -1) for d in docs if d['date'][:7] <= month)), 'net': income - expense, 'category_breakdown': dict(by_category), 'daily_expenses': dict(sorted(daily.items())), 'trend': trend, 'review': review}

def parse_entry(data: ParseRequest, user=None, db: DocumentRepository = None):
    return parse(data.text, data.reference_date, categories(user, db))
