from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, timezone
from uuid import uuid4
import pytest
from app.domain import funding, planning, wishlist
from app.domain.funding_commands import CashSnapshot, CashAccount, FundingPlan, Allocation
from app.domain.planning_commands import FinancialProfile, IncomeSource
from app.domain.wishlist_commands import Item, Purchase, Adjustment
from app.domain.errors import DomainError, ErrorKind
from app.repositories.documents import LocalRepository


def exercise_atomicity(first, second, monkeypatch):
    owner = str(uuid4())
    user = dict(id=owner, email=owner+'@example.com', currency='EUR')
    def tokens():
        s = wishlist.read(user, first)
        return dict(expected_revision=s['revision'], expected_planning_revision=s['planning_revision'], currency='EUR')
    def request(id, amount):
        s = wishlist.read(user, first)
        item = next(i for i in s['wishlist'] if i['id'] == id)
        return Purchase(**tokens(), operation_id=str(uuid4()), amount=amount, date=date.fromisoformat(s['as_of']),
                        category_id='shopping', confirmed=True, baseline_effect='subtract_from_prior_snapshot',
                        account_name='Cash', quote=item['quote'])
    try:
        first.put('users', user)
        planning.save_profile(FinancialProfile(expected_revision=0, currency='EUR', timezone='UTC',
            income_sources=(IncomeSource(name='Salary', currency='EUR', gross=600000, net=500000, frequency='monthly', start_date=date(2020, 1, 1)),),
            debt_confirmation='none', confirmed=True), user, first)
        funding.save_snapshot(CashSnapshot(**tokens(), accounts=(CashAccount(name='Cash', amount=70000),), as_of=datetime.now(timezone.utc), confirmed=True), user, first)
        funding.save_plan(FundingPlan(**tokens(), next_income_date=None, buffer_amount=0, monthly_forecast_surplus=20000, essential_allowances=(), confirmed=True), user, first)
        ids = []
        for name in ('Camera', 'Bicycle'):
            s = wishlist.save(Item(expected_revision=tokens()['expected_revision'], currency='EUR', name=name, target_cost=50000), user, first)
            ids.append(next(i['id'] for i in s['wishlist'] if i['name'] == name))
        expected = tokens()
        def allocate(pair):
            repo, id = pair
            try:
                return funding.allocate('allocate', Allocation(**expected, operation_id=str(uuid4()), amount=50000, target_id=id), user, repo)
            except DomainError as e:
                assert e.kind is ErrorKind.CONFLICT
                return None
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(allocate, [(first, ids[0]), (second, ids[1])]))
        assert sum(r is not None for r in results) == 1
        winning = ids[0] if results[0] else ids[1]
        losing = ids[1] if results[0] else ids[0]
        args = request(winning, 50000)
        before = wishlist.read(user, second)
        original = type(first).put
        def fail(self, collection, doc):
            result = original(self, collection, doc)
            if collection == 'funding':
                raise RuntimeError('simulated failure after all purchase writes')
            return result
        with monkeypatch.context() as patch:
            patch.setattr(type(first), 'put', fail)
            with pytest.raises(RuntimeError):
                wishlist.purchase(winning, args, user, first)
        assert wishlist.read(user, second) == before
        assert second.find('transactions', user_id=owner) == []
        assert funding.events(user, second)['total'] == 1
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda repo: wishlist.purchase(winning, args, user, repo), (first, second)))
        assert results[0] == results[1]
        assert len(second.find('transactions', user_id=owner)) == 1
        after = wishlist.read(user, second)
        assert after['liquid_total'] == 20000 and after['wishlist_reserved'] == 0 and after['usable']
        purchase_id = results[0]['purchase_id']
        # Refund and correction failures also roll back the linked transactions and cash marker.
        for kind in ('refund', 'reverse'):
            kwargs = dict(amount=100, date=date.today(), category_id='other-income') if kind == 'refund' else {}
            adjustment = Adjustment(expected_revision=after['revision'], currency='EUR', operation_id=str(uuid4()), confirmed=True, reason='Test correction', **kwargs)
            with monkeypatch.context() as patch:
                patch.setattr(type(first), 'put', fail)
                with pytest.raises(RuntimeError):
                    wishlist.adjust(purchase_id, kind, adjustment, user, first)
            assert wishlist.read(user, second) == after
            assert len(second.find('transactions', user_id=owner)) == 1
        funding.allocate('allocate', Allocation(**tokens(), operation_id=str(uuid4()), amount=10000, target_id=losing), user, first)
        args1, args2 = request(losing, 10000), request(losing, 10000)
        def competing(pair):
            repo, args = pair
            try:
                return wishlist.purchase(losing, args, user, repo)
            except DomainError as e:
                assert e.kind is ErrorKind.CONFLICT
                return None
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(competing, [(first, args1), (second, args2)]))
        assert sum(r is not None for r in results) == 1
        assert len(second.find('transactions', user_id=owner)) == 2
        assert wishlist.read(user, second)['liquid_total'] == 10000
    finally:
        for collection in ('transactions', 'planning', 'funding', 'funding_events'):
            first.delete(collection, user_id=owner)
        first.delete('users', id=owner)


def test_local_wishlist_concurrency_and_rollback(monkeypatch):
    repo = LocalRepository(':memory:')
    try:
        exercise_atomicity(repo, repo, monkeypatch)
    finally:
        repo.close()
