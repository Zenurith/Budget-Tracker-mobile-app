"""Immutable planning inputs, independent of HTTP and persistence."""
from dataclasses import dataclass
from datetime import date as Date


@dataclass(frozen=True, kw_only=True)
class IncomeSource:
    name: str
    currency: str
    gross: int | None
    net: int | None
    frequency: str
    start_date: Date
    end_date: Date | None = None
    basis: str = 'fixed_schedule'
    notes: str = ''
    id: str | None = None


@dataclass(frozen=True, kw_only=True)
class FinancialProfile:
    expected_revision: int
    currency: str
    timezone: str
    income_sources: tuple[IncomeSource, ...]
    debt_confirmation: str
    confirmed: bool
    dsr_target: str | None = None
    dti_target: str | None = None


@dataclass(frozen=True, kw_only=True)
class Schedule:
    expected_revision: int
    name: str
    currency: str
    amount: int | None
    frequency: str
    start_date: Date
    category_id: str
    end_date: Date | None = None
    status: str = 'active'
    second_day: int | None = None
    debt_type: str = 'other'
    outstanding_balance: int | None = None
    extra_payment: int = 0
    payment_basis: str = 'scheduled'
    notes: str = ''


@dataclass(frozen=True, kw_only=True)
class Payment:
    expected_revision: int
    operation_id: str
    transaction_id: str | None = None
    amount: int | None = None
    date: Date | None = None
    note: str = ''

