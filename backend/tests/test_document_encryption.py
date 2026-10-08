import base64
from copy import deepcopy
import json
from concurrent.futures import ThreadPoolExecutor

import pytest
from fastapi.testclient import TestClient

from app.infrastructure.document_encryption import DocumentCipher, EncryptionError, cipher_from_environment
from app.main import create_app
from app.repositories.documents import LocalRepository
from app.repositories.encrypted import EncryptedRepository
from app.repositories.encryption_migration import migrate_documents
from app.domain.ports import DuplicateRecordError


@pytest.fixture
def cipher():
    return DocumentCipher({'v1': b'a' * 32}, 'v1')


def sample():
    return {'id': 'tx', 'user_id': 'owner', 'category_id': 'food', 'amount': 1537,
            'note': 'Private lunch €', 'details': {'salary': 987654, 'confirmed': True}}


def test_cipher_seals_payload_and_randomizes_every_write(cipher):
    doc = sample()
    original = deepcopy(doc)
    first = cipher.encrypt('transactions', doc)
    second = cipher.encrypt('transactions', doc)
    assert first != second
    assert set(first) == {'id', 'user_id', 'category_id', '_encrypted'}
    assert 'Private lunch' not in json.dumps(first)
    assert cipher.decrypt('transactions', first) == original
    assert cipher.decrypt('transactions', second) == original
    assert doc == original


@pytest.mark.parametrize('change', ['ciphertext', 'nonce', 'key_id', 'version', 'algorithm', 'owner', 'id', 'extra', 'collection', 'wrong_key'])
def test_tampering_and_wrong_keys_are_rejected(cipher, change):
    record = cipher.encrypt('transactions', sample())
    collection = 'transactions'
    if change in ('ciphertext', 'nonce'):
        value = bytearray(base64.b64decode(record['_encrypted'][change]))
        value[0] ^= 1
        record['_encrypted'][change] = base64.b64encode(value).decode()
    elif change in ('key_id', 'version', 'algorithm'):
        record['_encrypted'][change] = 'invalid'
    elif change == 'owner':
        record['user_id'] = 'other'
    elif change == 'id':
        record['id'] = 'other'
    elif change == 'extra':
        record['amount'] = 1
    elif change == 'collection':
        collection = 'funding'
    else:
        cipher = DocumentCipher({'v1': b'b' * 32}, 'v1')
    with pytest.raises(EncryptionError):
        cipher.decrypt(collection, record)


def test_rotation_can_read_old_records_but_writes_active_key(cipher):
    old = cipher.encrypt('transactions', sample())
    rotated = DocumentCipher({'v1': b'a' * 32, 'v2': b'b' * 32}, 'v2')
    assert rotated.decrypt('transactions', old) == sample()
    current = rotated.encrypt('transactions', sample())
    assert current['_encrypted']['key_id'] == 'v2'
    with pytest.raises(EncryptionError):
        cipher.decrypt('transactions', current)


def test_repository_restart_filters_uniqueness_rollback_and_consume(tmp_path, cipher):
    path = str(tmp_path / 'encrypted.sqlite')
    raw = LocalRepository(path)
    repo = EncryptedRepository(raw, cipher)
    repo.put('transactions', sample())
    repo.put('users', {'id': 'owner', 'email': 'alex@example.com', 'name': 'Private Name'})
    with pytest.raises(DuplicateRecordError):
        repo.put('users', {'id': 'other', 'email': 'alex@example.com'})
    with pytest.raises(RuntimeError):
        with repo.atomic('owner') as scoped:
            scoped.put('transactions', dict(sample(), amount=1))
            scoped.put('funding_events', {'id': 'event', 'user_id': 'owner', 'amount': 5})
            raise RuntimeError('rollback')
    assert repo.get('transactions', id='tx') == sample()
    assert repo.find('funding_events', user_id='owner') == []
    repo.close()
    raw = LocalRepository(path)
    repo = EncryptedRepository(raw, cipher)
    try:
        assert repo.find('transactions', user_id='other') == []
        assert repo.find('transactions', amount=1537) == [sample()]
        assert repo.get('transactions', note='Private lunch €') == sample()
        assert repo.get('users', email='alex@example.com')['name'] == 'Private Name'
        assert 'name' not in raw.get('users', id='owner')
        token = {'id': 'session', 'user_id': 'owner', 'secret': 'private'}
        repo.put('sessions', token)
        with ThreadPoolExecutor(max_workers=2) as executor:
            results = list(executor.map(lambda _: repo.consume('sessions', 'session'), range(2)))
        assert results.count(token) == 1
        assert results.count(None) == 1
        assert repo.delete('transactions', amount=1537) == 1
        assert repo.find('transactions') == []
    finally:
        repo.close()


def test_plaintext_rejected_and_failed_authentication_does_not_consume(cipher):
    raw = LocalRepository(':memory:')
    repo = EncryptedRepository(raw, cipher)
    try:
        raw.put('sessions', {'id': 'legacy', 'secret': 'plain'})
        with pytest.raises(EncryptionError, match='migration'):
            repo.consume('sessions', 'legacy')
        assert raw.get('sessions', id='legacy') is not None
        repo.put('sessions', {'id': 'bad', 'secret': 'private'})
        bad = raw.get('sessions', id='bad')
        bad['_encrypted']['ciphertext'] = 'AAAA'
        raw.put('sessions', bad)
        with pytest.raises(EncryptionError):
            repo.consume('sessions', 'bad')
        assert raw.get('sessions', id='bad') == bad
    finally:
        repo.close()


def test_migration_dry_run_rotation_and_atomic_failure(cipher, monkeypatch):
    raw = LocalRepository(':memory:')
    try:
        raw.put('transactions', sample())
        raw.put('users', {'id': 'owner', 'email': 'alex@example.com', 'name': 'Alex'})
        assert migrate_documents(raw, cipher) == {'plaintext': 2, 'encrypted': 0, 'rewritten': 0}
        assert raw.get('transactions', id='tx') == sample()
        original_put = raw.put
        def fail_users(collection, doc):
            if collection == 'users':
                raise RuntimeError('simulated write failure')
            return original_put(collection, doc)
        with monkeypatch.context() as patch:
            patch.setattr(raw, 'put', fail_users)
            with pytest.raises(RuntimeError):
                migrate_documents(raw, cipher, apply=True)
        assert raw.get('transactions', id='tx') == sample()
        assert migrate_documents(raw, cipher, apply=True)['rewritten'] == 2
        assert migrate_documents(raw, cipher, apply=True)['rewritten'] == 0
        rotated = DocumentCipher({'v1': b'a' * 32, 'v2': b'b' * 32}, 'v2')
        assert migrate_documents(raw, rotated, apply=True)['rewritten'] == 2
        assert EncryptedRepository(raw, rotated).get('transactions', id='tx') == sample()
        with pytest.raises(EncryptionError):
            migrate_documents(raw, cipher, apply=True)
    finally:
        raw.close()


def test_key_configuration_and_app_startup_fail_closed(tmp_path, monkeypatch):
    monkeypatch.delenv('DOCUMENT_ENCRYPTION_KEY_FILE', raising=False)
    monkeypatch.setenv('DATABASE_MODE', 'local')
    with pytest.raises(EncryptionError, match='DOCUMENT_ENCRYPTION_KEY_FILE'):
        with TestClient(create_app()):
            pass
    key_file = tmp_path / 'keys.json'
    key_file.write_text(json.dumps({'active_key_id': 'v1', 'keys': {'v1': base64.b64encode(b'a' * 32).decode()}}))
    monkeypatch.setenv('DOCUMENT_ENCRYPTION_KEY_FILE', str(key_file))
    monkeypatch.setenv('LOCAL_DATABASE_PATH', str(tmp_path / 'app.sqlite'))
    with TestClient(create_app()) as client:
        assert isinstance(client.app.state.repo, EncryptedRepository)
    key_file.write_text('{"active_key_id":"v1","keys":{"v1":"bad"}}')
    with pytest.raises(EncryptionError):
        cipher_from_environment(required=True)


def test_api_encryption_errors_do_not_expose_record_or_key(cipher):
    raw = LocalRepository(':memory:')
    raw.put('users', {'id': 'owner', 'email': 'alex@example.com', 'password_hash': 'secret'})
    try:
        with TestClient(create_app(EncryptedRepository(raw, cipher), secret='x' * 32)) as client:
            response = client.post('/auth/login', json={'email': 'alex@example.com', 'password': 'password123'})
            assert response.status_code == 503
            assert response.json() == {'error': {'message': 'Stored data is temporarily unavailable.'}}
    finally:
        raw.close()
