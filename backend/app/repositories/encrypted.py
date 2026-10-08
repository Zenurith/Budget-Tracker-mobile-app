"""Encryption decorator preserving the domain repository and transaction contract."""
from contextlib import contextmanager

from ..infrastructure.document_encryption import EncryptionError, LOOKUP_FIELDS, MARKER


class EncryptedRepository:
    def __init__(self, repository, cipher):
        self.repository = repository
        self.cipher = cipher

    @contextmanager
    def atomic(self, owner):
        with self.repository.atomic(owner) as scoped:
            yield self if scoped is self.repository else EncryptedRepository(scoped, self.cipher)

    def _read(self, collection, record):
        if record is None:
            return None
        if MARKER not in record:
            raise EncryptionError('Unencrypted document found; run the document encryption migration.')
        return self.cipher.decrypt(collection, record)

    def find(self, collection, **query):
        lookup = {k: v for k, v in query.items() if k in LOOKUP_FIELDS}
        docs = [self._read(collection, row) for row in self.repository.find(collection, **lookup)]
        return [doc for doc in docs if all(doc.get(k) == v for k, v in query.items())]

    def get(self, collection, **query):
        if set(query).issubset(LOOKUP_FIELDS):
            return self._read(collection, self.repository.get(collection, **query))
        return next(iter(self.find(collection, **query)), None)

    def put(self, collection, doc):
        self.repository.put(collection, self.cipher.encrypt(collection, doc))
        return doc

    def delete(self, collection, **query):
        if set(query).issubset(LOOKUP_FIELDS):
            return self.repository.delete(collection, **query)
        # Current application deletes use only indexed metadata. Preserve the
        # general contract for future callers filtering encrypted attributes.
        with self.atomic(query.get('user_id', '__encrypted_delete__')) as scoped:
            docs = scoped.find(collection, **query)
            return sum(scoped.repository.delete(collection, id=doc['id']) for doc in docs)

    def consume(self, collection, id):
        # Authentication failure must roll back consumption, not lose the record.
        with self.repository.atomic(id) as scoped:
            return self._read(collection, scoped.consume(collection, id))

    def close(self):
        self.repository.close()
