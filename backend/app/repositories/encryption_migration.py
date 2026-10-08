"""Offline, atomic encryption/rotation of existing document storage."""
import json

from ..infrastructure.document_encryption import MARKER
from .documents import LocalRepository
from .supabase import SupabaseRepository


def migrate_documents(repository, cipher, *, apply=False):
    """Validate all rows, then rewrite in one transaction. Stop API writers first.

    Dry runs also authenticate every encrypted row. No plaintext is returned.
    Old keys must stay available until retained backups have expired.
    """
    counts = {'plaintext': 0, 'encrypted': 0, 'rewritten': 0}
    with repository.atomic('__document_encryption_migration__') as scoped:
        if isinstance(scoped, LocalRepository):
            rows = [(collection, id, json.loads(body)) for collection, id, body in
                    scoped.db.execute('SELECT collection, id, body FROM documents').fetchall()]
        elif isinstance(scoped, SupabaseRepository):
            with scoped.pool.connection() as db:
                # Advisory owner locks alone cannot exclude all application writes.
                db.execute("SET LOCAL lock_timeout = '10s'")
                db.execute('LOCK TABLE pocketwise.documents IN EXCLUSIVE MODE')
                rows = db.execute('SELECT collection, id, body FROM pocketwise.documents').fetchall()
        else:
            raise TypeError('Unsupported migration repository.')
        pending = []
        for collection, id, record in rows:
            encrypted = MARKER in record
            counts['encrypted' if encrypted else 'plaintext'] += 1
            document = cipher.decrypt(collection, record) if encrypted else record
            if document.get('id') != id:
                raise ValueError('Stored document identity does not match its row.')
            if not encrypted or record[MARKER]['key_id'] != cipher.active_key_id:
                sealed = cipher.encrypt(collection, document)
                if cipher.decrypt(collection, sealed) != document:
                    raise ValueError('Encryption verification failed.')
                pending.append((collection, sealed))
        if apply:
            for collection, sealed in pending:
                scoped.put(collection, sealed)
            counts['rewritten'] = len(pending)
    return counts
