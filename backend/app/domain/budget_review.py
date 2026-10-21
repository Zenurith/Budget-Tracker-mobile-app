"""Fresh monthly budget review; budget headroom is never verified cash."""
import calendar
from collections import defaultdict
from datetime import datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo
from . import finance, planning


def review(period, user, db, *, now=None):
    now = now or datetime.now(timezone.utc)
    with db.atomic(user['id']) as tx:
        profile = planning.load(user, tx)['profile']
        zone = ZoneInfo(profile['timezone']) if profile else None
        today = now.astimezone(zone).date() if zone else None
        year, month = map(int, period.split('-'))
        days = calendar.monthrange(year, month)[1]
        current = today is not None and today.strftime('%Y-%m') == period
        remaining_days = days - today.day + 1 if current else None
        totals = defaultdict(int)
        for entry in tx.find('transactions', user_id=user['id']):
            if entry['type'] == 'expense' and entry['date'].startswith(period):
                for part in finance.portions(entry):
                    totals[part['category_id']] += part['amount']
        names = {c['id']: c['name'] for c in finance.categories(user, tx)}
        items = []
        for budget in finance.list_budgets(period, user, tx)['items']:
            category = budget['category_id']
            contributions = [{'name': names.get(cid, 'Other'), 'amount': amount}
                             for cid, amount in totals.items()
                             if category is None or cid == category]
            contributions.sort(key=lambda c: (-c['amount'], c['name']))
            items.append(dict(budget,
                name=names.get(category, 'Other') if category else 'Overall monthly budget',
                threshold_reached=budget['spent'] * 100 >= budget['limit_amount'] * budget['alert_threshold'],
                daily_guide=max(0, budget['remaining']) // remaining_days if current else None,
                top_categories=contributions[:3]))
        expiry = min(now + timedelta(minutes=5), datetime.combine(today + timedelta(days=1), time(), zone).astimezone(timezone.utc)) if today else now + timedelta(minutes=5)
        return {'owner_id': user['id'], 'period': period, 'currency': user['currency'],
                'timezone': profile['timezone'] if profile else None,
                'days_remaining': remaining_days, 'current_month': current,
                'as_of': now.isoformat(), 'expires_at': expiry.isoformat(), 'items': items}
