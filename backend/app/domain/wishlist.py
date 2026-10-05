"""Wishlist projections and atomic purchase records; never initiate a payment."""
from calendar import monthrange
from dataclasses import asdict
from datetime import date, datetime
from zoneinfo import ZoneInfo
from urllib.parse import urlparse
from uuid import uuid4, uuid5, NAMESPACE_URL

from . import funding as f, funding_state as storage, planning
from .errors import DomainError, ErrorKind
from .finance import check_category, owned, categories
from .wishlist_commands import Item, Purchase, Adjustment


def item_for(state, id):
    item = state.get('wishlist', {}).get(id)
    if not item:
        raise DomainError(ErrorKind.NOT_FOUND, 'Wishlist item not found.')
    return item


def readiness(item, allocated, data, cost=None):
    cost = item['target_cost'] if cost is None else cost
    if not data['usable']:
        return 'Needs updated information', data['missing_inputs'] + data['stale_reasons']
    reasons = []
    if item['status'] != 'active':
        reasons.append('Only active items can be ready.')
    if data['coverage_shortfall']:
        reasons.append('Cash no longer covers all obligations and reservations.')
    if data['has_overdue_obligations']:
        reasons.append('Resolve overdue obligations first.')
    if data['has_unfunded_required_savings']:
        reasons.append('Fund the required savings due within this horizon first.')
    if reasons:
        return 'Review your plan', reasons
    if cost <= 0 or allocated < cost:
        return 'Still saving', ['Explicitly reserve the remaining target cost before recording a planned purchase.']
    other = (data['obligations_total'] + data['emergency_reserved'] + data['savings_reserved']
             + data['wishlist_reserved'] - allocated + data['buffer_amount'])
    if data['liquid_total'] - cost < other:
        return 'Review your plan', ['The remaining cash would not cover your plan.']
    return 'Ready under your plan', []


def projection(state, plan, user):
    data = f.view(state, plan, user)
    items = list(state.get('wishlist', {}).values())
    total = sum(i['monthly_contribution'] for i in items if i['status'] == 'active')
    surplus = data['monthly_forecast_surplus']
    result = []
    for item in sorted(items, key=lambda i: (-i['priority'], i['name'], i['id'])):
        allocated = state['reservations'].get(item['id'], 0)
        label, reasons = readiness(item, allocated, data)
        remaining = max(0, item['target_cost'] - allocated)
        forecast, months = None, None
        explanation = None
        contribution = item['monthly_contribution']
        if remaining == 0:
            explanation = 'Already funded. ' + (label if label != 'Ready under your plan' else 'Review readiness before recording a purchase.')
        elif item['status'] != 'active':
            explanation = 'Paused, archived and purchased items have no contribution forecast.'
        elif not data['usable']:
            explanation = 'Update cash and the funding plan before forecasting.'
        elif surplus is None or surplus <= 0:
            explanation = 'Confirm a positive monthly surplus after essentials, debt and protected savings.'
        elif total > surplus:
            explanation = 'Combined contributions exceed the confirmed monthly surplus. Explicitly reassign contributions.'
        elif contribution <= 0 or not item['next_contribution_date']:
            explanation = 'Choose a monthly contribution and its next date.'
        elif item['next_contribution_date'] < data['as_of']:
            explanation = 'Update the next planned contribution date.'
        else:
            months = (remaining + contribution - 1) // contribution
            start = date.fromisoformat(item['next_contribution_date'])
            year, month = divmod(start.year * 12 + start.month - 1 + months - 1, 12)
            if year > 9999:
                explanation = 'The forecast is beyond the supported calendar; review your contribution.'
            else:
                forecast = date(year, month + 1, min(start.day, monthrange(year, month + 1)[1])).isoformat()
                explanation = f'If you save {contribution} minor units monthly; future contributions are not funded cash.'
        quote = f.fingerprint([user['id'], item, data['revision'], data['planning_revision'], data['as_of']])
        result.append(dict(item, has_purchase=any(p['item_id'] == item['id'] and p['status'] == 'recorded' for p in state.get('purchases', {}).values()), funded_amount=allocated, remaining_target=remaining, readiness=label,
                           reasons=reasons, quote=quote, forecast_date=forecast, months_needed=months,
                           forecast_reason=explanation))
    return dict(data, wishlist=result, planned_contributions=total,
                snapshot_token=f.fingerprint(state['snapshot']) if state['snapshot'] else None,
                purchases=list(state.get('purchases', {}).values()))


def read(user, db):
    with db.atomic(user['id']) as tx:
        return dict(projection(storage.load(user, tx), planning.load(user, tx), user), categories=categories(user, tx))


def save(data: Item, user, db, id=None):
    f.currency(data.currency, user)
    planning.money(data.target_cost)
    planning.money(data.monthly_contribution)
    if not data.name.strip() or data.target_cost <= 0 or data.status not in ('active', 'paused', 'archived'):
        f.invalid('Name the item, enter a positive total cost and choose an editable status.')
    if data.reference_url and urlparse(data.reference_url).scheme not in ('https', 'http'):
        f.invalid('Use an http or https reference URL.')
    if data.monthly_contribution and (data.status != 'active' or not data.next_contribution_date):
        f.invalid('Only active items can have a contribution plan. Explicitly clear it when pausing or archiving.')
    with db.atomic(user['id']) as tx:
        state, plan = storage.load(user, tx), planning.load(user, tx)
        f.revisions(state, plan, data.expected_revision)
        if id:
            item_for(state, id)
            linked = any(p['item_id'] == id and p['status'] == 'recorded' for p in state.get('purchases', {}).values())
            if linked and data.status != 'archived':
                f.conflict('Purchased items can be archived. Reverse the purchase link before reopening them.')
        id = id or str(uuid4())
        values = asdict(data)
        values.pop('expected_revision')
        for key in ('target_date', 'next_contribution_date'):
            values[key] = values[key].isoformat() if values[key] else None
        state.setdefault('wishlist', {})[id] = dict(values, id=id, name=data.name.strip())
        storage.persist(state, tx)
        return projection(state, plan, user)


def delete(id, revision, user, db):
    with db.atomic(user['id']) as tx:
        state, plan = storage.load(user, tx), planning.load(user, tx)
        f.revisions(state, plan, revision)
        item_for(state, id)
        if state['reservations'].get(id, 0) or any(p['item_id'] == id for p in state.get('purchases', {}).values()):
            f.conflict('Release reservations first. Items with purchase history must be archived, not deleted.')
        del state['wishlist'][id]
        state['reservations'].pop(id, None)
        storage.persist(state, tx)
        return projection(state, plan, user)


def replay(state, digest, operation_id):
    old = state['operations'].get(operation_id)
    if old:
        if old['fingerprint'] != digest:
            f.conflict('This operation ID was used for a different request.')
        return old['result']


def digest_for(kind, id, data):
    payload = asdict(data)
    payload.pop('expected_revision')
    payload.pop('expected_planning_revision', None)
    return f.fingerprint([kind, id, payload])


def record_event(state, tx, user, operation_id, digest, kind, item_id, amount, **extra):
    id = str(uuid5(NAMESPACE_URL, f"pocketwise:wishlist:{user['id']}:{operation_id}"))
    result = dict(id=id, revision=state['revision'] + 1, kind=kind, item_id=item_id, amount=amount, **extra)
    tx.put('funding_events', dict(result, user_id=user['id'], currency=user['currency'],
                               created_at=f.now().isoformat(), prior_revision=state['revision']))
    state['operations'][operation_id] = dict(fingerprint=digest, result=result)
    storage.persist(state, tx)
    return result


def purchase(id, data: Purchase, user, db):
    f.currency(data.currency, user)
    planning.money(data.amount)
    if not data.confirmed or data.amount <= 0:
        f.invalid('Confirm the actual purchase and its positive total cost.')
    digest = digest_for('purchase', id, data)
    with db.atomic(user['id']) as tx:
        state, plan = storage.load(user, tx), planning.load(user, tx)
        previous = replay(state, digest, data.operation_id)
        if previous:
            return previous
        f.revisions(state, plan, data.expected_revision, data.expected_planning_revision)
        item = item_for(state, id)
        if any(p['item_id'] == id and p['status'] == 'recorded' for p in state.get('purchases', {}).values()):
            f.conflict('This item already has a purchase.')
        today = planning.today_for(plan)
        if data.date > today:
            f.invalid('Record a purchase that has already happened, not a future payment.')
        check_category(data.category_id, 'expense', user, tx)
        snapshot = state['snapshot']
        projected = projection(state, plan, user)
        allocated = state['reservations'].get(id, 0)
        snapshot_date = datetime.fromisoformat(snapshot['as_of']).astimezone(ZoneInfo((plan.get('profile') or {}).get('timezone', 'UTC'))).date() if snapshot else None
        assessed = 'not_assessed'
        if data.baseline_effect == 'subtract_from_prior_snapshot':
            current = next(i for i in projected['wishlist'] if i['id'] == id)
            if data.transaction_id or data.quote != current['quote']:
                f.conflict('Refresh the purchase review. Use the reconciled path for an existing expense.')
            label, _ = readiness(item, allocated, projected, data.amount)
            if label != 'Ready under your plan':
                f.conflict('Review funding for the actual purchase cost before using the planned purchase flow.')
            if data.date < snapshot_date:
                f.invalid('The purchase predates this snapshot. Reconcile and use the already included path.')
            account = next((a for a in snapshot['accounts'] if a['name'] == data.account_name), None)
            if not account or account['amount'] < data.amount:
                f.invalid('Choose an included account with enough confirmed cash for this payment.')
            account['amount'] -= data.amount
            snapshot['liquid_total'] -= data.amount
            assessed = 'ready_under_plan'
        elif data.baseline_effect == 'already_reconciled':
            if not snapshot or data.snapshot_token != projected['snapshot_token'] or not projected['fresh']:
                f.conflict('Newly reconcile your cash including this payment, then confirm its snapshot.')
            if data.date > snapshot_date:
                f.invalid('The snapshot must include the purchase date.')
        else:
            f.invalid('Specify whether the reconciled cash already includes this payment.')
        purchase_id = str(uuid5(NAMESPACE_URL, f"pocketwise:purchase:{user['id']}:{data.operation_id}"))
        if data.transaction_id:
            expense = owned('transactions', data.transaction_id, user, tx)
            if (expense['type'] != 'expense' or expense['amount'] != data.amount or expense['date'] != data.date.isoformat()
                    or expense['category_id'] != data.category_id or expense.get('commitment_occurrence_id')
                    or expense.get('wishlist_purchase_id')):
                f.conflict('Choose an unlinked expense with matching amount, date and category.')
            if expense['created_at'] > snapshot['reviewed_at']:
                f.conflict('Reconcile balances after recording this expense.')
        else:
            expense = dict(id=str(uuid4()), user_id=user['id'], amount=data.amount, type='expense',
                           category_id=data.category_id, date=data.date.isoformat(), note=item['name'],
                           payment_method='cash', source='manual', created_at=f.now().isoformat())
        expense['wishlist_purchase_id'] = purchase_id
        tx.put('transactions', expense)
        state['cash_revision'] += 1
        snapshot['cash_revision'] = state['cash_revision']
        state['reservations'][id] = 0
        item['status'] = 'purchased'
        item['monthly_contribution'] = 0
        state.setdefault('purchases', {})[purchase_id] = dict(id=purchase_id, item_id=id,
            transaction_id=expense['id'], amount=data.amount, date=data.date.isoformat(),
            baseline_effect=data.baseline_effect, readiness=assessed, allocated_consumed=allocated,
            status='recorded', refunds=[], created_at=f.now().isoformat())
        return record_event(state, tx, user, data.operation_id, digest, 'purchase', id, data.amount,
                            purchase_id=purchase_id, transaction_id=expense['id'])


def adjust(purchase_id, kind, data: Adjustment, user, db):
    f.currency(data.currency, user)
    if not data.confirmed or not data.reason.strip() or kind not in ('reverse', 'refund'):
        f.invalid('Confirm the correction or actual refund and explain the reason.')
    digest = digest_for(kind, purchase_id, data)
    with db.atomic(user['id']) as tx:
        state, plan = storage.load(user, tx), planning.load(user, tx)
        previous = replay(state, digest, data.operation_id)
        if previous:
            return previous
        f.revisions(state, plan, data.expected_revision)
        purchase = state.get('purchases', {}).get(purchase_id)
        if not purchase:
            raise DomainError(ErrorKind.NOT_FOUND, 'Purchase not found.')
        if purchase['status'] != 'recorded':
            f.conflict('This purchase link has already been reversed.')
        expense = owned('transactions', purchase['transaction_id'], user, tx)
        if kind == 'reverse':
            if data.amount or data.date or data.category_id:
                f.invalid('A link correction does not record returned money. Use an actual refund instead.')
            # Retain actual spending and the audit record; unlock correction explicitly.
            for tid in [expense['id']] + [r['transaction_id'] for r in purchase['refunds']]:
                entry = owned('transactions', tid, user, tx)
                entry.pop('wishlist_purchase_id', None)
                tx.put('transactions', entry)
            purchase.update(status='reversed', reversal_reason=data.reason, reversed_at=f.now().isoformat())
            state['wishlist'][purchase['item_id']]['status'] = 'active'
        else:
            planning.money(data.amount)
            if not data.amount or not data.date or data.date > planning.today_for(plan):
                f.invalid('Enter the actual refund amount and date.')
            if data.date.isoformat() < purchase['date']:
                f.invalid('A refund cannot predate the purchase.')
            if data.amount + sum(r['amount'] for r in purchase['refunds']) > purchase['amount']:
                f.conflict('Refunds cannot exceed the recorded purchase amount.')
            check_category(data.category_id, 'income', user, tx)
            entry = dict(id=str(uuid4()), user_id=user['id'], type='income', amount=data.amount,
                         date=data.date.isoformat(), category_id=data.category_id, note=data.reason,
                         payment_method='cash', source='manual', created_at=f.now().isoformat(),
                         wishlist_purchase_id=purchase_id)
            tx.put('transactions', entry)
            purchase['refunds'].append(dict(transaction_id=entry['id'], amount=data.amount, date=data.date.isoformat()))
        # Never assume a correction returned cash. Reconcile actual balances explicitly.
        state['cash_revision'] += 1
        return record_event(state, tx, user, data.operation_id, digest, kind, purchase['item_id'], data.amount,
                            purchase_id=purchase_id)


def monthly_review(month, user, db):
    with db.atomic(user['id']) as tx:
        state = storage.load(user, tx)
        view = f.view(state, planning.load(user, tx), user)
        purchases = [p for p in state.get('purchases', {}).values() if p['status'] == 'recorded']
        monthly = [p for p in purchases if p['date'].startswith(month)]
        return {'current_reserves': {key: view[key] for key in ('emergency_reserved', 'savings_reserved', 'wishlist_reserved')},
                'usable': view['usable'], 'as_of': view['as_of'],
                'purchase_count': len(monthly), 'purchase_total': sum(p['amount'] for p in monthly),
                'refund_total': sum(r['amount'] for p in purchases for r in p['refunds'] if r['date'].startswith(month)),
                'active_items': sum(i['status'] == 'active' for i in state.get('wishlist', {}).values())}
