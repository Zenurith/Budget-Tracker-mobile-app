"""Application composition and transport error mapping."""
import os
import secrets
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException
from .api.routes import build_router
from .domain.auth import AuthService
from .domain.errors import DomainError
from .infrastructure.security import TokenService
from .repositories.documents import LocalRepository, MongoRepository


def create_app(repository=None, secret=None):
    mode = os.getenv('DATABASE_MODE', 'local')
    jwt_secret = secret or os.getenv('JWT_SECRET')
    if mode == 'mongo' and (not jwt_secret or len(jwt_secret) < 32):
        raise RuntimeError('Set JWT_SECRET to at least 32 random characters for MongoDB mode.')
    jwt_secret = jwt_secret or secrets.token_urlsafe(48)

    @asynccontextmanager
    async def lifespan(app):
        app.state.repo = repository or (MongoRepository(os.environ['MONGODB_URI'], os.getenv('MONGODB_DATABASE', 'pocketwise')) if mode == 'mongo' else LocalRepository(os.getenv('LOCAL_DATABASE_PATH', 'data/pocketwise.sqlite')))
        yield
        if repository is None:
            app.state.repo.close()

    app = FastAPI(title='Pocketwise API', version='0.2.0', lifespan=lifespan)
    app.add_middleware(CORSMiddleware, allow_origins=os.getenv('CORS_ORIGINS', 'http://localhost:5173,http://127.0.0.1:5173').split(','), allow_methods=['GET','POST','PUT','DELETE'], allow_headers=['Authorization','Content-Type'])

    @app.exception_handler(HTTPException)
    async def http_error(request, exc):
        return JSONResponse({'error': {'message': str(exc.detail)}}, status_code=exc.status_code, headers=exc.headers)

    @app.exception_handler(DomainError)
    async def domain_error(request, exc):
        return JSONResponse({'error': {'message': exc.detail}}, status_code=exc.status_code)

    @app.exception_handler(RequestValidationError)
    async def validation_error(request, exc):
        messages = [f"{'.'.join(str(p) for p in e['loc'][1:])}: {e['msg']}" for e in exc.errors()]
        return JSONResponse({'error': {'message': '; '.join(messages)}}, status_code=422)

    app.include_router(build_router(AuthService(TokenService(jwt_secret)), mode))
    return app


app = create_app()
