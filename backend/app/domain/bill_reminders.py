"""Read-only, grouped reminder dates from the authoritative unpaid occurrences."""
from collections import defaultdict
from datetime import datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo
from . import planning


def upcoming(lead_days, user, db, *, now=None):
    if lead_days not in (0, 1, 3, 7):
        planning.invalid('Choose a reminder lead time of 0, 1, 3 or 7 days.')
    now = now or datetime.now(timezone.utc)
    with db.atomic(user['id']) as tx:
        plan = planning.load(user, tx)
        profile = plan['profile']
        if not profile:
            return {'owner_id': user['id'], 'ready': False, 'items': [],
                    'reason': 'Set the timezone in your financial profile before scheduling reminders.'}
        zone = ZoneInfo(profile['timezone'])
        today = now.astimezone(zone).date()
        window_end = today + timedelta(days=59)
        groups = defaultdict(int)
        occurrences = planning.list_occurrences(today + timedelta(days=lead_days),
            window_end + timedelta(days=lead_days), user, tx, plan)['items']
        for item in occurrences:
            # Partial and unknown amounts still need review; fully paid/zero do not.
            if item['remaining_amount'] != 0:
                groups[item['due_date']] += 1
        items = []
        for due, count in sorted(groups.items()):
            due_date = datetime.fromisoformat(due).date()
            fire = datetime.combine(due_date - timedelta(days=lead_days), time(9), zone)
            if fire <= now:
                continue  # Never replay a missed reminder just because the app reopened.
            items.append({'id': due_date.toordinal(), 'due_date': due, 'count': count,
                          'fire_at': fire.astimezone(timezone.utc).isoformat()})
        return {'owner_id': user['id'], 'ready': True, 'items': items,
                'timezone': profile['timezone'], 'window_end': window_end.isoformat(),
                'generated_at': now.isoformat(), 'planning_revision': plan['revision']}
