"""Current setup progress and cash availability, independent of report month."""
from datetime import datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo

from . import funding, funding_state, planning


def summary(user, db):
    with db.atomic(user['id']) as tx:
        plan = planning.load(user, tx)
        state = funding_state.load(user, tx)
        cash = funding.view(state, plan, user)
        profile = planning.public_plan(plan)
        today = planning.today_for(plan)
        period = today.strftime('%Y-%m')
        saved = state['plan']
        snapshot = state['snapshot']
        steps = [
            {'id': 'cash', 'done': snapshot is not None},
            {'id': 'income', 'done': profile['complete'] and not profile['review_due']},
            {'id': 'commitments', 'done': bool(saved and saved['planning_revision'] == plan['revision'])},
            {'id': 'budget', 'done': bool(tx.find('budgets', user_id=user['id'], period=period))},
            {'id': 'savings', 'done': bool(state['goals']), 'optional': True},
            {'id': 'review', 'done': cash['usable']},
        ]
        # A previously fetched amount expires at local midnight or after 24 hours.
        midnight = datetime.combine(today + timedelta(days=1), time.min,
                                    ZoneInfo(profile['timezone']))
        expires = midnight.astimezone(timezone.utc)
        if snapshot:
            expires = min(expires, datetime.fromisoformat(snapshot['as_of']) + timedelta(hours=24))
        keys = ('as_of', 'horizon_end', 'usable', 'free_to_allocate', 'coverage_shortfall',
                'liquid_total', 'scheduled_obligations', 'essential_allowances',
                'required_savings', 'emergency_reserved', 'savings_reserved',
                'wishlist_reserved', 'buffer_amount', 'missing_inputs', 'stale_reasons')
        return {
            'setup': {'steps': steps, 'budget_month': period,
                      'complete': all(s['done'] for s in steps if not s.get('optional'))},
            'availability': {**{key: cash[key] for key in keys},
                             'next_income_date': (saved or {}).get('next_income_date'),
                             'cash_reviewed_at': (snapshot or {}).get('as_of'),
                             'plan_reviewed_at': (saved or {}).get('reviewed_at'),
                             'expires_at': expires.isoformat()},
        }
