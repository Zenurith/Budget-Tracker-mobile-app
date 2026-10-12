from datetime import date
from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, ConfigDict, Field
from ..domain import balances, csv_import, record_history
from ..domain.commands import Currency


class StrictInput(BaseModel):
    model_config = ConfigDict(extra='forbid')


class OpeningAccount(StrictInput):
    name: str = Field(min_length=1, max_length=80)
    amount: int = Field(ge=-100_000_000_000, le=100_000_000_000, strict=True)


class Opening(StrictInput):
    operation_id: str = Field(min_length=16, max_length=100)
    expected_revision: int = Field(ge=0)
    currency: Currency
    as_of: date
    accounts: list[OpeningAccount] = Field(min_length=1, max_length=30)
    confirmed: bool


class CSVPreview(StrictInput):
    contents: str = Field(min_length=1, max_length=1_000_000)


class CSVCommit(CSVPreview):
    operation_id: str = Field(min_length=16, max_length=100)
    rows: list[int] = Field(min_length=1, max_length=1000)
    allow_duplicates: list[int] = Field(default_factory=list, max_length=1000)


def build_record_router(current, repo):
    router = APIRouter()

    @router.get('/balances')
    def balance_history(page: int = Query(1, ge=1), user=Depends(current), db=Depends(repo)):
        return balances.overview(user, db, page)

    @router.put('/balances/opening')
    def opening(data: Opening, user=Depends(current), db=Depends(repo)):
        return balances.save(data.model_dump(), user, db)

    @router.post('/imports/csv/preview')
    def preview(data: CSVPreview, user=Depends(current), db=Depends(repo)):
        return csv_import.parse(data.contents, user, db)

    @router.post('/imports/csv/commit')
    def commit(data: CSVCommit, user=Depends(current), db=Depends(repo)):
        return csv_import.commit(data.model_dump(), user, db)

    @router.get('/transaction-history')
    def history(page: int = Query(1, ge=1), user=Depends(current), db=Depends(repo)):
        return record_history.history(user, db, page)

    @router.post('/transaction-history/{id}/undo')
    def undo(id: str, user=Depends(current), db=Depends(repo)):
        return record_history.undo(id, user, db)

    return router
