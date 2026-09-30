from datetime import date
from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from .schemas import Budget, Category, DemoRequest, Login, ParseRequest, Refresh, Register, Transaction, UpdateProfile
from ..domain import commands, finance
from ..domain.demo import demo as seed_demo
from ..infrastructure.rate_limit import AuthRateLimiter
from . import planning_schemas as ps
from ..domain import planning, planning_commands as pc


def build_router(auth, mode):
    router = APIRouter()
    bearer = HTTPBearer(auto_error=False)
    limiter = AuthRateLimiter()

    def repo(request: Request):
        return request.app.state.repo

    def auth_limit(request: Request):
        limiter.check(request.client.host if request.client else 'local')

    def current(credentials: HTTPAuthorizationCredentials | None = Depends(bearer), db=Depends(repo)):
        if not credentials:
            raise HTTPException(401, 'Please sign in to continue.')
        return auth.user_for_token(credentials.credentials, db)


    @router.get('/health')
    def health():
        return {'status': 'ok', 'storage': mode}

    @router.post('/auth/register', status_code=201, dependencies=[Depends(auth_limit)])
    def register(data: Register, db=Depends(repo)):
        return auth.register(data=commands.Register(**data.model_dump()), db=db)

    @router.post('/auth/login', dependencies=[Depends(auth_limit)])
    def login(data: Login, db=Depends(repo)):
        return auth.login(data=commands.Login(**data.model_dump()), db=db)

    @router.post('/auth/refresh', dependencies=[Depends(auth_limit)])
    def refresh(data: Refresh, db=Depends(repo)):
        return auth.refresh(data=commands.Refresh(**data.model_dump()), db=db)

    @router.post('/auth/logout')
    def logout(data: Refresh, db=Depends(repo)):
        return auth.logout(data=commands.Refresh(**data.model_dump()), db=db)

    @router.get('/auth/me')
    def me(user=Depends(current)):
        return auth.me(user=user)

    @router.put('/auth/me')
    def update_profile(data: UpdateProfile, user=Depends(current), db=Depends(repo)):
        return auth.update_profile(commands.UpdateProfile(**data.model_dump()), user, db)

    @router.get('/auth/me/export')
    def export_data(response: Response, user=Depends(current), db=Depends(repo)):
        response.headers['Cache-Control'] = 'no-store'
        response.headers['Content-Disposition'] = 'attachment; filename="pocketwise-data.json"'
        return auth.export_data(user, db)

    @router.delete('/auth/me', status_code=204)
    def delete_account(user=Depends(current), db=Depends(repo)):
        return auth.delete_account(user=user, db=db)

    @router.get('/categories')
    def list_categories(user=Depends(current), db=Depends(repo)):
        return finance.list_categories(user=user, db=db)

    @router.get('/financial-profile')
    def financial_profile(user=Depends(current), db=Depends(repo)):
        return planning.get_plan(user, db)

    @router.get('/planning')
    def planning_overview(start: date, end: date, user=Depends(current), db=Depends(repo)):
        return planning.overview(start, end, user, db)

    @router.put('/financial-profile')
    def save_financial_profile(data: ps.Profile, user=Depends(current), db=Depends(repo)):
        values = data.model_dump()
        values['income_sources'] = tuple(pc.IncomeSource(**s) for s in values['income_sources'])
        return planning.save_profile(pc.FinancialProfile(**values), user, db)

    @router.get('/debts')
    def debts(user=Depends(current), db=Depends(repo)):
        plan = planning.get_plan(user, db)
        return {'items': plan['debts'], 'revision': plan['revision']}

    @router.post('/debts', status_code=201)
    def add_debt(data: ps.Schedule, user=Depends(current), db=Depends(repo)):
        return planning.save_schedule('debts', pc.Schedule(**data.model_dump()), user, db)

    @router.put('/debts/{id}')
    def edit_debt(id: str, data: ps.Schedule, user=Depends(current), db=Depends(repo)):
        return planning.save_schedule('debts', pc.Schedule(**data.model_dump()), user, db, id)

    @router.delete('/debts/{id}')
    def delete_debt(id: str, expected_revision: int=Query(ge=0), user=Depends(current), db=Depends(repo)):
        return planning.delete_schedule('debts', id, expected_revision, user, db)

    @router.get('/commitments')
    def commitments(user=Depends(current), db=Depends(repo)):
        plan = planning.get_plan(user, db)
        return {'items': plan['commitments'], 'revision': plan['revision']}

    @router.post('/commitments', status_code=201)
    def add_commitment(data: ps.Schedule, user=Depends(current), db=Depends(repo)):
        return planning.save_schedule('commitments', pc.Schedule(**data.model_dump()), user, db)

    @router.put('/commitments/{id}')
    def edit_commitment(id: str, data: ps.Schedule, user=Depends(current), db=Depends(repo)):
        return planning.save_schedule('commitments', pc.Schedule(**data.model_dump()), user, db, id)

    @router.delete('/commitments/{id}')
    def delete_commitment(id: str, expected_revision: int=Query(ge=0), user=Depends(current), db=Depends(repo)):
        return planning.delete_schedule('commitments', id, expected_revision, user, db)

    @router.get('/commitment-occurrences')
    def occurrences(start: date, end: date, user=Depends(current), db=Depends(repo)):
        return planning.list_occurrences(start, end, user, db)

    @router.post('/commitment-occurrences/{id}/payments')
    def record_payment(id: str, data: ps.Payment, user=Depends(current), db=Depends(repo)):
        return planning.pay(id, pc.Payment(**data.model_dump()), user, db)

    @router.delete('/commitment-occurrences/{id}/payments/{transaction_id}')
    def unlink_payment(id: str, transaction_id: str, expected_revision: int=Query(ge=0), user=Depends(current), db=Depends(repo)):
        return planning.unlink(id, transaction_id, expected_revision, user, db)

    @router.post('/categories', status_code=201)
    def add_category(data: Category, user=Depends(current), db=Depends(repo)):
        return finance.add_category(data=commands.Category(**data.model_dump()), user=user, db=db)

    @router.put('/categories/{id}')
    def edit_category(id: str, data: Category, user=Depends(current), db=Depends(repo)):
        return finance.edit_category(id=id, data=commands.Category(**data.model_dump()), user=user, db=db)

    @router.delete('/categories/{id}', status_code=204)
    def delete_category(id: str, user=Depends(current), db=Depends(repo)):
        return finance.delete_category(id=id, user=user, db=db)

    @router.get('/transactions')
    def list_transactions(start: date | None=None, end: date | None=None, category_id: str | None=None, type: str | None=None, q: str='', min_amount: int | None=None, max_amount: int | None=None, page: int=Query(1, ge=1), page_size: int=Query(50, ge=1, le=100), user=Depends(current), db=Depends(repo)):
        return finance.list_transactions(start=start, end=end, category_id=category_id, type=type, q=q, min_amount=min_amount, max_amount=max_amount, page=page, page_size=page_size, user=user, db=db)

    @router.post('/transactions', status_code=201)
    def add_transaction(data: Transaction, user=Depends(current), db=Depends(repo)):
        return finance.add_transaction(data=commands.Transaction(**data.model_dump()), user=user, db=db)

    @router.put('/transactions/{id}')
    def edit_transaction(id: str, data: Transaction, user=Depends(current), db=Depends(repo)):
        return finance.edit_transaction(id=id, data=commands.Transaction(**data.model_dump()), user=user, db=db)

    @router.delete('/transactions/{id}', status_code=204)
    def delete_transaction(id: str, user=Depends(current), db=Depends(repo)):
        return finance.delete_transaction(id=id, user=user, db=db)

    @router.get('/budgets')
    def list_budgets(period: str=Query(pattern='^\\d{4}-(0[1-9]|1[0-2])$'), user=Depends(current), db=Depends(repo)):
        return finance.list_budgets(period=period, user=user, db=db)

    @router.post('/budgets', status_code=201)
    def set_budget(data: Budget, user=Depends(current), db=Depends(repo)):
        return finance.set_budget(data=commands.Budget(**data.model_dump()), user=user, db=db)

    @router.delete('/budgets/{id}', status_code=204)
    def delete_budget(id: str, user=Depends(current), db=Depends(repo)):
        return finance.delete_budget(id=id, user=user, db=db)

    @router.get('/reports/summary')
    def summary(month: str=Query(pattern='^\\d{4}-(0[1-9]|1[0-2])$'), user=Depends(current), db=Depends(repo)):
        return finance.summary(month=month, user=user, db=db)

    @router.post('/nlp/parse')
    def parse_entry(data: ParseRequest, user=Depends(current), db=Depends(repo)):
        return finance.parse_entry(data=commands.ParseRequest(**data.model_dump()), user=user, db=db)

    @router.post('/auth/demo', dependencies=[Depends(auth_limit)])
    def demo(data: DemoRequest, db=Depends(repo)):
        if mode != 'local':
            raise HTTPException(404, 'Demo is only available in local development.')
        return seed_demo(data.currency, db, auth)

    return router
