from datetime import date as Date
from typing import Literal
from pydantic import Field
from .funding_schemas import Revision, ReviewedRevision


class Item(Revision):
    name: str = Field(min_length=1, max_length=80)
    target_cost: int = Field(gt=0, le=100_000_000_000, strict=True)
    priority: int = Field(default=0, ge=0, le=100, strict=True)
    target_date: Date | None = None
    notes: str = Field(default='', max_length=2000)
    reference_url: str | None = Field(default=None, max_length=2000)
    status: Literal['active', 'paused', 'archived'] = 'active'
    monthly_contribution: int = Field(default=0, ge=0, le=100_000_000_000, strict=True)
    next_contribution_date: Date | None = None


class Purchase(ReviewedRevision):
    operation_id: str = Field(min_length=16, max_length=100, pattern=r'^[A-Za-z0-9_-]+$')
    amount: int = Field(gt=0, le=100_000_000_000, strict=True)
    date: Date
    category_id: str = Field(min_length=1, max_length=100)
    confirmed: bool
    baseline_effect: Literal['subtract_from_prior_snapshot', 'already_reconciled']
    quote: str | None = Field(default=None, max_length=100)
    account_name: str | None = Field(default=None, max_length=80)
    transaction_id: str | None = Field(default=None, max_length=100)
    snapshot_token: str | None = Field(default=None, max_length=100)


class Adjustment(Revision):
    operation_id: str = Field(min_length=16, max_length=100, pattern=r'^[A-Za-z0-9_-]+$')
    confirmed: bool
    reason: str = Field(min_length=1, max_length=500)
    amount: int = Field(default=0, ge=0, le=100_000_000_000, strict=True)
    date: Date | None = None
    category_id: str | None = Field(default=None, max_length=100)
