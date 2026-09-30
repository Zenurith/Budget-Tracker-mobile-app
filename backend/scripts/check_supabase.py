"""Read-only database preflight. Never prints connection strings or user data.

Run from the repository root: backend/.venv/bin/python backend/scripts/check_supabase.py
Reads backend/.env; does not change DATABASE_MODE or apply migrations.
"""
import json
import os
from pathlib import Path

import psycopg
from dotenv import dotenv_values


def main():
    env = dotenv_values(Path(__file__).resolve().parents[1] / '.env')
    url = os.getenv('SUPABASE_DB_URL') or env.get('SUPABASE_DB_URL')
    if not url:
        print('SUPABASE_DB_URL is missing. Configure the Session pooler URI in backend/.env.')
        return 2
    try:
        with psycopg.connect(url, connect_timeout=10, sslmode='require') as db:
            db.execute('SET TRANSACTION READ ONLY')
            exists = db.execute("SELECT to_regclass('pocketwise.documents') IS NOT NULL").fetchone()[0]
            result = {'connected': True, 'documents_table_exists': exists}
            if exists:
                result['row_level_security'] = db.execute(
                    "SELECT relrowsecurity FROM pg_class WHERE oid='pocketwise.documents'::regclass"
                ).fetchone()[0]
                result['indexes'] = [row[0] for row in db.execute(
                    "SELECT indexname FROM pg_indexes WHERE schemaname='pocketwise' AND tablename='documents' ORDER BY indexname"
                )]
                result['client_privileges'] = {
                    role: dict(zip(('schema_usage', 'select', 'insert', 'update', 'delete'),
                                   db.execute(
                                       "SELECT has_schema_privilege(%s, 'pocketwise', 'USAGE'), "
                                       "has_table_privilege(%s, 'pocketwise.documents', 'SELECT'), "
                                       "has_table_privilege(%s, 'pocketwise.documents', 'INSERT'), "
                                       "has_table_privilege(%s, 'pocketwise.documents', 'UPDATE'), "
                                       "has_table_privilege(%s, 'pocketwise.documents', 'DELETE')",
                                       (role,) * 5,
                                   ).fetchone()))
                    for role in ('anon', 'authenticated')
                }
            print(json.dumps(result, indent=2))
            return 0 if exists else 1
    except psycopg.Error as error:
        # Driver errors can contain connection details. Report only the class/code.
        detail = str(error).lower()
        reason = next((label for marker, label in (
            ('password authentication failed', 'password_rejected'),
            ('tenant or user not found', 'pooler_project_or_user_not_found'),
            ('could not translate host name', 'hostname_resolution_failed'),
            ('failed to resolve host', 'hostname_resolution_failed'),
            ('timeout', 'connection_timed_out'),
            ('connection refused', 'connection_refused'),
            ('invalid', 'invalid_connection_configuration'),
        ) if marker in detail), 'connection_failed')
        print(json.dumps({'connected': False, 'error_type': type(error).__name__,
                          'reason': reason, 'sqlstate': error.sqlstate}))
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
