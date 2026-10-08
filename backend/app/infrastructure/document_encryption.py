"""Versioned AES-256-GCM document envelopes; keys never enter database records."""
import base64
import binascii
import json
import os
from pathlib import Path

from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives.ciphers.aead import AESGCM


MARKER = '_encrypted'
# Keep existing owner queries and unique indexes usable. Everything else is sealed.
LOOKUP_FIELDS = frozenset({'id', 'user_id', 'email', 'period', 'category_id'})


class EncryptionError(RuntimeError):
    """An unreadable record or invalid key configuration. Never contains secrets."""


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode()


class DocumentCipher:
    def __init__(self, keys, active_key_id):
        if not keys or active_key_id not in keys:
            raise EncryptionError('Configure a valid active document encryption key.')
        if any(not isinstance(k, str) or not k or not isinstance(v, bytes) or len(v) != 32
               for k, v in keys.items()):
            raise EncryptionError('Document encryption requires named 32-byte keys.')
        self._keys = {key_id: AESGCM(key) for key_id, key in keys.items()}
        self.active_key_id = active_key_id

    def encrypt(self, collection, document):
        if MARKER in document:
            raise EncryptionError('Reserved encryption field in document.')
        metadata = {key: value for key, value in document.items() if key in LOOKUP_FIELDS}
        header = {'version': 1, 'algorithm': 'AES-256-GCM', 'key_id': self.active_key_id}
        nonce = os.urandom(12)
        aad = canonical(['pocketwise.documents', collection, metadata, header])
        ciphertext = self._keys[self.active_key_id].encrypt(nonce, canonical(document), aad)
        return {**metadata, MARKER: {**header, 'nonce': base64.b64encode(nonce).decode(),
                                    'ciphertext': base64.b64encode(ciphertext).decode()}}

    def decrypt(self, collection, record):
        try:
            envelope = record[MARKER]
            if set(envelope) != {'version', 'algorithm', 'key_id', 'nonce', 'ciphertext'}:
                raise ValueError()
            if envelope['version'] != 1 or envelope['algorithm'] != 'AES-256-GCM':
                raise ValueError()
            metadata = {key: value for key, value in record.items() if key != MARKER}
            if not set(metadata).issubset(LOOKUP_FIELDS):
                raise ValueError()
            header = {key: envelope[key] for key in ('version', 'algorithm', 'key_id')}
            nonce = base64.b64decode(envelope['nonce'], validate=True)
            if len(nonce) != 12:
                raise ValueError()
            plaintext = self._keys[envelope['key_id']].decrypt(
                nonce, base64.b64decode(envelope['ciphertext'], validate=True),
                canonical(['pocketwise.documents', collection, metadata, header]))
            document = json.loads(plaintext)
            if (not isinstance(document, dict) or MARKER in document or
                    {k: v for k, v in document.items() if k in LOOKUP_FIELDS} != metadata):
                raise ValueError()
            return document
        except (InvalidTag, KeyError, TypeError, ValueError, binascii.Error):
            raise EncryptionError('Document authentication failed; check encryption keys and stored data.') from None


def cipher_from_environment(*, required=False):
    """Load a mounted secret file. Never generate an ephemeral data key."""
    path = os.getenv('DOCUMENT_ENCRYPTION_KEY_FILE')
    if not path:
        if required:
            raise EncryptionError('Set DOCUMENT_ENCRYPTION_KEY_FILE before starting the database-backed app.')
        return None
    try:
        config = json.loads(Path(path).read_text())
        keys = {name: base64.b64decode(value, validate=True) for name, value in config['keys'].items()}
        return DocumentCipher(keys, config['active_key_id'])
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        raise EncryptionError('Cannot load the document encryption key file.') from None
