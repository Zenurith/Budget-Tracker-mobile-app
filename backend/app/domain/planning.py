"""Financial inputs and obligations. Payment links and expenses commit atomically."""
import calendar
import hashlib
import json
import re
from dataclasses import asdict
from datetime import date, datetime, timedelta, timezone
from uuid import uuid4
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from .errors import DomainError, ErrorKind
from .funding_state import cash_changed
from .finance import check_category, owned
from .planning_commands import FinancialProfile, Schedule, Payment

INCOME_FREQUENCIES = {'weekly', 'fortnightly', 'twice_monthly', 'monthly', 'quarterly', 'annually'}


def invalid(message):
    raise DomainError(ErrorKind.INVALID_INPUT, message)


def conflict(message='This plan has changed. Reload it before saving.'):
    raise DomainError(ErrorKind.CONFLICT, message)


def stamp():
    return datetime.now(timezone.utc).isoformat()


def load(user, db):
    if not db.get('users', id=user['id']):
        raise DomainError(ErrorKind.UNAUTHORIZED, 'Account not found.')
    return db.get('planning', id=user['id'], user_id=user['id']) or {
        'id': user['id'], 'user_id': user['id'], 'revision': 0, 'profile': None,
        'debts': {}, 'commitments': {}, 'payments': {}, 'operations': {},
    }


def today_for(plan):
    zone = (plan.get('profile') or {}).get('timezone', 'UTC')
    return datetime.now(ZoneInfo(zone)).date()


def check_revision(plan, expected):
    if plan['revision'] != expected:
        conflict()


def persist(plan, db, invalidate=False):
    plan['revision'] += 1
    plan['updated_at'] = stamp()
    plan.setdefault('created_at', plan['updated_at'])
    if invalidate and plan['profile']:
        plan['profile']['reviewed_at'] = None
        plan['profile']['debt_confirmation'] = 'unknown'
    db.put('planning', plan)


def active(record, on):
    return record['start_date'] <= on.isoformat() and (
        record.get('end_date') is None or record['end_date'] >= on.isoformat())


def public_plan(plan):
    profile = plan['profile']
    today = today_for(plan)
    missing = []
    if not profile:
        missing.append('Confirm your income sources, timezone and debt list.')
    else:
        if not profile.get('reviewed_at'):
            missing.append('Review and confirm the financial profile.')
        sources = [s for s in profile['income_sources'] if active(s, today)]
        if not sources:
            missing.append('Add current income sources, including explicit zero income if applicable.')
        if any(s['gross'] is None for s in sources):
            missing.append('Gross income is missing for one or more sources.')
        if any(s['net'] is None for s in sources):
            missing.append('Net income is missing for one or more sources.')
        if profile['debt_confirmation'] == 'unknown':
            missing.append('Confirm the full debt list or explicitly confirm no debt.')
        if any(d['amount'] is None for d in plan['debts'].values() if active(d, today)):
            missing.append('Required payment is missing for an active debt.')
    reviewed = profile.get('reviewed_at') if profile else None
    return {'revision': plan['revision'], 'profile': profile,
            'debts': list(plan['debts'].values()), 'commitments': list(plan['commitments'].values()),
            'as_of': today.isoformat(), 'timezone': (profile or {}).get('timezone', 'UTC'),
            'complete': not missing, 'missing_inputs': missing,
            'review_due': bool(reviewed and (datetime.now(timezone.utc) - datetime.fromisoformat(reviewed)).days >= 30)}


def get_plan(user, db):
    return public_plan(load(user, db))


def money(value, optional=False):
    if value is None and optional:
        return
    if type(value) is not int or not 0 <= value <= 100_000_000_000:
        invalid('Amounts must be nonnegative integer minor units.')


def save_profile(data: FinancialProfile, user, db):
    if data.currency != user['currency']:
        invalid('Use your account currency for every income source.')
    try:
        ZoneInfo(data.timezone)
    except (ZoneInfoNotFoundError, ValueError):
        invalid('Choose a valid IANA timezone, such as Asia/Kuala_Lumpur or Europe/London.')
    for target in (data.dsr_target, data.dti_target):
        if target is not None and (not isinstance(target, str) or not re.fullmatch(r'\d{1,4}(\.\d{1,2})?', target)):
            invalid('Ratio targets must be nonnegative percentages with up to two decimals.')
    sources = []
    ids = set()
    for source in data.income_sources:
        if not source.name.strip() or source.currency != user['currency']:
            invalid('Each income source needs a name and the account currency.')
        if source.frequency not in INCOME_FREQUENCIES:
            invalid('Choose a supported income frequency.')
        money(source.gross, optional=True)
        money(source.net, optional=True)
        if source.end_date and source.end_date < source.start_date:
            invalid('Income end date must not precede its start date.')
        if source.basis not in ('fixed_schedule', 'monthly_estimate'):
            invalid('Choose fixed income or an explicit monthly estimate.')
        if source.basis == 'monthly_estimate' and (source.frequency != 'monthly' or not source.notes.strip()):
            invalid('Variable income needs a monthly estimate and visible assumptions.')
        if source.gross is not None and source.net is not None and source.net > source.gross and not source.notes.strip():
            invalid('Explain why net income exceeds gross income, or correct the amounts.')
        record = dict(asdict(source), id=source.id or str(uuid4()), name=source.name.strip(),
                      start_date=source.start_date.isoformat(),
                      end_date=source.end_date.isoformat() if source.end_date else None)
        if record['id'] in ids:
            invalid('Income source IDs must be unique.')
        ids.add(record['id'])
        sources.append(record)
    if data.debt_confirmation not in ('unknown', 'complete', 'none'):
        invalid('Confirm the status of your debt list.')
    with db.atomic(user['id']) as tx:
        plan = load(user, tx)
        check_revision(plan, data.expected_revision)
        effective = datetime.now(ZoneInfo(data.timezone)).date()
        if data.debt_confirmation == 'none' and any(active(d, effective) for d in plan['debts'].values()):
            invalid('Your plan contains current debt. Review it before confirming no debt.')
        plan['profile'] = {'currency': data.currency, 'timezone': data.timezone,
                           'income_sources': sources, 'debt_confirmation': data.debt_confirmation,
                           'dsr_target': data.dsr_target, 'dti_target': data.dti_target,
                           'reviewed_at': stamp() if data.confirmed else None}
        persist(plan, tx)
        return public_plan(plan)


def save_schedule(kind, data: Schedule, user, db, id=None):
    if kind not in ('debts', 'commitments'):
        invalid('Unsupported schedule type.')
    if data.currency != user['currency'] or not data.name.strip():
        invalid('Use a name and your account currency.')
    money(data.amount, optional=kind == 'debts')
    money(data.outstanding_balance, optional=True)
    money(data.extra_payment)
    allowed = INCOME_FREQUENCIES if kind == 'debts' else {'daily', 'weekly', 'monthly'}
    if data.frequency not in allowed:
        invalid('Unsupported recurrence frequency.')
    if data.frequency == 'twice_monthly' and (data.second_day is None or not 1 <= data.second_day <= 31 or data.second_day == data.start_date.day):
        invalid('Twice-monthly schedules need a different second due day (1–31).')
    if data.status not in ('active', 'closed'):
        invalid('Choose active or closed.')
    end_date = data.end_date
    if data.status == 'closed' and end_date is None:
        invalid('A closed schedule needs its final effective date.')
    if end_date and end_date < data.start_date:
        invalid('End date must not precede start date.')
    if kind == 'debts' and data.debt_type == 'credit_card' and data.payment_basis != 'statement':
        invalid('Enter the statement-required credit-card payment; no percentage is assumed.')
    if kind == 'commitments' and (data.extra_payment or data.outstanding_balance is not None or data.debt_type != 'other' or data.payment_basis != 'scheduled'):
        invalid('Record debt payments under Debts, not as a separate recurring bill.')
    with db.atomic(user['id']) as tx:
        plan = load(user, tx)
        check_revision(plan, data.expected_revision)
        check_category(data.category_id, 'expense', user, tx)
        previous = plan[kind].get(id) if id else None
        if id and not previous:
            raise DomainError(ErrorKind.NOT_FOUND, 'Schedule not found.')
        linked = [p for p in plan['payments'].values() if p['schedule_id'] == id and p['kind'] == kind]
        record = dict(asdict(data), id=id or str(uuid4()), user_id=user['id'],
                      name=data.name.strip(), start_date=data.start_date.isoformat(),
                      end_date=end_date.isoformat() if end_date else None,
                      revision=(previous or {}).get('revision', 0) + 1,
                      created_at=(previous or {}).get('created_at', stamp()), updated_at=stamp())
        record.pop('expected_revision')
        if linked:
            if any(record[k] != previous[k] for k in ('amount', 'frequency', 'start_date', 'category_id', 'second_day', 'extra_payment')):
                conflict('This schedule has linked payments. Close it and create a new schedule to change payment terms.')
            if record['end_date'] and any(p['due_date'] > record['end_date'] for p in linked):
                conflict('The end date cannot remove an occurrence with a linked payment.')
        plan[kind][record['id']] = record
        persist(plan, tx, invalidate=kind == 'debts')
        return public_plan(plan)


def delete_schedule(kind, id, revision, user, db):
    with db.atomic(user['id']) as tx:
        plan = load(user, tx)
        check_revision(plan, revision)
        if id not in plan[kind]:
            raise DomainError(ErrorKind.NOT_FOUND, 'Schedule not found.')
        if any(p['schedule_id'] == id and p['kind'] == kind for p in plan['payments'].values()):
            conflict('This schedule has linked payments. Close it or explicitly unlink those payments first.')
        del plan[kind][id]
        persist(plan, tx, invalidate=kind == 'debts')
        return public_plan(plan)


def dates(schedule, start, end):
    origin = date.fromisoformat(schedule['start_date'])
    first = max(start, origin)
    last = min(end, date.fromisoformat(schedule['end_date'])) if schedule['end_date'] else end
    frequency = schedule['frequency']
    if first > last:
        return
    if frequency in ('daily', 'weekly', 'fortnightly'):
        step = {'daily': 1, 'weekly': 7, 'fortnightly': 14}[frequency]
        offset = max(0, ((first - origin).days + step - 1) // step)
        current = origin + timedelta(days=offset * step)
        while current <= last:
            yield current
            if (last - current).days < step:
                break
            current += timedelta(days=step)
    else:
        stride = {'monthly': 1, 'twice_monthly': 1, 'quarterly': 3, 'annually': 12}[frequency]
        month = origin.year * 12 + origin.month - 1
        beginning = first.year * 12 + first.month - 1
        month += max(0, (beginning - month) // stride) * stride
        final_month = last.year * 12 + last.month - 1
        while month <= final_month:
            year, index = divmod(month, 12)
            limit = calendar.monthrange(year, index + 1)[1]
            days = {min(origin.day, limit)}
            if frequency == 'twice_monthly':
                days.add(min(schedule['second_day'], limit))
            for day in sorted(days):
                current = date(year, index + 1, day)
                if first <= current <= last:
                    yield current
            month += stride


def occurrence(plan, kind, schedule, due, as_of):
    id = f"{kind}:{schedule['id']}:{due.isoformat()}"
    linked = [p for p in plan['payments'].values() if p['occurrence_id'] == id]
    paid = sum(p['amount'] for p in linked)
    expected = None if schedule['amount'] is None else schedule['amount'] + (schedule['extra_payment'] if kind == 'debts' else 0)
    remaining = None if expected is None else max(0, expected - paid)
    state = 'incomplete' if expected is None else 'paid' if remaining == 0 else 'partially_paid' if paid else 'overdue' if due < as_of else 'due'
    return {'id': id, 'kind': kind, 'schedule_id': schedule['id'], 'name': schedule['name'],
            'due_date': due.isoformat(), 'expected_amount': expected, 'paid_amount': paid,
            'remaining_amount': remaining, 'state': state, 'overdue': due < as_of and remaining != 0,
            'category_id': schedule['category_id'], 'currency': schedule['currency'],
            'payments': linked}


def list_occurrences(start, end, user, db, plan=None):
    if end < start or (end - start).days > 366:
        invalid('Choose a date range of at most 367 days.')
    plan = plan if plan is not None else load(user, db)
    today = today_for(plan)
    items = []
    for kind in ('debts', 'commitments'):
        for schedule in plan[kind].values():
            for due in dates(schedule, start, end):
                items.append(occurrence(plan, kind, schedule, due, today))
                if len(items) > 5000:
                    invalid('Too many occurrences. Choose a shorter date range.')
    items.sort(key=lambda item: (item['due_date'], item['id']))
    return {'items': items, 'revision': plan['revision'], 'as_of': today.isoformat(),
            'timezone': (plan['profile'] or {}).get('timezone', 'UTC'),
            'timezone_confirmed': plan['profile'] is not None}


def overview(start, end, user, db):
    plan = load(user, db)
    return {**public_plan(plan), 'occurrences': list_occurrences(start, end, user, db, plan)['items']}


def resolve_occurrence(plan, id):
    try:
        kind, schedule_id, raw_date = id.split(':')
        schedule = plan[kind][schedule_id] if kind in ('debts', 'commitments') else None
        due = date.fromisoformat(raw_date)
        if schedule is None or due not in dates(schedule, due, due):
            raise ValueError()
    except (ValueError, KeyError, TypeError):
        raise DomainError(ErrorKind.NOT_FOUND, 'Occurrence not found.')
    return occurrence(plan, kind, schedule, due, today_for(plan))


def pay(id, data: Payment, user, db):
    payload = asdict(data)
    payload.pop('expected_revision')
    fingerprint = hashlib.sha256(json.dumps({'occurrence_id': id, **payload}, sort_keys=True, default=str).encode()).hexdigest()
    with db.atomic(user['id']) as tx:
        plan = load(user, tx)
        previous = plan['operations'].get(data.operation_id)
        if previous:
            if previous['fingerprint'] != fingerprint:
                conflict('This operation ID was already used for a different payment.')
            return previous['result']
        check_revision(plan, data.expected_revision)
        due = resolve_occurrence(plan, id)
        if due['remaining_amount'] is None:
            invalid('Enter the required payment amount before recording a payment.')
        if data.transaction_id:
            if data.amount is not None or data.date is not None:
                invalid('Choose an existing expense or record a new payment, not both.')
            expense = owned('transactions', data.transaction_id, user, tx)
            if expense['type'] != 'expense' or expense.get('commitment_occurrence_id') or expense.get('wishlist_purchase_id'):
                conflict('Choose an expense that is not already linked to an obligation.')
        else:
            money(data.amount)
            if data.date is None or data.date > today_for(plan):
                invalid('Record only a payment already made, on or before today.')
            check_category(due['category_id'], 'expense', user, tx)
            expense = {'id': str(uuid4()), 'user_id': user['id'], 'amount': data.amount,
                       'type': 'expense', 'category_id': due['category_id'], 'date': data.date.isoformat(),
                       'note': data.note or due['name'], 'payment_method': 'Other',
                       'source': 'manual', 'created_at': stamp()}
        if date.fromisoformat(expense['date']) > today_for(plan):
            invalid('A future-dated transaction cannot confirm a payment already made.')
        if not 0 < expense['amount'] <= due['remaining_amount']:
            invalid('Payment must be positive and no larger than the unpaid amount. Record extra spending separately.')
        expense['commitment_occurrence_id'] = id
        tx.put('transactions', expense)
        cash_changed(user, tx)
        plan['payments'][expense['id']] = {
            'transaction_id': expense['id'], 'occurrence_id': id, 'kind': due['kind'],
            'schedule_id': due['schedule_id'], 'due_date': due['due_date'],
            'amount': expense['amount'], 'date': expense['date'], 'linked_at': stamp(),
        }
        result = {'transaction_id': expense['id'], 'occurrence_id': id, 'revision': plan['revision'] + 1}
        plan['operations'][data.operation_id] = {'fingerprint': fingerprint, 'result': result}
        persist(plan, tx)
        return result


def unlink(id, transaction_id, revision, user, db):
    with db.atomic(user['id']) as tx:
        plan = load(user, tx)
        check_revision(plan, revision)
        link = plan['payments'].get(transaction_id)
        if not link or link['occurrence_id'] != id:
            raise DomainError(ErrorKind.NOT_FOUND, 'Payment link not found.')
        expense = owned('transactions', transaction_id, user, tx)
        expense.pop('commitment_occurrence_id', None)
        tx.put('transactions', expense)
        cash_changed(user, tx)
        del plan['payments'][transaction_id]
        persist(plan, tx)
        return {'revision': plan['revision'], 'transaction_id': transaction_id}
