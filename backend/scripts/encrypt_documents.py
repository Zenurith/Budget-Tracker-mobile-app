"""Offline encryption migration. Defaults to validation only; never prints keys/data."""
import argparse
import base64
import json
import os
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from dotenv import load_dotenv
from app.infrastructure.document_encryption import cipher_from_environment
from app.repositories.documents import LocalRepository
from app.repositories.supabase import SupabaseRepository
from app.repositories.encryption_migration import migrate_documents


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--env-file', type=Path, default=Path(__file__).resolve().parents[1] / '.env')
    parser.add_argument('--init-key-file', type=Path, help='Create a new secret file (never overwrite).')
    parser.add_argument('--apply', action='store_true', help='Rewrite records; API workers must be stopped.')
    args = parser.parse_args()
    if args.init_key_file:
        if args.apply:
            parser.error('Initialize keys separately from migration.')
        # Exclusive creation and restrictive permissions from the first write.
        descriptor = os.open(args.init_key_file, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, 'w') as file:
            json.dump({'active_key_id': 'v1', 'keys': {
                'v1': base64.b64encode(os.urandom(32)).decode()}}, file)
            file.flush()
            os.fsync(file.fileno())
        print('Created key file. Back it up securely before encrypting any data.')
        return 0
    load_dotenv(args.env_file)
    cipher = cipher_from_environment(required=True)
    mode = os.getenv('DATABASE_MODE', 'local')
    if mode == 'supabase':
        repository = SupabaseRepository(os.environ['SUPABASE_DB_URL'])
    elif mode == 'local':
        path = os.getenv('LOCAL_DATABASE_PATH', 'data/pocketwise.sqlite')
        if not Path(path).is_file():
            raise ValueError('Local database does not exist; check the working directory and path.')
        repository = LocalRepository(path)
    else:
        raise ValueError('Invalid database mode.')
    try:
        print(json.dumps(migrate_documents(repository, cipher, apply=args.apply)))
    finally:
        repository.close()
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except Exception as error:
        # Driver exceptions may contain credentials. Do not print their messages.
        print(f'Encryption setup failed ({type(error).__name__}). Check configuration and keys.', file=sys.stderr)
        raise SystemExit(1)
