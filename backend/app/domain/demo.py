from datetime import date, datetime, timezone
from uuid import uuid4
from ..models import Budget, Transaction
from ..infrastructure.security import DUMMY_HASH
from .finance import add_transaction, set_budget

def demo(db=None, auth=None):
    user = {'id': str(uuid4()), 'name': 'Alex', 'email': f'{uuid4()}@demo.pocketwise.local', 'currency': 'MYR', 'password_hash': DUMMY_HASH, 'created_at': datetime.now(timezone.utc).isoformat()}
    db.put('users', user)
    today = date.today()
    first = today.replace(day=1)
    samples = [(480000, 'income', 'salary', 'Monthly salary', 1), (2450, 'expense', 'food', 'Lunch at the little café', 2), (1800, 'expense', 'transport', 'Grab ride home', 3), (12990, 'expense', 'shopping', 'A few everyday essentials', 5), (8990, 'expense', 'bills', 'Internet subscription', 6), (3600, 'expense', 'food', 'Weekend groceries', 8), (2200, 'expense', 'entertainment', 'Movie night', 10), (1250, 'expense', 'food', 'Morning coffee & toast', min(today.day, 12))]
    for amount, kind, category, note, day in samples:
        add_transaction(Transaction(amount=amount, type=kind, category_id=category, date=first.replace(day=min(day, today.day)), note=note), user, db)
    set_budget(Budget(period=today.strftime('%Y-%m'), limit_amount=200000), user, db)
    set_budget(Budget(period=today.strftime('%Y-%m'), category_id='food', limit_amount=60000), user, db)
    set_budget(Budget(period=today.strftime('%Y-%m'), category_id='shopping', limit_amount=30000), user, db)
    return auth.session(user, db)
