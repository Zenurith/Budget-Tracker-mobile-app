from datetime import date
from typing import Literal
from pydantic import BaseModel, ConfigDict, Field
class ForecastEvent(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)
    name: str = Field(min_length=1, max_length=80)
    date: date
    kind: Literal['income', 'expense']
    amount: int = Field(gt=0, le=100_000_000_000, strict=True)


class CashForecast(BaseModel):
    model_config = ConfigDict(extra='forbid')
    daily_spending: int = Field(ge=0, le=100_000_000_000, strict=True)
    buffer: int = Field(ge=0, le=100_000_000_000, strict=True)
    income_date: date | None = None
    income_amount: int | None = Field(default=None, gt=0, le=100_000_000_000, strict=True)
    extra_expense_date: date | None = None
    extra_expense_amount: int | None = Field(default=None, gt=0, le=100_000_000_000, strict=True)
    events: list[ForecastEvent] = Field(default_factory=list, max_length=30)
