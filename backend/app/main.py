"""Composition root: wire API adapters, domain services and infrastructure."""
import os
import secrets
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from .api.routes import build_router
from .api.errors import install_error_handlers
from .domain.auth import AuthService
from .infrastructure.security import Argon2PasswordHasher, TokenService
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

    install_error_handlers(app)

    app.include_router(build_router(AuthService(TokenService(jwt_secret), Argon2PasswordHasher()), mode))
    return app


app = create_app()
