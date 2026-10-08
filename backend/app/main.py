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
from .repositories.documents import LocalRepository
from .repositories.supabase import SupabaseRepository
from .repositories.encrypted import EncryptedRepository
from .infrastructure.document_encryption import cipher_from_environment


def create_app(repository=None, secret=None):
    mode = os.getenv('DATABASE_MODE', 'local')
    if mode not in ('local', 'supabase'):
        raise RuntimeError('DATABASE_MODE must be local or supabase.')
    jwt_secret = secret or os.getenv('JWT_SECRET')
    if mode == 'supabase' and (not jwt_secret or len(jwt_secret) < 32):
        raise RuntimeError('Set JWT_SECRET to at least 32 random characters for Supabase mode.')
    jwt_secret = jwt_secret or secrets.token_urlsafe(48)

    @asynccontextmanager
    async def lifespan(app):
        cipher = None
        if repository is not None:
            app.state.repo = repository
        elif mode == 'supabase':
            url = os.getenv('SUPABASE_DB_URL')
            if not url:
                raise RuntimeError('Set SUPABASE_DB_URL to your Supabase Postgres connection string.')
            cipher = cipher_from_environment(required=True)
            app.state.repo = SupabaseRepository(url)
        else:
            cipher = cipher_from_environment(required=True)
            app.state.repo = LocalRepository(os.getenv('LOCAL_DATABASE_PATH', 'data/pocketwise.sqlite'))
        if cipher is not None:
            app.state.repo = EncryptedRepository(app.state.repo, cipher)
        try:
            yield
        finally:
            if repository is None:
                app.state.repo.close()

    app = FastAPI(title='Pocketwise API', version='0.2.0', lifespan=lifespan)
    app.add_middleware(CORSMiddleware, allow_origins=os.getenv('CORS_ORIGINS', 'http://localhost:5173,http://127.0.0.1:5173').split(','), allow_methods=['GET','POST','PUT','DELETE'], allow_headers=['Authorization','Content-Type'])

    install_error_handlers(app)

    app.include_router(build_router(AuthService(TokenService(jwt_secret), Argon2PasswordHasher()), mode))
    return app


app = create_app()
