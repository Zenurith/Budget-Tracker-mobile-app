from datetime import date
from typing import Literal
from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator


from ..domain.commands import Currency


class DemoRequest(BaseModel):
    currency: Currency


class Register(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    currency: Currency


class Login(BaseModel):
    email: EmailStr
    password: str = Field(max_length=128)


class Refresh(BaseModel):
    refresh_token: str


class UpdateProfile(BaseModel):
    model_config = ConfigDict(extra='forbid')
    name: str = Field(min_length=1, max_length=80)

    @field_validator('name')
    @classmethod
    def clean_name(cls, value):
        if not value.strip():
            raise ValueError('Name cannot be blank')
        return value.strip()


class Transaction(BaseModel):
    amount: int = Field(gt=0, le=100_000_000_000, strict=True)
    type: Literal['income', 'expense']
    category_id: str
    date: date
    note: str = Field(default='', max_length=500)
    payment_method: str = Field(default='Cash', max_length=40)
    source: Literal['manual', 'nlp'] = 'manual'


class Category(BaseModel):
    name: str = Field(min_length=1, max_length=40)
    type: Literal['income', 'expense'] = 'expense'
    icon: str = Field(default='category', max_length=40)
    color: str = Field(default='#4D8B70', pattern=r'^#[0-9A-Fa-f]{6}$')

    @field_validator('name')
    @classmethod
    def clean_name(cls, value):
        if not value.strip():
            raise ValueError('Name cannot be blank')
        return value.strip()


class Budget(BaseModel):
    category_id: str | None = None
    period: str = Field(pattern=r'^\d{4}-(0[1-9]|1[0-2])$')
    limit_amount: int = Field(gt=0, le=100_000_000_000, strict=True)
    alert_threshold: int = Field(default=80, ge=1, le=100)


class ParseRequest(BaseModel):
    text: str = Field(min_length=1, max_length=500)
    reference_date: date = Field(default_factory=date.today)
