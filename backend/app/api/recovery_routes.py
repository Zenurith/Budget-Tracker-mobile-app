import logging
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Response
from pydantic import BaseModel, EmailStr, Field
from ..domain import recovery


class RequestReset(BaseModel):
    email: EmailStr


class ResetPassword(BaseModel):
    token: str = Field(min_length=32, max_length=100)
    password: str = Field(min_length=8, max_length=128)


def build_recovery_router(auth, mailer, repo, auth_limit):
    router = APIRouter()

    def deliver(email, db):
        try:
            recovery.request(email, db, mailer)
        except Exception:
            # SMTP/database errors can contain credentials or addresses. Log no details.
            logging.getLogger(__name__).error('Password recovery delivery failed.')

    @router.post('/auth/password/request', status_code=202, dependencies=[Depends(auth_limit)])
    def request_reset(data: RequestReset, background: BackgroundTasks, response: Response, db=Depends(repo)):
        response.headers['Cache-Control'] = 'no-store'
        if not mailer.configured:
            raise HTTPException(503, 'Password recovery email is not configured yet.')
        # Account lookup and delivery run after the same response for all addresses.
        background.add_task(deliver, str(data.email).lower(), db)
        return {'message': 'If an account exists for that email, a reset code will be sent. Check your inbox and spam folder.'}

    @router.post('/auth/password/reset', dependencies=[Depends(auth_limit)])
    def reset_password(data: ResetPassword, response: Response, db=Depends(repo)):
        response.headers['Cache-Control'] = 'no-store'
        return recovery.reset(data.token, data.password, db, auth.passwords)

    return router
