"""Read-only cash projection. Expected income never authorizes spending."""
from datetime import datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo
from . import funding, funding_state, planning
from .errors import DomainError, ErrorKind


def calculate(assumptions, user, db):
    with db.atomic(user['id']) as tx:
        plan = planning.load(user, tx)
        state = funding_state.load(user, tx)
        today = planning.today_for(plan)
        end = today + timedelta(days=29)
        view = funding.view(state, plan, user)
        obligations, limit_error = funding.obligations(plan, end)
        reasons = list(view['missing_inputs']) + list(view['stale_reasons'])
        if limit_error:
            reasons.append(limit_error)
        if any(o['remaining_amount'] is None for o in obligations):
            reasons.append('Enter all required debt amounts in the next 30 days.')
        base = {'as_of': today.isoformat(), 'end': end.isoformat(), 'timezone': (plan['profile'] or {}).get('timezone', 'UTC')}
        if reasons:
            return dict(base, ready=False, reasons=list(dict.fromkeys(reasons)))
        for prefix in ('income', 'extra_expense'):
            when, amount = assumptions.get(prefix + '_date'), assumptions.get(prefix + '_amount')
            if (when is None) != (amount is None):
                raise DomainError(ErrorKind.INVALID_INPUT, 'Provide both a date and amount for each expected event.')
            if when and not today <= when <= end:
                raise DomainError(ErrorKind.INVALID_INPUT, f'Expected events must fall between {today} and {end}.')
        extra_events = assumptions.get('events', [])
        if extra_events and any(assumptions.get(prefix + suffix) is not None
                                for prefix in ('income', 'extra_expense') for suffix in ('_date', '_amount')):
            raise DomainError(ErrorKind.INVALID_INPUT, 'Use either event rows or the legacy single-event fields, not both.')
        for event in extra_events:
            if not today <= event['date'] <= end:
                raise DomainError(ErrorKind.INVALID_INPUT, f"Event {event['name']} must fall between {today} and {end}.")
        events = [{'date': e['date'].isoformat(), 'name': e['name'],
                   'kind': 'income' if e['kind'] == 'income' else 'extra_expense',
                   'amount': e['amount'] * (1 if e['kind'] == 'income' else -1), 'overdue': False}
                  for e in extra_events]
        for obligation in obligations:
            events.append({'date': max(today.isoformat(), obligation['due_date']), 'name': obligation['name'],
                           'kind': 'obligation', 'amount': -obligation['remaining_amount'],
                           'overdue': obligation['due_date'] < today.isoformat()})
        for prefix, sign in (('income', 1), ('extra_expense', -1)):
            if assumptions.get(prefix + '_date'):
                events.append({'date': assumptions[prefix + '_date'].isoformat(),
                               'name': 'Expected income' if sign == 1 else 'Additional expense scenario',
                               'kind': prefix, 'amount': sign * assumptions[prefix + '_amount'], 'overdue': False})
        for offset in range(30):
            events.append({'date': (today + timedelta(days=offset)).isoformat(),
                           'name': 'Additional everyday spending', 'kind': 'daily',
                           'amount': -assumptions['daily_spending'], 'overdue': False})
        # Conservatively place outflows before income on the same day.
        events.sort(key=lambda e: (e['date'], 1 if e['amount'] > 0 else 0, e['kind'], e['name']))
        balance = state['snapshot']['liquid_total']
        minimum = balance
        first_negative = today.isoformat() if balance < 0 else None
        first_below_buffer = today.isoformat() if balance < assumptions['buffer'] else None
        for event in events:
            balance += event['amount']
            event['balance'] = balance
            minimum = min(minimum, balance)
            if balance < 0 and first_negative is None:
                first_negative = event['date']
            if balance < assumptions['buffer'] and first_below_buffer is None:
                first_below_buffer = event['date']
        midnight = datetime.combine(today + timedelta(days=1), time.min, ZoneInfo(base['timezone'])).astimezone(timezone.utc)
        expires = min(midnight, datetime.fromisoformat(state['snapshot']['as_of']) + timedelta(hours=24), funding.now() + timedelta(minutes=5))
        return dict(base, ready=True, reasons=[], currency=user['currency'],
                    starting_balance=state['snapshot']['liquid_total'], ending_balance=balance,
                    minimum_balance=minimum, first_negative=first_negative, first_below_buffer=first_below_buffer,
                    buffer=assumptions['buffer'], events=events, expires_at=expires.isoformat(),
                    warnings=['Projection only, not available cash. Savings and wishlist reservations remain inside the projected cash balance.',
                              'Includes remaining scheduled obligations, with overdue payments assumed today. Outflows are placed before income on the same day.',
                              'Everyday spending is additional to scheduled obligations. Existing funding allowances are not also deducted. Include all other expected spending in your assumptions.',
                              'Expected income must not already be included in reconciled cash. Future-dated ordinary transactions are not automatically included.'])
