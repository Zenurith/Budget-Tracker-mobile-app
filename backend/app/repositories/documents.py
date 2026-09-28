"""Document storage: MongoDB in production, persistent SQLite for local development."""
import json
import sqlite3
import threading
from pathlib import Path
from pymongo import MongoClient


class LocalRepository:
    def __init__(self, path: str):
        if path != ':memory:':
            Path(path).parent.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(path, check_same_thread=False)
        self.lock = threading.RLock()
        self.db.execute('CREATE TABLE IF NOT EXISTS documents (collection TEXT, id TEXT, body TEXT, PRIMARY KEY(collection,id))')
        self.db.execute("CREATE UNIQUE INDEX IF NOT EXISTS unique_email ON documents(json_extract(body, '$.email')) WHERE collection='users'")

    def find(self, collection, **query):
        with self.lock:
            rows = self.db.execute('SELECT body FROM documents WHERE collection=?', (collection,)).fetchall()
        docs = [json.loads(row[0]) for row in rows]
        return [doc for doc in docs if all(doc.get(key) == value for key, value in query.items())]

    def get(self, collection, **query):
        return next(iter(self.find(collection, **query)), None)

    def put(self, collection, doc):
        with self.lock, self.db:
            self.db.execute('INSERT INTO documents VALUES (?,?,?) ON CONFLICT(collection,id) DO UPDATE SET body=excluded.body', (collection, doc['id'], json.dumps(doc)))
        return doc

    def delete(self, collection, **query):
        with self.lock, self.db:
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


class MongoRepository:
    def __init__(self, uri, database):
        self.client = MongoClient(uri, serverSelectionTimeoutMS=5000)
        self.db = self.client[database]
        self.db.users.create_index('email', unique=True)
        for name in ('users', 'transactions', 'categories', 'budgets', 'sessions'):
            self.db[name].create_index('id', unique=True)
        self.db.transactions.create_index([('user_id', 1), ('date', -1)])
        self.db.budgets.create_index([('user_id', 1), ('period', 1), ('category_id', 1)], unique=True)

    def find(self, collection, **query):
        return list(self.db[collection].find(query, {'_id': 0}))

    def get(self, collection, **query):
        return self.db[collection].find_one(query, {'_id': 0})

    def put(self, collection, doc):
        self.db[collection].replace_one({'id': doc['id']}, doc, upsert=True)
        return doc

    def delete(self, collection, **query):
        return self.db[collection].delete_many(query).deleted_count

    def consume(self, collection, id):
        return self.db[collection].find_one_and_delete({'id': id}, projection={'_id': 0})

    def close(self):
        self.client.close()
