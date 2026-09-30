"""Document storage: Supabase Postgres in production, persistent SQLite for local development."""
import json
import sqlite3
import threading
from contextlib import contextmanager
from pathlib import Path
from ..domain.ports import DuplicateRecordError


class LocalRepository:
    def __init__(self, path: str):
        if path != ':memory:':
            Path(path).parent.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(path, check_same_thread=False)
        self.lock = threading.RLock()
        self._in_transaction = False
        self.db.execute('CREATE TABLE IF NOT EXISTS documents (collection TEXT, id TEXT, body TEXT, PRIMARY KEY(collection,id))')
        self.db.execute("CREATE UNIQUE INDEX IF NOT EXISTS unique_email ON documents(json_extract(body, '$.email')) WHERE collection='users'")

    @contextmanager
    def atomic(self, owner):
        with self.lock:
            if self._in_transaction:
                yield self
                return
            self.db.execute('BEGIN IMMEDIATE')
            self._in_transaction = True
            try:
                yield self
                self.db.commit()
            except BaseException:
                self.db.rollback()
                raise
            finally:
                self._in_transaction = False

    @contextmanager
    def _write(self):
        if self._in_transaction:
            yield
        else:
            with self.db:
                yield

    def find(self, collection, **query):
        with self.lock:
            rows = self.db.execute('SELECT body FROM documents WHERE collection=?', (collection,)).fetchall()
        docs = [json.loads(row[0]) for row in rows]
        return [doc for doc in docs if all(doc.get(key) == value for key, value in query.items())]

    def get(self, collection, **query):
        return next(iter(self.find(collection, **query)), None)

    def put(self, collection, doc):
        try:
            with self.lock, self._write():
                self.db.execute('INSERT INTO documents VALUES (?,?,?) ON CONFLICT(collection,id) DO UPDATE SET body=excluded.body', (collection, doc['id'], json.dumps(doc)))
        except sqlite3.IntegrityError as exc:
            if exc.sqlite_errorcode not in (sqlite3.SQLITE_CONSTRAINT_UNIQUE, sqlite3.SQLITE_CONSTRAINT_PRIMARYKEY):
                raise
            raise DuplicateRecordError('A unique document already exists.') from exc
        return doc

    def delete(self, collection, **query):
        with self.lock, self._write():
            docs = self.find(collection, **query)
            for doc in docs:
                self.db.execute('DELETE FROM documents WHERE collection=? AND id=?', (collection, doc['id']))
        return len(docs)

    def consume(self, collection, id):
        with self.lock:
            doc = self.get(collection, id=id)
            if doc:
                self.delete(collection, id=id)
            return doc

    def close(self):
        self.db.close()
