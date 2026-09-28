from datetime import date
from fastapi import APIRouter, Depends, HTTPException, Query, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from ..models import Budget, Category, Login, ParseRequest, Refresh, Register, Transaction
from ..domain import finance
from ..domain.demo import demo as seed_demo
from ..infrastructure.rate_limit import AuthRateLimiter


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
        return auth.register(data=data, db=db)

    @router.post('/auth/login', dependencies=[Depends(auth_limit)])
    def login(data: Login, db=Depends(repo)):
        return auth.login(data=data, db=db)

    @router.post('/auth/refresh', dependencies=[Depends(auth_limit)])
    def refresh(data: Refresh, db=Depends(repo)):
        return auth.refresh(data=data, db=db)

    @router.post('/auth/logout')
    def logout(data: Refresh, db=Depends(repo)):
        return auth.logout(data=data, db=db)

    @router.get('/auth/me')
    def me(user=Depends(current)):
        return auth.me(user=user)

    @router.delete('/auth/me', status_code=204)
    def delete_account(user=Depends(current), db=Depends(repo)):
        return auth.delete_account(user=user, db=db)

    @router.get('/categories')
    def list_categories(user=Depends(current), db=Depends(repo)):
        return finance.list_categories(user=user, db=db)

    @router.post('/categories', status_code=201)
    def add_category(data: Category, user=Depends(current), db=Depends(repo)):
        return finance.add_category(data=data, user=user, db=db)

    @router.put('/categories/{id}')
    def edit_category(id: str, data: Category, user=Depends(current), db=Depends(repo)):
        return finance.edit_category(id=id, data=data, user=user, db=db)

    @router.delete('/categories/{id}', status_code=204)
    def delete_category(id: str, user=Depends(current), db=Depends(repo)):
        return finance.delete_category(id=id, user=user, db=db)

    @router.get('/transactions')
    def list_transactions(start: date | None=None, end: date | None=None, category_id: str | None=None, type: str | None=None, q: str='', min_amount: int | None=None, max_amount: int | None=None, page: int=Query(1, ge=1), page_size: int=Query(50, ge=1, le=100), user=Depends(current), db=Depends(repo)):
        return finance.list_transactions(start=start, end=end, category_id=category_id, type=type, q=q, min_amount=min_amount, max_amount=max_amount, page=page, page_size=page_size, user=user, db=db)

    @router.post('/transactions', status_code=201)
    def add_transaction(data: Transaction, user=Depends(current), db=Depends(repo)):
        return finance.add_transaction(data=data, user=user, db=db)

    @router.put('/transactions/{id}')
    def edit_transaction(id: str, data: Transaction, user=Depends(current), db=Depends(repo)):
        return finance.edit_transaction(id=id, data=data, user=user, db=db)

    @router.delete('/transactions/{id}', status_code=204)
    def delete_transaction(id: str, user=Depends(current), db=Depends(repo)):
        return finance.delete_transaction(id=id, user=user, db=db)

    @router.get('/budgets')
    def list_budgets(period: str=Query(pattern='^\\d{4}-(0[1-9]|1[0-2])$'), user=Depends(current), db=Depends(repo)):
        return finance.list_budgets(period=period, user=user, db=db)

    @router.post('/budgets', status_code=201)
    def set_budget(data: Budget, user=Depends(current), db=Depends(repo)):
        return finance.set_budget(data=data, user=user, db=db)

    @router.delete('/budgets/{id}', status_code=204)
    def delete_budget(id: str, user=Depends(current), db=Depends(repo)):
        return finance.delete_budget(id=id, user=user, db=db)

    @router.get('/reports/summary')
    def summary(month: str=Query(pattern='^\\d{4}-(0[1-9]|1[0-2])$'), user=Depends(current), db=Depends(repo)):
        return finance.summary(month=month, user=user, db=db)

    @router.post('/nlp/parse')
    def parse_entry(data: ParseRequest, user=Depends(current), db=Depends(repo)):
        return finance.parse_entry(data=data, user=user, db=db)

    @router.post('/auth/demo', dependencies=[Depends(auth_limit)])
    def demo(db=Depends(repo)):
        if mode != 'local':
            raise HTTPException(404, 'Demo is only available in local development.')
        return seed_demo(db, auth)

    return router
