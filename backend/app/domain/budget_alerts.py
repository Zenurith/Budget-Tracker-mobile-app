"""Current-month threshold checks; delivery and deduplication are device-local."""
from datetime import datetime, timezone
from zoneinfo import ZoneInfo
from . import finance, planning


def current(user, db, *, now=None):
    now = now or datetime.now(timezone.utc)
    with db.atomic(user['id']) as tx:
        profile = planning.load(user, tx)['profile']
        if not profile:
            return {'owner_id': user['id'], 'ready': False, 'items': [],
                    'reason': 'Set your financial profile timezone to check budget alerts.'}
        period = now.astimezone(ZoneInfo(profile['timezone'])).strftime('%Y-%m')
        budgets = finance.list_budgets(period, user, tx)['items']
        # Integer comparison avoids rounding an almost-reached threshold up.
        items = [{'id': b['id']} for b in budgets
                 if b['limit_amount'] > 0
                 and b['spent'] * 100 >= b['limit_amount'] * b['alert_threshold']]
        return {'owner_id': user['id'], 'ready': True, 'period': period,
                'timezone': profile['timezone'], 'items': items}
