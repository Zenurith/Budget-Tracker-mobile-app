"""Server-only Supabase Postgres adapter for the existing document contract."""
from psycopg.errors import UniqueViolation
from psycopg.types.json import Jsonb
from psycopg_pool import ConnectionPool
from contextlib import contextmanager, nullcontext

from ..domain.ports import DuplicateRecordError


class SupabaseRepository:
    def __init__(self, url):
        self.pool = ConnectionPool(
            url, min_size=1, max_size=5, open=False, timeout=10,
            kwargs={'autocommit': True, 'prepare_threshold': None,
                    'connect_timeout': 10, 'sslmode': 'require'},
            check=ConnectionPool.check_connection,
        )
        try:
            self.pool.open(wait=True)
            with self.pool.connection() as db:
                # Schema changes are applied explicitly using the SQL migration.
                db.execute('SELECT 1 FROM pocketwise.documents LIMIT 0')
        except Exception:
            self.pool.close()
            raise

    @contextmanager
    def atomic(self, owner):
        with self.pool.connection() as db, db.transaction():
            db.execute("SET LOCAL statement_timeout = '10s'")
            db.execute('SELECT pg_advisory_xact_lock(hashtextextended(%s, 0))', (owner,))
            scoped = SupabaseRepository.__new__(SupabaseRepository)
            scoped.pool = _BoundConnection(db)
            yield scoped

    def find(self, collection, **query):
        with self.pool.connection() as db:
            rows = db.execute(
                'SELECT body FROM pocketwise.documents WHERE collection=%s AND body @> %s',
                (collection, Jsonb(query)),
            ).fetchall()
        return [row[0] for row in rows]

    def get(self, collection, **query):
        with self.pool.connection() as db:
            row = db.execute(
                'SELECT body FROM pocketwise.documents WHERE collection=%s AND body @> %s LIMIT 1',
                (collection, Jsonb(query)),
            ).fetchone()
        return row[0] if row else None

    def put(self, collection, doc):
        try:
            with self.pool.connection() as db:
                db.execute(
                    'INSERT INTO pocketwise.documents (collection, id, body) VALUES (%s, %s, %s) '
                    'ON CONFLICT (collection, id) DO UPDATE SET body=EXCLUDED.body',
                    (collection, doc['id'], Jsonb(doc)),
                )
        except UniqueViolation as exc:
            raise DuplicateRecordError('A unique document already exists.') from exc
        return doc

    def delete(self, collection, **query):
        with self.pool.connection() as db:
            return db.execute(
                'DELETE FROM pocketwise.documents WHERE collection=%s AND body @> %s',
                (collection, Jsonb(query)),
            ).rowcount

    def consume(self, collection, id):
        # One statement makes refresh tokens single-use across API processes.
        with self.pool.connection() as db:
            row = db.execute(
                'DELETE FROM pocketwise.documents WHERE collection=%s AND id=%s RETURNING body',
                (collection, id),
            ).fetchone()
        return row[0] if row else None

    def close(self):
        self.pool.close()


class _BoundConnection:
    def __init__(self, connection):
        self.db = connection

    def connection(self):
        return nullcontext(self.db)
