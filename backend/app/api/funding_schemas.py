from datetime import date, datetime
from typing import Literal
from pydantic import Field
from .planning_schemas import StrictInput, Currency


class Revision(StrictInput):
    expected_revision: int = Field(ge=0, strict=True)
    currency: Currency


class ReviewedRevision(Revision):
    expected_planning_revision: int = Field(ge=0, strict=True)


class Account(StrictInput):
    name: str = Field(min_length=1, max_length=80)
    amount: int = Field(ge=0, le=100_000_000_000, strict=True)


class Snapshot(ReviewedRevision):
    accounts: list[Account] = Field(min_length=1, max_length=30)
    as_of: datetime
    confirmed: bool


class Allowance(Account):
    schedule_ids: list[str] = Field(default_factory=list, max_length=100)


class Plan(ReviewedRevision):
    next_income_date: date | None
    buffer_amount: int = Field(ge=0, le=100_000_000_000, strict=True)
    monthly_forecast_surplus: int = Field(ge=-100_000_000_000, le=100_000_000_000, strict=True)
    essential_allowances: list[Allowance] = Field(max_length=100)
    confirmed: bool


class Goal(Revision):
    name: str = Field(min_length=1, max_length=80)
    kind: Literal['emergency', 'savings']
    target_amount: int = Field(ge=0, le=100_000_000_000, strict=True)
    included_in_cash: bool
    excluded_balance: int = Field(default=0, ge=0, le=100_000_000_000, strict=True)
    required_amount: int = Field(default=0, ge=0, le=100_000_000_000, strict=True)
    required_by: date | None = None


class Allocation(ReviewedRevision):
    operation_id: str = Field(min_length=16, max_length=100, pattern=r'^[A-Za-z0-9_-]+$')
    amount: int = Field(gt=0, le=100_000_000_000, strict=True)
    source_id: str | None = Field(default=None, max_length=100)
    target_id: str | None = Field(default=None, max_length=100)
