from datetime import datetime, timezone
from concurrent.futures import ThreadPoolExecutor
from unittest.mock import MagicMock, patch
import pytest
from fastapi.testclient import TestClient
from app.main import create_app
from app.domain import recovery
from app.infrastructure.document_encryption import DocumentCipher
from app.infrastructure.recovery_mail import SMTPResetMailer
from app.repositories.documents import LocalRepository
from app.repositories.encrypted import EncryptedRepository
from test_api import signup


class Mailbox:
    configured = True
    def __init__(self): self.messages = []
    def send_reset(self, recipient, token): self.messages.append((recipient, token))


@pytest.fixture(params=[False, True])
def setup(request):
    raw = LocalRepository(':memory:')
    db = EncryptedRepository(raw, DocumentCipher({'test': b'x' * 32}, 'test')) if request.param else raw
    mailbox = Mailbox()
    with TestClient(create_app(db, secret='x' * 32, mailer=mailbox)) as client:
        yield client, db, mailbox
    db.close()


def test_recovery_generic_response_hash_only_expiry_and_session_revocation(setup, monkeypatch):
    client, db, mailbox = setup
    h, session = signup(client)
    known = client.post('/auth/password/request', json={'email': 'alex@example.com'})
    unknown = client.post('/auth/password/request', json={'email': 'unknown@example.com'})
    assert known.status_code == unknown.status_code == 202
    assert known.json() == unknown.json()
    assert known.headers['cache-control'] == 'no-store'
    assert len(mailbox.messages) == 1
    token = mailbox.messages[0][1]
    assert token not in str(db.find('password_resets'))
    assert client.post('/auth/password/request', json={'email': 'alex@example.com'}).status_code == 202
    assert len(mailbox.messages) == 1
    assert client.post('/auth/password/reset', json={'token': token, 'password': 'short'}).status_code == 422
    response = client.post('/auth/password/reset', json={'token': token, 'password': 'new-password-123'})
    assert response.status_code == 200
    assert client.get('/auth/me', headers=h).status_code == 401
    assert client.post('/auth/refresh', json={'refresh_token': session['refresh_token']}).status_code == 401
    assert client.post('/auth/password/reset', json={'token': token, 'password': 'another-password'}).status_code == 422
    assert client.post('/auth/login', json={'email': 'alex@example.com', 'password': 'correct-horse-123'}).status_code == 401
    assert client.post('/auth/login', json={'email': 'alex@example.com', 'password': 'new-password-123'}).status_code == 200
    client.post('/auth/password/request', json={'email': 'alex@example.com'})
    monkeypatch.setattr(recovery, 'now', lambda: datetime(2099, 1, 1, tzinfo=timezone.utc))
    assert client.post('/auth/password/reset', json={'token': mailbox.messages[-1][1], 'password': 'expired-password'}).status_code == 422


def test_recovery_only_one_concurrent_reset_succeeds(setup):
    client, db, mailbox = setup
    signup(client)
    client.post('/auth/password/request', json={'email': 'alex@example.com'})
    token = mailbox.messages[0][1]
    with ThreadPoolExecutor(max_workers=2) as pool:
        responses = list(pool.map(lambda _: client.post('/auth/password/reset', json={'token': token, 'password': 'new-password-123'}).status_code, range(2)))
    assert sorted(responses) == [200, 422]


def test_unconfigured_email_is_clear_and_smtp_failure_does_not_leak_account(setup):
    client, db, mailbox = setup
    signup(client)
    mailbox.configured = False
    assert client.post('/auth/password/request', json={'email': 'alex@example.com'}).status_code == 503
    mailbox.configured = True
    with patch.object(mailbox, 'send_reset', side_effect=RuntimeError('secret SMTP details')):
        response = client.post('/auth/password/request', json={'email': 'alex@example.com'})
        assert response.status_code == 202
        assert 'secret' not in response.text
    assert db.find('password_resets') == []


def test_smtp_starttls_and_local_inbox_configuration(monkeypatch):
    monkeypatch.setenv('SMTP_HOST', 'smtp.example.com')
    monkeypatch.setenv('SMTP_SECURITY', 'starttls')
    monkeypatch.setenv('SMTP_USERNAME', 'smtp-user')
    monkeypatch.setenv('SMTP_PASSWORD', 'smtp-password')
    with patch('app.infrastructure.recovery_mail.smtplib.SMTP') as smtp:
        mailer = SMTPResetMailer()
        mailer.send_reset('alex@example.com', 'test-code')
        connection = smtp.return_value.__enter__.return_value
        connection.starttls.assert_called_once()
        connection.login.assert_called_once_with('smtp-user', 'smtp-password')
        message = connection.send_message.call_args.args[0]
        assert message['To'] == 'alex@example.com' and 'test-code' in message.get_content()
    monkeypatch.setenv('SMTP_SECURITY', 'local')
    with pytest.raises(ValueError): SMTPResetMailer()
    monkeypatch.setenv('SMTP_HOST', '127.0.0.1')
    assert SMTPResetMailer().configured


def test_reset_failure_rolls_back_password_sessions_and_token(setup, monkeypatch):
    client, db, mailbox = setup
    h, _ = signup(client)
    client.post('/auth/password/request', json={'email': 'alex@example.com'})
    token = mailbox.messages[0][1]
    original = db.delete
    def fail(collection, **query):
        if collection == 'sessions':
            raise RuntimeError('session delete failed')
        return original(collection, **query)
    with monkeypatch.context() as patch:
        patch.setattr(db, 'delete', fail)
        with pytest.raises(RuntimeError):
            client.post('/auth/password/reset', json={'token': token, 'password': 'new-password-123'})
    assert client.get('/auth/me', headers=h).status_code == 200
    assert client.post('/auth/login', json={'email': 'alex@example.com', 'password': 'correct-horse-123'}).status_code == 200
    assert client.post('/auth/password/reset', json={'token': token, 'password': 'new-password-123'}).status_code == 200
