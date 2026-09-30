from unittest.mock import MagicMock

import pytest
from psycopg.errors import UniqueViolation

from app.domain.ports import DuplicateRecordError
from app.repositories.documents import LocalRepository
from app.repositories.supabase import SupabaseRepository


def test_sqlite_duplicate_is_translated_and_rolled_back():
    repo = LocalRepository(':memory:')
    try:
        first = {'id': 'first', 'email': 'alex@example.com'}
        repo.put('users', first)
        with pytest.raises(DuplicateRecordError):
            repo.put('users', {'id': 'second', 'email': first['email']})
        assert repo.find('users') == [first]
        repo.put('users', {'id': 'second', 'email': 'other@example.com'})
        assert len(repo.find('users')) == 2
    finally:
        repo.close()


def test_supabase_duplicate_is_translated_without_masking_other_errors():
    # Driver boundary test; the live database contract is tested separately.
    repo = SupabaseRepository.__new__(SupabaseRepository)
    repo.pool = MagicMock()
    db = repo.pool.connection.return_value.__enter__.return_value
    db.execute.side_effect = UniqueViolation('duplicate')
    with pytest.raises(DuplicateRecordError):
        repo.put('users', {'id': 'first'})
    db.execute.side_effect = RuntimeError('unavailable')
    with pytest.raises(RuntimeError, match='unavailable'):
        repo.put('users', {'id': 'first'})


def test_unknown_database_mode_is_rejected(monkeypatch):
    from app.main import create_app
    monkeypatch.setenv('DATABASE_MODE', 'typo')
    with pytest.raises(RuntimeError, match='DATABASE_MODE'):
        create_app()


def test_supabase_requires_stable_secret(monkeypatch):
    from app.main import create_app
    monkeypatch.setenv('DATABASE_MODE', 'supabase')
    monkeypatch.delenv('JWT_SECRET', raising=False)
    with pytest.raises(RuntimeError, match='JWT_SECRET'):
        create_app()


def test_supabase_requires_connection_string(monkeypatch):
    from app.main import create_app
    from fastapi.testclient import TestClient
    monkeypatch.setenv('DATABASE_MODE', 'supabase')
    monkeypatch.delenv('SUPABASE_DB_URL', raising=False)
    with pytest.raises(RuntimeError, match='SUPABASE_DB_URL'):
        with TestClient(create_app(secret='x' * 32)):
            pass
