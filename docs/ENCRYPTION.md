# Database document encryption

Pocketwise encrypts document contents in the backend using AES-256-GCM before
writing to either SQLite or Supabase Postgres. The backend decrypts on reads so
existing calculations, search, reports, synchronization and authorized exports
continue to work. This is server-side encryption, not end-to-end encryption.

Every document is sealed with a fresh random 96-bit nonce and a 256-bit key.
The GCM authentication tag, nonce, format version and key ID are stored with the
ciphertext. Collection name and lookup metadata are authenticated as additional
data to reject changes of record identity or owner. The implementation uses
the Python `cryptography` library, not a custom cipher.

## What remains visible

Collection names and the `id`, `user_id`, `email`, `period` and `category_id`
fields remain readable to preserve owner queries, login lookup and existing
unique email/budget indexes. Amounts, notes, names, financial profiles, funding
state, wishlist contents, snapshot inputs and outputs, and session payloads are
encrypted. Passwords continue to use Argon2 hashing; their hashes are also inside
the encrypted payload. Email is **not encrypted** in this version.

This protects payloads in database dumps from readers without the backend keys.
It does not protect against a compromised backend, deletion or replay of an old
valid ciphertext. Authorized JSON exports and existing mobile offline caches
are not encrypted by this change. HTTPS/TLS is still required between Flutter
and the backend and between the backend and Postgres. Local HTTP development
defaults and the existing Postgres TLS configuration are unchanged.

## First-time setup

All non-injected application repositories require `DOCUMENT_ENCRYPTION_KEY_FILE`.
Startup fails without it. There is no temporary key or plaintext write fallback.
Raw repository injection remains available for isolated tests and migration tools.

From `backend/`, initialize a key file in a private directory outside the source
tree (substitute an actual absolute path):

```sh
.venv/bin/python scripts/encrypt_documents.py --init-key-file /PRIVATE/PATH/pocketwise.encryption-keys.json
```

The command creates a random key with exclusive creation and file mode 0600,
never overwrites an existing key file, and never prints the key. On Windows,
also restrict the file ACL to the backend service identity. Add to `backend/.env`:

```dotenv
DOCUMENT_ENCRYPTION_KEY_FILE=/PRIVATE/PATH/pocketwise.encryption-keys.json
```

Back up the key in a secure, separate location **before migration**. Losing all
copies makes encrypted records unrecoverable. For production, mount the key file
from a managed secret store; keep it out of Flutter, Git, images, logs and database
backups. A KMS envelope-encryption integration is not implemented. Docker Compose
mounts the configured absolute host file as `/run/secrets/document_keys`; ensure
the container's `appuser` can read the mounted secret with restricted host access.

For a fresh empty database, start the API after configuring the key. For existing
data, follow the migration procedure before starting the updated API.

## Existing records and key rotation

1. Stop **all** API instances and other database writers. Do not run old application
   versions against the encrypted store.
2. Make and verify a recoverable database backup, and retain the separate keys.
3. From `backend/`, run the default validation command. It authenticates encrypted
   records and reports only counts; it does not rewrite records:

   ```sh
   .venv/bin/python scripts/encrypt_documents.py
   ```

4. Apply the migration, then run validation again:

   ```sh
   .venv/bin/python scripts/encrypt_documents.py --apply
   .venv/bin/python scripts/encrypt_documents.py
   ```

5. Confirm `plaintext` is zero, then start all API workers with the same key file.

The migration encrypts legacy rows and re-encrypts rows whose key ID differs from
the active key. It authenticates and prepares every row before rewriting any,
then commits atomically. A failure rolls back all rewrites. PostgreSQL uses a table
lock during migration; SQLite uses its existing write transaction. This is an
offline, in-memory migration intended for the current prototype database size.
For large databases, design and verify a batched migration first. Dry runs also
take a lock and should be performed during maintenance.

The API rejects legacy plaintext records. It does not silently accept plaintext
or automatically migrate on reads. Wrong/missing keys and tampered envelopes
produce a generic unavailable response without exposing record details.

To rotate, retain previous entries in the key file, add a new independently
generated 32-byte base64 key under a new ID, and select it as `active_key_id`:

```json
{"active_key_id":"v2","keys":{"v1":"<old base64 key>","v2":"<new base64 key>"}}
```

Run the same maintenance migration and restart every worker. Do not reuse a key
ID for different key material. Retain old keys for as long as any backup needs
them. A database rollback must restore the matching key set as well.

Old database backups, PostgreSQL WAL/snapshots and SQLite free pages/WAL may retain
the original plaintext after rewriting. Handle their retention or storage-level
sanitization separately; rewriting rows is not secure erasure.

## Verification

Run `python -m pytest -q` from `backend/`. Shared API fixtures exercise plaintext
test storage and encrypted storage, including funding, purchases and sync. Dedicated
tests cover tampering, wrong keys, rotation, persistent restart, ownership, atomic
rollback, uniqueness, single-use sessions, migration and fail-closed configuration.
Live Postgres encryption tests are opt-in and require a disposable test database.

References: [cryptography AESGCM](https://cryptography.io/en/stable/hazmat/primitives/aead/)
and [OWASP cryptographic storage](https://cheatsheetseries.owasp.org/cheatsheets/Cryptographic_Storage_Cheat_Sheet.html).
