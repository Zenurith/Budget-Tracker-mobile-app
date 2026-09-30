"""Immutable use-case inputs, independent of HTTP request validation."""
from dataclasses import dataclass
from datetime import date
from typing import Literal

Currency = Literal['MYR', 'USD', 'SGD', 'EUR', 'GBP']


@dataclass(frozen=True, kw_only=True)
class Register:
    name: str
    email: str
    password: str
    currency: Currency


@dataclass(frozen=True, kw_only=True)
class Login:
    email: str
    password: str


@dataclass(frozen=True, kw_only=True)
class Refresh:
    refresh_token: str


@dataclass(frozen=True, kw_only=True)
class UpdateProfile:
    name: str


@dataclass(frozen=True, kw_only=True)
class Transaction:
    amount: int
    type: Literal['income', 'expense']
    category_id: str
    date: date
    note: str = ''
    payment_method: str = 'Cash'
    source: Literal['manual', 'nlp'] = 'manual'


@dataclass(frozen=True, kw_only=True)
class Category:
    name: str
    type: Literal['income', 'expense'] = 'expense'
    icon: str = 'category'
    color: str = '#4D8B70'


@dataclass(frozen=True, kw_only=True)
class Budget:
    period: str
    limit_amount: int
    category_id: str | None = None
    alert_threshold: int = 80


@dataclass(frozen=True, kw_only=True)
class ParseRequest:
    text: str
    reference_date: date
