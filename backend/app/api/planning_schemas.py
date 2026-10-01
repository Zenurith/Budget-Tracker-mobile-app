from datetime import date as Date
from typing import Literal
from pydantic import BaseModel, ConfigDict, Field, field_validator

Currency = Literal['EUR', 'GBP', 'MYR', 'SGD', 'USD']
Frequency = Literal['daily', 'weekly', 'fortnightly', 'twice_monthly', 'monthly', 'quarterly', 'annually']


class StrictInput(BaseModel):
    model_config = ConfigDict(extra='forbid')


class Income(StrictInput):
    id: str | None = Field(default=None, max_length=80)
    name: str = Field(min_length=1, max_length=80)
    currency: Currency
    gross: int | None = Field(default=None, ge=0, le=100_000_000_000, strict=True)
    net: int | None = Field(default=None, ge=0, le=100_000_000_000, strict=True)
    frequency: Frequency
    start_date: Date
    end_date: Date | None = None
    basis: Literal['fixed_schedule', 'monthly_estimate'] = 'fixed_schedule'
    notes: str = Field(default='', max_length=500)


class Profile(StrictInput):
    expected_revision: int = Field(ge=0, strict=True)
    currency: Currency
    timezone: str = Field(min_length=1, max_length=80)
    income_sources: list[Income] = Field(max_length=30)
    debt_confirmation: Literal['unknown', 'complete', 'none']
    confirmed: bool
    dsr_target: str | None = Field(default=None, pattern=r'^\d{1,4}(\.\d{1,2})?$')
    dti_target: str | None = Field(default=None, pattern=r'^\d{1,4}(\.\d{1,2})?$')


class Schedule(StrictInput):
    expected_revision: int = Field(ge=0, strict=True)
    name: str = Field(min_length=1, max_length=80)
    currency: Currency
    amount: int | None = Field(default=None, ge=0, le=100_000_000_000, strict=True)
    frequency: Frequency
    start_date: Date
    category_id: str = Field(min_length=1, max_length=100)
    end_date: Date | None = None
    status: Literal['active', 'closed'] = 'active'
    second_day: int | None = Field(default=None, ge=1, le=31, strict=True)
    debt_type: Literal['mortgage', 'vehicle', 'personal', 'education', 'credit_card', 'bnpl', 'other'] = 'other'
    outstanding_balance: int | None = Field(default=None, ge=0, le=100_000_000_000, strict=True)
    extra_payment: int = Field(default=0, ge=0, le=100_000_000_000, strict=True)
    payment_basis: Literal['scheduled', 'statement'] = 'scheduled'
    notes: str = Field(default='', max_length=500)


class Payment(StrictInput):
    expected_revision: int = Field(ge=0, strict=True)
    operation_id: str = Field(min_length=16, max_length=100, pattern=r'^[A-Za-z0-9_-]+$')
    transaction_id: str | None = Field(default=None, max_length=100)
    amount: int | None = Field(default=None, gt=0, le=100_000_000_000, strict=True)
    date: Date | None = None
    note: str = Field(default='', max_length=500)
