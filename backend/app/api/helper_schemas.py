from datetime import date
from pydantic import Field
from .planning_schemas import StrictInput, Currency


class Calculation(StrictInput):
    expected_revision: int | None = Field(default=None, ge=0, strict=True)
    effective_date: date | None = None


class DebtOverride(StrictInput):
    id: str = Field(min_length=1, max_length=100)
    monthly_payment: int = Field(ge=0, le=100_000_000_000, strict=True)


class Assumptions(StrictInput):
    currency: Currency
    gross_monthly: int | None = Field(default=None, ge=0, le=100_000_000_000, strict=True)
    net_monthly: int | None = Field(default=None, ge=0, le=100_000_000_000, strict=True)
    additional_debt_monthly: int = Field(default=0, ge=0, le=100_000_000_000, strict=True)
    debt_payments: list[DebtOverride] = Field(default_factory=list, max_length=100)
    notes: str = Field(default='', max_length=500)


class ScenarioRequest(Calculation):
    expected_revision: int = Field(ge=0, strict=True)
    assumptions: Assumptions


class Snapshot(StrictInput):
    expected_revision: int = Field(ge=0, strict=True)
    effective_date: date
    assumptions: Assumptions | None = None
    operation_id: str = Field(min_length=16, max_length=100, pattern=r'^[A-Za-z0-9_-]+$')
    name: str = Field(min_length=1, max_length=80)
