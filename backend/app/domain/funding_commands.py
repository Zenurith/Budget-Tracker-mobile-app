from dataclasses import dataclass
from datetime import date, datetime


@dataclass(frozen=True, kw_only=True)
class CashAccount:
    name: str
    amount: int


@dataclass(frozen=True, kw_only=True)
class CashSnapshot:
    expected_revision: int
    expected_planning_revision: int
    currency: str
    accounts: tuple[CashAccount, ...]
    as_of: datetime
    confirmed: bool


@dataclass(frozen=True, kw_only=True)
class Allowance:
    name: str
    amount: int
    schedule_ids: tuple[str, ...] = ()


@dataclass(frozen=True, kw_only=True)
class FundingPlan:
    expected_revision: int
    expected_planning_revision: int
    currency: str
    next_income_date: date | None
    buffer_amount: int
    monthly_forecast_surplus: int
    essential_allowances: tuple[Allowance, ...]
    confirmed: bool


@dataclass(frozen=True, kw_only=True)
class Goal:
    expected_revision: int
    currency: str
    name: str
    kind: str
    target_amount: int
    included_in_cash: bool
    excluded_balance: int = 0
    required_amount: int = 0
    required_by: date | None = None


@dataclass(frozen=True, kw_only=True)
class Allocation:
    expected_revision: int
    expected_planning_revision: int
    currency: str
    operation_id: str
    amount: int
    source_id: str | None = None
    target_id: str | None = None
