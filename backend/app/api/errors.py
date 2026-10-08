"""Translate application and request failures into the public error envelope."""
from fastapi import FastAPI
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException
from ..domain.errors import DomainError, ErrorKind
from ..infrastructure.document_encryption import EncryptionError


def install_error_handlers(app: FastAPI):
    @app.exception_handler(EncryptionError)
    async def encryption_error(request, exc):
        return JSONResponse({'error': {'message': 'Stored data is temporarily unavailable.'}}, status_code=503)

    @app.exception_handler(HTTPException)
    async def http_error(request, exc):
        return JSONResponse({'error': {'message': str(exc.detail)}}, status_code=exc.status_code, headers=exc.headers)

    @app.exception_handler(DomainError)
    async def domain_error(request, exc):
        return JSONResponse({'error': {'message': exc.detail}}, status_code={
            ErrorKind.UNAUTHORIZED: 401, ErrorKind.NOT_FOUND: 404,
            ErrorKind.CONFLICT: 409, ErrorKind.INVALID_INPUT: 422,
            ErrorKind.RATE_LIMITED: 429, ErrorKind.UNAVAILABLE: 503,
        }[exc.kind])

    @app.exception_handler(RequestValidationError)
    async def validation_error(request, exc):
        messages = [f"{'.'.join(str(p) for p in e['loc'][1:])}: {e['msg']}" for e in exc.errors()]
        return JSONResponse({'error': {'message': '; '.join(messages)}}, status_code=422)
