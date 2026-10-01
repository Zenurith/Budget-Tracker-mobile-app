from fastapi import APIRouter, Depends, Query
from . import funding_schemas as fs
from ..domain import funding, funding_commands as fc


def build_funding_router(current, repo):
    router = APIRouter()

    @router.get('/funding/availability')
    @router.get('/funding/snapshot')
    @router.get('/funding/plan')
    @router.get('/goals')
    def availability(user=Depends(current), db=Depends(repo)):
        return funding.availability(user, db)

    @router.put('/funding/snapshot')
    def snapshot(data: fs.Snapshot, user=Depends(current), db=Depends(repo)):
        values = data.model_dump()
        values['accounts'] = tuple(fc.CashAccount(**a) for a in values['accounts'])
        return funding.save_snapshot(fc.CashSnapshot(**values), user, db)

    @router.put('/funding/plan')
    def plan(data: fs.Plan, user=Depends(current), db=Depends(repo)):
        values = data.model_dump()
        values['essential_allowances'] = tuple(fc.Allowance(**dict(a, schedule_ids=tuple(a['schedule_ids']))) for a in values['essential_allowances'])
        return funding.save_plan(fc.FundingPlan(**values), user, db)

    @router.post('/goals', status_code=201)
    def add_goal(data: fs.Goal, user=Depends(current), db=Depends(repo)):
        return funding.save_goal(fc.Goal(**data.model_dump()), user, db)

    @router.put('/goals/{id}')
    def edit_goal(id: str, data: fs.Goal, user=Depends(current), db=Depends(repo)):
        return funding.save_goal(fc.Goal(**data.model_dump()), user, db, id)

    @router.delete('/goals/{id}')
    def delete_goal(id: str, expected_revision: int=Query(ge=0), user=Depends(current), db=Depends(repo)):
        return funding.delete_goal(id, expected_revision, user, db)

    @router.post('/funding/allocations')
    def allocate(data: fs.Allocation, user=Depends(current), db=Depends(repo)):
        return funding.allocate('allocate', fc.Allocation(**data.model_dump()), user, db)

    @router.post('/funding/releases')
    def release(data: fs.Allocation, user=Depends(current), db=Depends(repo)):
        return funding.allocate('release', fc.Allocation(**data.model_dump()), user, db)

    @router.post('/funding/reallocations')
    def reallocate(data: fs.Allocation, user=Depends(current), db=Depends(repo)):
        return funding.allocate('reallocate', fc.Allocation(**data.model_dump()), user, db)

    @router.get('/funding/events')
    def events(page: int=Query(1, ge=1), page_size: int=Query(20, ge=1, le=100), user=Depends(current), db=Depends(repo)):
        return funding.events(user, db, page, page_size)

    return router
