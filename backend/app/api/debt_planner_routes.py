from datetime import datetime, timezone
from hashlib import sha256
from uuid import UUID
from fastapi import APIRouter, Depends
from pydantic import BaseModel, ConfigDict, Field
from ..domain import planning
from ..domain.errors import DomainError, ErrorKind


class Debt(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)
    name: str = Field(min_length=1, max_length=80)
    balance: int = Field(gt=0, le=100_000_000_000, strict=True)
    rate: int = Field(ge=0, le=10000, strict=True)
    minimum: int = Field(gt=0, le=100_000_000_000, strict=True)


class Scenario(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)
    operation_id: UUID
    name: str = Field(min_length=1, max_length=80)
    currency: str
    first_month: str = Field(pattern=r'^(19\d{2}|[2-8]\d{3}|9[0-3]\d{2}|9400)-(0[1-9]|1[0-2])$')
    extra: int = Field(ge=0, le=100_000_000_000, strict=True)
    debts: list[Debt] = Field(min_length=1, max_length=20)


def build_debt_planner_router(current, repo):
    router = APIRouter()

    @router.get('/debt-planner')
    def load(user=Depends(current), db=Depends(repo)):
        with db.atomic(user['id']) as tx:
            plan = planning.load(user, tx)
            today = planning.today_for(plan).isoformat()
            debts = [dict(name=d['name'], balance=d.get('outstanding_balance'), rate=None,
                          minimum=d.get('amount') if d['frequency'] == 'monthly' else None,
                          frequency=d['frequency']) for d in plan['debts'].values()
                     if d['status'] == 'active' and (not d.get('end_date') or d['end_date'] >= today)]
            return {'currency': user['currency'], 'as_of': today, 'debts': debts,
                    'scenarios': sorted(tx.find('debt_scenarios', user_id=user['id']),
                                        key=lambda s: s['created_at'], reverse=True)}

    @router.post('/debt-scenarios', status_code=201)
    def save(data: Scenario, user=Depends(current), db=Depends(repo)):
        if data.currency != user['currency']:
            raise DomainError(ErrorKind.INVALID_INPUT, 'Use your account currency.')
        payload = data.model_dump(mode='json', exclude={'operation_id'})
        key = sha256(f"{user['id']}:{data.operation_id}".encode()).hexdigest()
        with db.atomic(user['id']) as tx:
            planning.load(user, tx)  # Refuse writes after account deletion.
            old = tx.get('debt_scenarios', id=key, user_id=user['id'])
            if old:
                if any(old[k] != v for k, v in payload.items()):
                    raise DomainError(ErrorKind.CONFLICT, 'This save request was already used for another scenario.')
                return old
            if len(tx.find('debt_scenarios', user_id=user['id'])) >= 30:
                raise DomainError(ErrorKind.CONFLICT, 'Delete an old scenario before saving more than 30.')
            record = dict(payload, id=key, user_id=user['id'], created_at=datetime.now(timezone.utc).isoformat())
            tx.put('debt_scenarios', record)
            return record

    @router.delete('/debt-scenarios/{id}', status_code=204)
    def delete(id: str, user=Depends(current), db=Depends(repo)):
        with db.atomic(user['id']) as tx:
            tx.delete('debt_scenarios', id=id, user_id=user['id'])

    return router
