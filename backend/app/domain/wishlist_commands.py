from dataclasses import dataclass
from datetime import date as Date


@dataclass(frozen=True, kw_only=True)
class Item:
    expected_revision: int
    currency: str
    name: str
    target_cost: int
    priority: int = 0
    target_date: Date | None = None
    notes: str = ''
    reference_url: str | None = None
    status: str = 'active'
    monthly_contribution: int = 0
    next_contribution_date: Date | None = None


@dataclass(frozen=True, kw_only=True)
class Purchase:
    expected_revision: int
    expected_planning_revision: int
    currency: str
    operation_id: str
    amount: int
    date: Date
    category_id: str
    confirmed: bool
    baseline_effect: str
    quote: str | None = None
    account_name: str | None = None
    transaction_id: str | None = None
    snapshot_token: str | None = None


@dataclass(frozen=True, kw_only=True)
class Adjustment:
    expected_revision: int
    currency: str
    operation_id: str
    confirmed: bool
    reason: str
    amount: int = 0
    date: Date | None = None
    category_id: str | None = None
