"""Protected cash, obligations and reservations. All money uses integer minor units."""
from dataclasses import asdict
from datetime import date, datetime, timedelta, timezone
from hashlib import sha256
import json
from uuid import uuid4, uuid5, NAMESPACE_URL

from . import funding_state as storage, planning
from .errors import DomainError, ErrorKind
from .funding_commands import CashSnapshot, FundingPlan, Goal, Allocation


def now():
    return datetime.now(timezone.utc)


def invalid(message):
    raise DomainError(ErrorKind.INVALID_INPUT, message)


def conflict(message):
    raise DomainError(ErrorKind.CONFLICT, message)


def fingerprint(value):
    return sha256(json.dumps(value, sort_keys=True, default=str).encode()).hexdigest()


def revisions(state, plan, expected, expected_planning=None):
    if state['revision'] != expected or (expected_planning is not None and plan['revision'] != expected_planning):
        conflict('Your cash or obligations changed. Refresh and review before saving.')


def currency(value, user):
    if value != user['currency']:
        invalid('Use your account currency. No currency conversion is assumed.')


def goal_hash(state):
    return fingerprint(state['goals'])


def horizon(funding_plan, today):
    next_income = (funding_plan or {}).get('next_income_date')
    return date.fromisoformat(next_income) if next_income else today + timedelta(days=29)


def obligations(plan, end):
    """Include all known overdue occurrences; fail closed instead of truncating history."""
    today = planning.today_for(plan)
    items, count = [], 0
    for kind in ('debts', 'commitments'):
        for schedule in plan[kind].values():
            for due in planning.dates(schedule, date.fromisoformat(schedule['start_date']), end):
                count += 1
                if count > 10000:
                    return items, 'Too many scheduled occurrences to assess. Review the schedule start dates.'
                item = planning.occurrence(plan, kind, schedule, due, today)
                if item['remaining_amount'] != 0:
                    items.append(item)
    items.sort(key=lambda x: (x['due_date'], x['id']))
    return items, None


def view(state, plan, user):
    today = planning.today_for(plan)
    saved_plan, snapshot = state['plan'], state['snapshot']
    end = horizon(saved_plan, today)
    missing, stale = [], []
    profile = plan.get('profile') or {}
    if not profile.get('reviewed_at') or profile.get('debt_confirmation') not in ('complete', 'none'):
        missing.append('Review your financial profile and explicitly confirm the debt list.')
    if not saved_plan:
        missing.append('Confirm the horizon, essential allowances, buffer and forecast surplus, including explicit zeros.')
    else:
        if saved_plan['planning_revision'] != plan['revision']:
            stale.append('Debt, bill or payment details changed. Review the funding plan.')
        if saved_plan['goals_hash'] != goal_hash(state):
            stale.append('Protected savings goals changed. Review the funding plan.')
        if saved_plan['review_date'] != today.isoformat():
            stale.append('Review today’s horizon and remaining essential allowances.')
        if end < today:
            stale.append('The next income date has passed. Confirm a new horizon.')
    if not snapshot:
        missing.append('Confirm your actual liquid cash and included accounts, including zero cash.')
    else:
        age = now() - datetime.fromisoformat(snapshot['as_of'])
        if age > timedelta(hours=24) or age < timedelta(0):
            stale.append('The cash snapshot is older than 24 hours or has an invalid timestamp.')
        if snapshot['cash_revision'] != state['cash_revision']:
            stale.append('Recorded cash activity changed. Reconcile the current account balances.')
    items, limit_error = obligations(plan, max(end, today))
    if limit_error:
        missing.append(limit_error)
    if any(item['remaining_amount'] is None for item in items):
        missing.append('Enter the required amount for every unpaid debt occurrence.')
    scheduled = sum(item['remaining_amount'] or 0 for item in items)
    by_schedule = {}
    for item in items:
        key = f"{item['kind']}:{item['schedule_id']}"
        by_schedule[key] = by_schedule.get(key, 0) + (item['remaining_amount'] or 0)
    allowances = []
    for entry in (saved_plan or {}).get('essential_allowances', []):
        linked = sum(by_schedule.get(key, 0) for key in entry['schedule_ids'])
        allowances.append(dict(entry, scheduled_within_allowance=linked, additional_amount=max(0, entry['amount'] - linked)))
    goals, required = [], 0
    emergency, savings = 0, 0
    unresolved_saving = False
    for id, goal in state['goals'].items():
        funded = state['reservations'].get(id, 0)
        gap = max(0, goal['required_amount'] - funded) if goal['included_in_cash'] else 0
        in_horizon = bool(goal['required_by'] and goal['required_by'] <= end.isoformat())
        protected_due = gap if in_horizon else 0
        required += protected_due
        unresolved_saving |= protected_due > 0
        if goal['kind'] == 'emergency':
            emergency += funded
        else:
            savings += funded
        goals.append(dict(goal, funded_amount=funded, required_unfunded=protected_due))
    allowance_total = sum(a['additional_amount'] for a in allowances)
    obligations_total = scheduled + allowance_total + required
    liquid = snapshot['liquid_total'] if snapshot else None
    buffer = saved_plan['buffer_amount'] if saved_plan else None
    complete = not missing
    usable = complete and not stale
    wishlist = sum(state['reservations'].get(id, 0) for id in state.get('wishlist', {}))
    protected = obligations_total + emergency + savings + wishlist + (buffer or 0)
    # A stale calculation remains inspectable, but never authorizes a contribution.
    free = max(0, liquid - protected) if complete and liquid is not None and buffer is not None else None
    shortfall = max(0, protected - liquid) if complete and liquid is not None and buffer is not None else None
    return {'revision': state['revision'], 'planning_revision': plan['revision'],
            'cash_revision': state['cash_revision'], 'currency': user['currency'],
            'as_of': today.isoformat(), 'timezone': profile.get('timezone'), 'horizon_end': end.isoformat(),
            'schedules': [dict(id=f'{kind}:{s["id"]}', name=s['name']) for kind in ('debts', 'commitments') for s in plan[kind].values()],
            'snapshot': snapshot, 'plan': saved_plan, 'goals': goals, 'occurrences': items,
            'wishlist': [dict(i, funded_amount=state['reservations'].get(i['id'], 0)) for i in state.get('wishlist', {}).values()],
            'allowances': allowances, 'complete': complete, 'fresh': not stale,
            'usable': usable, 'missing_inputs': missing, 'stale_reasons': stale,
            'liquid_total': liquid, 'scheduled_obligations': scheduled,
            'essential_allowances': allowance_total, 'required_savings': required,
            'obligations_total': obligations_total, 'emergency_reserved': emergency,
            'savings_reserved': savings, 'wishlist_reserved': wishlist, 'buffer_amount': buffer,
            'free_to_allocate': free, 'coverage_shortfall': shortfall,
            'can_allocate': usable and shortfall == 0,
            'has_overdue_obligations': any(i['overdue'] for i in items),
            'has_unfunded_required_savings': unresolved_saving,
            'monthly_forecast_surplus': (saved_plan or {}).get('monthly_forecast_surplus'),
            'warnings': ['Cash is manually reconciled, not bank-verified. Expected income contributes no available money.',
                         'All debt and recurring-bill occurrences are protected, including overdue and planned extra payments.']}


def availability(user, db):
    with db.atomic(user['id']) as tx:
        return view(storage.load(user, tx), planning.load(user, tx), user)


def save_snapshot(data: CashSnapshot, user, db):
    currency(data.currency, user)
    if not data.confirmed:
        invalid('Confirm that these balances include all spending already made and all reserves held in the included accounts.')
    if not data.accounts or len(data.accounts) > 30:
        invalid('List at least one included account; enter zero explicitly if you have no cash.')
    names = set()
    for account in data.accounts:
        planning.money(account.amount)
        if not account.name.strip() or account.name.strip().casefold() in names:
            invalid('Use distinct nonempty names for included accounts.')
        names.add(account.name.strip().casefold())
    if data.as_of.tzinfo is None or not timedelta(0) <= now() - data.as_of <= timedelta(hours=24):
        invalid('Reconcile cash using a timestamp within the last 24 hours, including its timezone.')
    with db.atomic(user['id']) as tx:
        state, plan = storage.load(user, tx), planning.load(user, tx)
        revisions(state, plan, data.expected_revision, data.expected_planning_revision)
        state['snapshot'] = {'currency': data.currency,
            'accounts': [dict(name=a.name.strip(), amount=a.amount) for a in data.accounts],
            'liquid_total': sum(a.amount for a in data.accounts), 'as_of': data.as_of.astimezone(timezone.utc).isoformat(),
            'reviewed_at': now().isoformat(), 'cash_revision': state['cash_revision']}
        storage.persist(state, tx)
        return view(state, plan, user)


def save_plan(data: FundingPlan, user, db):
    currency(data.currency, user)
    planning.money(data.buffer_amount)
    if type(data.monthly_forecast_surplus) is not int or abs(data.monthly_forecast_surplus) > 100_000_000_000:
        invalid('Enter the confirmed monthly forecast surplus, including zero or a shortfall.')
    if not data.confirmed:
        invalid('Review all obligations, savings requirements and the horizon before confirming.')
    with db.atomic(user['id']) as tx:
        state, plan = storage.load(user, tx), planning.load(user, tx)
        revisions(state, plan, data.expected_revision, data.expected_planning_revision)
        today = planning.today_for(plan)
        if data.next_income_date and not today <= data.next_income_date <= today + timedelta(days=366):
            invalid('Confirm an income date from today through the next 366 days, or use the 30-day horizon.')
        linked, names = set(), set()
        for allowance in data.essential_allowances:
            planning.money(allowance.amount)
            if not allowance.name.strip() or allowance.name.strip().casefold() in names:
                invalid('Use distinct names for essential allowances.')
            names.add(allowance.name.strip().casefold())
            for key in allowance.schedule_ids:
                try:
                    kind, id = key.split(':')
                    if kind not in ('debts', 'commitments') or id not in plan[kind]:
                        raise ValueError()
                except (ValueError, KeyError):
                    raise DomainError(ErrorKind.NOT_FOUND, 'Linked schedule not found.')
                if key in linked:
                    invalid('Link each schedule to at most one allowance to avoid double counting.')
                linked.add(key)
        state['plan'] = {'currency': data.currency, 'next_income_date': data.next_income_date.isoformat() if data.next_income_date else None,
            'buffer_amount': data.buffer_amount, 'monthly_forecast_surplus': data.monthly_forecast_surplus,
            'essential_allowances': [dict(name=a.name.strip(), amount=a.amount, schedule_ids=list(a.schedule_ids)) for a in data.essential_allowances],
            'planning_revision': plan['revision'], 'goals_hash': goal_hash(state),
            'review_date': today.isoformat(), 'reviewed_at': now().isoformat()}
        storage.persist(state, tx)
        return view(state, plan, user)


def save_goal(data: Goal, user, db, id=None):
    currency(data.currency, user)
    if not data.name.strip() or data.kind not in ('emergency', 'savings'):
        invalid('Name the emergency reserve or savings goal.')
    for amount in (data.target_amount, data.excluded_balance, data.required_amount):
        planning.money(amount)
    if bool(data.required_amount) != bool(data.required_by):
        invalid('A required saving amount needs a due date; clear both when none is required.')
    if (data.included_in_cash and data.excluded_balance) or (not data.included_in_cash and data.required_amount):
        invalid('Outside-account savings are recorded separately and cannot receive cash allocations or required contributions here.')
    with db.atomic(user['id']) as tx:
        state, plan = storage.load(user, tx), planning.load(user, tx)
        revisions(state, plan, data.expected_revision)
        if id and id not in state['goals']:
            raise DomainError(ErrorKind.NOT_FOUND, 'Goal not found.')
        if id and state['reservations'].get(id, 0) and not data.included_in_cash:
            conflict('Release reserved cash explicitly before moving this goal outside included accounts.')
        id = id or str(uuid4())
        state['goals'][id] = {k: v for k, v in asdict(data).items() if k != 'expected_revision'} | {
            'id': id, 'name': data.name.strip(), 'required_by': data.required_by.isoformat() if data.required_by else None}
        storage.persist(state, tx)
        return view(state, plan, user)


def delete_goal(id, revision, user, db):
    with db.atomic(user['id']) as tx:
        state, plan = storage.load(user, tx), planning.load(user, tx)
        revisions(state, plan, revision)
        if id not in state['goals']:
            raise DomainError(ErrorKind.NOT_FOUND, 'Goal not found.')
        if state['reservations'].get(id, 0):
            conflict('Explicitly release or reallocate all reserved cash before deleting this goal.')
        del state['goals'][id]
        state['reservations'].pop(id, None)
        storage.persist(state, tx)
        return view(state, plan, user)


def allocate(kind, data: Allocation, user, db):
    currency(data.currency, user)
    planning.money(data.amount)
    if data.amount == 0:
        invalid('Enter a positive allocation amount.')
    if kind not in ('allocate', 'release', 'reallocate'):
        invalid('Unknown allocation operation.')
    if ((kind == 'allocate' and (not data.target_id or data.source_id)) or
        (kind == 'release' and (not data.source_id or data.target_id)) or
        (kind == 'reallocate' and (not data.source_id or not data.target_id or data.source_id == data.target_id))):
        invalid('Choose the correct source and destination goals.')
    payload = asdict(data)
    payload.pop('expected_revision'); payload.pop('expected_planning_revision')
    digest = fingerprint({'kind': kind, **payload})
    with db.atomic(user['id']) as tx:
        state, plan = storage.load(user, tx), planning.load(user, tx)
        previous = state['operations'].get(data.operation_id)
        if previous:
            if previous['fingerprint'] != digest:
                conflict('This operation ID was used for a different allocation.')
            return previous['result']
        revisions(state, plan, data.expected_revision, data.expected_planning_revision)
        for id in (data.source_id, data.target_id):
            if id and id not in state['goals'] and id not in state.get('wishlist', {}):
                raise DomainError(ErrorKind.NOT_FOUND, 'Goal not found.')
            if id in state['goals'] and not state['goals'][id]['included_in_cash']:
                invalid('Savings outside included accounts are not part of this cash reservation ledger.')
        if data.target_id in state.get('wishlist', {}) and state['wishlist'][data.target_id]['status'] != 'active':
            conflict('Only active wishlist items can receive new reservations.')
        before = view(state, plan, user)
        if kind != 'release' and not before['usable']:
            conflict('Reconcile cash and review the funding plan before reserving or moving money.')
        if data.source_id:
            if state['reservations'].get(data.source_id, 0) < data.amount:
                conflict('This goal does not have that much reserved cash.')
            state['reservations'][data.source_id] -= data.amount
        if data.target_id:
            state['reservations'][data.target_id] = state['reservations'].get(data.target_id, 0) + data.amount
        after = view(state, plan, user)
        # Funding a required saving moves its cash from O into E/G; it is counted once.
        if kind != 'release' and after['coverage_shortfall'] != 0:
            conflict('This allocation would leave obligations, reserves or the buffer uncovered.')
        event_id = str(uuid5(NAMESPACE_URL, f"pocketwise:funding:{user['id']}:{data.operation_id}"))
        result = {'id': event_id, 'revision': state['revision'] + 1, 'kind': kind,
                  'source_id': data.source_id, 'target_id': data.target_id, 'amount': data.amount}
        event = dict(result, user_id=user['id'], currency=user['currency'], created_at=now().isoformat(),
                     prior_revision=state['revision'])
        tx.put('funding_events', event)
        state['operations'][data.operation_id] = {'fingerprint': digest, 'result': result}
        storage.persist(state, tx)
        return result


def events(user, db, page=1, page_size=20):
    items = sorted(db.find('funding_events', user_id=user['id']), key=lambda e: (e['created_at'], e['id']), reverse=True)
    return {'items': items[(page-1)*page_size:page*page_size], 'page': page, 'total': len(items)}
