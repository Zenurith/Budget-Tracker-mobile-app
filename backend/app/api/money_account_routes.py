from datetime import date
from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field, ConfigDict
from ..domain import money_accounts

class AccountCreate(BaseModel):
    model_config = ConfigDict(extra='forbid')
    operation_id: str = Field(min_length=16, max_length=100)
    name: str = Field(min_length=1, max_length=80)
    opening_date: date
    opening_amount: int = Field(ge=-100_000_000_000, le=100_000_000_000, strict=True)

class AccountUpdate(AccountCreate):
    account_id: str = Field(min_length=1, max_length=100)
    expected_revision: int = Field(ge=0, strict=True)
    archived: bool


class TransferCreate(BaseModel):
    model_config = ConfigDict(extra='forbid')
    operation_id: str = Field(min_length=16, max_length=100)
    from_account: str = Field(min_length=1, max_length=100)
    to_account: str = Field(min_length=1, max_length=100)
    date: date
    amount: int = Field(gt=0, le=100_000_000_000, strict=True)
    note: str = Field(default='', max_length=500)


class AccountReconcile(BaseModel):
    model_config = ConfigDict(extra='forbid')
    operation_id: str = Field(min_length=16, max_length=100)
    account_id: str = Field(min_length=1, max_length=100)
    actual: int = Field(ge=-100_000_000_000, le=100_000_000_000, strict=True)


def build_money_account_router(current, repo):
    router = APIRouter()
    @router.get('/money-accounts')
    def overview(user=Depends(current), db=Depends(repo)):
        return money_accounts.overview(user, db)
    @router.post('/money-accounts', status_code=201)
    def create(data: AccountCreate, user=Depends(current), db=Depends(repo)):
        return money_accounts.create(data.model_dump(), user, db)
    @router.post('/account-transfers', status_code=201)
    def transfer(data: TransferCreate, user=Depends(current), db=Depends(repo)):
        return money_accounts.transfer(data.model_dump(), user, db)
    @router.post('/money-accounts/reconcile', status_code=201)
    def reconcile(data: AccountReconcile, user=Depends(current), db=Depends(repo)):
        return money_accounts.reconcile(data.model_dump(), user, db)
    @router.post('/money-accounts/update')
    def update(data: AccountUpdate, user=Depends(current), db=Depends(repo)):
        return money_accounts.update(data.model_dump(), user, db)
    return router
