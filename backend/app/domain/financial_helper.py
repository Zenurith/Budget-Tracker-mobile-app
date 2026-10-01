"""Authoritative debt ratios. No transaction totals, external models or float arithmetic."""
import calendar
from copy import deepcopy
from dataclasses import asdict, dataclass
from datetime import date, datetime, timezone
from decimal import Decimal, ROUND_HALF_UP, localcontext
import hashlib
import json
from uuid import NAMESPACE_URL, uuid5

from . import planning
from .errors import DomainError, ErrorKind

FORMULA_VERSION = 'debt-ratios-v1'
FACTORS = {'weekly': (52, 12), 'fortnightly': (26, 12), 'twice_monthly': (2, 1),
           'monthly': (1, 1), 'quarterly': (1, 3), 'annually': (1, 12)}


@dataclass(frozen=True, kw_only=True)
class Scenario:
    currency: str
    gross_monthly: int | None = None
    net_monthly: int | None = None
    additional_debt_monthly: int = 0
    debt_payments: tuple[tuple[str, int], ...] = ()
    notes: str = ''


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, default=str).encode()).hexdigest()


def input_hash(plan):
    return digest({'profile': plan['profile'], 'debts': plan['debts']})


def normalized(amount, frequency):
    if amount is None:
        return None
    planning.money(amount)
    numerator, denominator = FACTORS[frequency]
    return Decimal(amount) * numerator / denominator


def decimal_text(value):
    return None if value is None else format(value, 'f')


def rounded(value):
    return None if value is None else format(value.quantize(Decimal('.01'), rounding=ROUND_HALF_UP), 'f')


def calculate_plan(plan, currency, effective_date=None, scenario=None):
    # Explicit context makes results independent of request-thread decimal settings.
    with localcontext() as ctx:
        ctx.prec = 50
        return _calculate(plan, currency, effective_date or planning.today_for(plan), scenario)


def _calculate(plan, currency, on, scenario):
    profile = plan['profile'] or {}
    incomes = [deepcopy(s) for s in profile.get('income_sources', []) if planning.active(s, on)]
    debts = [deepcopy(d) for d in plan['debts'].values() if planning.active(d, on)]
    if profile.get('currency', currency) != currency or any(r['currency'] != currency for r in incomes + debts):
        planning.invalid('All calculation inputs must use the account currency.')
    if scenario:
        if scenario.currency != currency:
            planning.invalid('Scenario currency must match your account.')
        for value in (scenario.gross_monthly, scenario.net_monthly):
            planning.money(value, optional=True)
        planning.money(scenario.additional_debt_monthly)
        overrides = dict(scenario.debt_payments)
        if len(overrides) != len(scenario.debt_payments):
            planning.invalid('Specify each debt only once.')
        for id, amount in overrides.items():
            if id not in plan['debts']:
                raise DomainError(ErrorKind.NOT_FOUND, 'Debt not found.')
            if not planning.active(plan['debts'][id], on):
                planning.invalid('Only debts effective on the scenario date can be changed.')
            planning.money(amount)
        for debt in debts:
            if debt['id'] in overrides:
                debt.update(amount=overrides[debt['id']], frequency='monthly')

    missing = []
    def missing_input(field, code, message):
        missing.append({'field': field, 'code': code, 'message': message})
    reviewed = profile.get('reviewed_at')
    if not reviewed:
        missing_input('profile', 'unconfirmed', 'Review and confirm your income and debt profile.')
    debt_confirmed = profile.get('debt_confirmation') in ('none', 'complete')
    if not debt_confirmed:
        missing_input('debts', 'unconfirmed', 'Confirm your full debt list or explicitly confirm no debt.')
    if any(d['amount'] is None for d in debts):
        missing_input('debts', 'missing_payment', 'Enter the required payment for every effective debt.')
    debt_known = debt_confirmed and all(d['amount'] is not None for d in debts)
    income_totals = {}
    for basis in ('gross', 'net'):
        override = getattr(scenario, f'{basis}_monthly') if scenario else None
        value = (sum((normalized(s[basis], s['frequency']) for s in incomes), Decimal(0))
                 if incomes and all(s[basis] is not None for s in incomes) else None)
        if override is not None:
            value = Decimal(override)
        income_totals[basis] = value
        if value is None:
            missing_input(basis, 'missing_income', f'Enter {basis} income for every effective source.')
        elif value == 0:
            missing_input(basis, 'zero_income', f'{basis.capitalize()} income is zero; its ratio is unavailable.')
    gross, net = income_totals['gross'], income_totals['net']
    if (scenario and (scenario.net_monthly is not None or scenario.gross_monthly is not None)
            and net is not None and gross is not None and net > gross and not scenario.notes.strip()):
        planning.invalid('Explain scenario net income above gross income, or correct the amounts.')
    debt_total = sum((normalized(d['amount'], d['frequency']) or Decimal(0) for d in debts), Decimal(0))
    if scenario:
        debt_total += scenario.additional_debt_monthly
    if not debt_known:
        debt_total = None

    ratios = {}
    for label, basis in (('dsr', 'net'), ('dti', 'gross')):
        denominator = income_totals[basis]
        reasons = [m for m in missing if m['field'] in ('profile', 'debts', basis)]
        available = not reasons
        raw_ratio = debt_total / denominator * 100 if available else None
        target = profile.get(f'{label}_target')
        ratios[label] = {'value': rounded(raw_ratio), 'income_basis': basis, 'reasons': reasons,
                         'target': target, 'distance_to_target': rounded(raw_ratio - Decimal(target))
                         if raw_ratio is not None and target is not None else None}
    review_due = bool(reviewed and (datetime.now(timezone.utc) - datetime.fromisoformat(reviewed)).days >= 30)
    warnings = ['Income after debt has not deducted essentials or savings. This is a personal estimate, not a lender assessment.']
    if review_due:
        warnings.append('Your profile review is at least 30 days old. Review your inputs again.')
    if on != planning.today_for(plan):
        warnings.append('This date uses your currently declared schedules, not a historical income record or forecast guarantee.')
    if scenario:
        warnings.append('Hypothetical assumptions only. No income, debt or transaction has been changed.')
    for source in incomes:
        if source.get('notes'):
            warnings.append(f"{source['name']}: {source['notes']}")
    after_debt = net - debt_total if reviewed and net is not None and debt_total is not None else None
    return {'formula_version': FORMULA_VERSION, 'calculated_at': planning.stamp(),
            'source_revision': plan['revision'], 'input_hash': input_hash(plan),
            'effective_date': on.isoformat(), 'currency': currency,
            'kind': 'scenario' if scenario else 'baseline', 'reviewed_at': reviewed,
            'review_due': review_due, 'complete': not missing, 'missing_inputs': missing,
            'warnings': warnings, 'ratios': ratios,
            'gross_monthly': decimal_text(gross), 'net_monthly': decimal_text(net),
            'debt_monthly': decimal_text(debt_total), 'income_after_debt': decimal_text(after_debt),
            'income_sources': [dict(s, gross_monthly=decimal_text(normalized(s['gross'], s['frequency'])),
                                    net_monthly=decimal_text(normalized(s['net'], s['frequency']))) for s in incomes],
            'debts': [dict(d, monthly_payment=decimal_text(normalized(d['amount'], d['frequency']))) for d in debts],
            'assumptions': asdict(scenario) if scenario else None,
            'inputs': {'profile': deepcopy(plan['profile']), 'debts': deepcopy(plan['debts'])}}


def calculate(user, db, expected_revision=None, effective_date=None, scenario=None):
    plan = planning.load(user, db)
    if expected_revision is not None:
        planning.check_revision(plan, expected_revision)
    on = effective_date or planning.today_for(plan)
    result = calculate_plan(plan, user['currency'], on, scenario)
    if scenario:
        return {'baseline': calculate_plan(plan, user['currency'], on), 'scenario': result}
    return result


def monthly_review(month, user, db):
    plan = planning.load(user, db)
    today = planning.today_for(plan)
    year, selected_month = map(int, month.split('-'))
    on = (today if month == today.strftime('%Y-%m') else
          date(year, selected_month, calendar.monthrange(year, selected_month)[1]))
    return calculate_plan(plan, user['currency'], on)


def public_snapshot(record, plan):
    return {k: deepcopy(v) for k, v in record.items() if k not in ('user_id', 'request_hash')} | {
        'outdated': record['result']['input_hash'] != input_hash(plan),
        'review_due': bool(record['result']['reviewed_at'] and
            (datetime.now(timezone.utc) - datetime.fromisoformat(record['result']['reviewed_at'])).days >= 30),
    }


def save_snapshot(user, db, *, expected_revision, effective_date, scenario, operation_id, name):
    if not name.strip() or len(name.strip()) > 80:
        planning.invalid('Name the snapshot using 1–80 characters.')
    fingerprint = digest({'revision': expected_revision, 'date': effective_date, 'scenario': asdict(scenario) if scenario else None, 'name': name.strip()})
    id = str(uuid5(NAMESPACE_URL, f"pocketwise:snapshot:{user['id']}:{operation_id}"))
    with db.atomic(user['id']) as tx:
        plan = planning.load(user, tx)
        previous = tx.get('calculation_snapshots', id=id, user_id=user['id'])
        if previous:
            if previous['request_hash'] != fingerprint:
                planning.conflict('This operation ID was already used for a different snapshot.')
            return public_snapshot(previous, plan)
        planning.check_revision(plan, expected_revision)
        result = calculate_plan(plan, user['currency'], effective_date, scenario)
        record = {'id': id, 'user_id': user['id'], 'name': name.strip(), 'created_at': planning.stamp(),
                  'request_hash': fingerprint, 'result': result}
        tx.put('calculation_snapshots', record)
        return public_snapshot(record, plan)


def snapshots(user, db, page=1, page_size=20):
    with db.atomic(user['id']) as tx:
        plan = planning.load(user, tx)
        items = sorted(tx.find('calculation_snapshots', user_id=user['id']),
                       key=lambda r: (r['created_at'], r['id']), reverse=True)
        return {'items': [public_snapshot(r, plan) for r in items[(page-1)*page_size:page*page_size]],
                'total': len(items), 'page': page, 'page_size': page_size}
