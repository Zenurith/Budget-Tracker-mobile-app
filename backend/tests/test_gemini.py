import io
import json
from datetime import date
from urllib.error import HTTPError, URLError
import pytest
from fastapi.testclient import TestClient
from app.domain.errors import DomainError, ErrorKind
from app.domain.finance import CATEGORIES
from app.infrastructure.gemini import GeminiParser
from app.main import create_app
from app.repositories.documents import LocalRepository

DRAFT = {'amount': 1550, 'type': 'expense', 'category_id': 'food', 'date': '2026-09-28', 'payment_method': 'Cash'}


def mock_output(monkeypatch, value, finish='STOP'):
    def send(request, timeout, context):
        body = json.loads(request.data)
        assert request.full_url.endswith('/gemini-3.5-flash-lite:generateContent')
        assert 'test-key' not in request.full_url
        assert timeout == 25
        context = json.loads(body['contents'][0]['parts'][0]['text'])
        assert context['currency'] == 'MYR'
        assert all(set(c) == {'id', 'name', 'type'} for c in context['categories'])
        return io.BytesIO(json.dumps({'candidates': [{'finishReason': finish, 'content': {'parts': [{'text': json.dumps(value)}]}}]}).encode())
    monkeypatch.setattr('app.infrastructure.gemini.urlopen', send)


def parse():
    return GeminiParser('test-key')('Lunch 15.50 yesterday', date(2026, 9, 29), CATEGORIES, 'MYR')


def test_transaction_entry_stays_local_with_gemini_configured(monkeypatch):
    monkeypatch.setenv('GEMINI_API_KEY', 'test-key')
    monkeypatch.setenv('GEMINI_MODEL', 'gemini-3.5-flash-lite')
    monkeypatch.setenv('NLP_PROVIDER', 'gemini')  # Obsolete setting must not enable AI.
    def unexpected_network(*args, **kwargs):
        pytest.fail('Transaction parsing must not call Gemini')
    monkeypatch.setattr('app.infrastructure.gemini.urlopen', unexpected_network)
    repo = LocalRepository(':memory:')
    with TestClient(create_app(repo, secret='test-secret-that-is-at-least-32-characters')) as client:
        tokens = client.post('/auth/register', json={'name': 'Alex', 'email': 'alex@example.com', 'password': 'password123', 'currency': 'MYR'}).json()
        headers = {'Authorization': 'Bearer ' + tokens['access_token']}
        assert client.post('/nlp/parse', json={'text': 'Lunch 15.50'}).status_code == 401
        result = client.post('/nlp/parse', headers=headers, json={'text': 'Lunch 15.50 yesterday', 'reference_date': '2026-09-29'})
        assert result.status_code == 200
        tx = result.json()['transaction']
        assert tx['amount'] == 1550 and tx['source'] == 'nlp'
        assert client.get('/transactions', headers=headers).json()['total'] == 0
        assert client.post('/transactions', headers=headers, json=tx).status_code == 201
    repo.close()


@pytest.mark.parametrize('changes', [{'amount': -1}, {'amount': 1.5}, {'amount': True}, {'amount': 100_000_000_001}, {'category_id': 'someone-elses-category'}, {'category_id': 'salary'}, {'date': '2026-02-30'}, {'source': 'manual'}])
def test_rejects_invalid_model_details(monkeypatch, changes):
    mock_output(monkeypatch, {'transaction': dict(DRAFT, **changes), 'warnings': []})
    with pytest.raises(DomainError) as error:
        parse()
    assert error.value.kind == ErrorKind.UNAVAILABLE


@pytest.mark.parametrize('value,finish', [({'transaction': DRAFT, 'warnings': []}, 'MAX_TOKENS'), ({}, 'STOP'), ({'transaction': None, 'warnings': []}, 'STOP')])
def test_incomplete_and_ambiguous(monkeypatch, value, finish):
    mock_output(monkeypatch, value, finish)
    with pytest.raises(DomainError):
        parse()


@pytest.mark.parametrize('failure,kind', [(HTTPError('url', 429, 'secret-provider-body', {}, None), ErrorKind.RATE_LIMITED), (HTTPError('url', 403, 'secret-provider-body', {}, None), ErrorKind.UNAVAILABLE), (URLError('secret-provider-body'), ErrorKind.UNAVAILABLE), (TimeoutError(), ErrorKind.UNAVAILABLE)])
def test_provider_errors_are_sanitized(monkeypatch, failure, kind):
    def fail(*args, **kwargs):
        raise failure
    monkeypatch.setattr('app.infrastructure.gemini.urlopen', fail)
    with pytest.raises(DomainError) as error:
        parse()
    assert error.value.kind == kind
    assert 'secret-provider-body' not in str(error.value)


def test_standalone_adapter_requires_key():
    with pytest.raises(RuntimeError, match='GEMINI_API_KEY'):
        GeminiParser('')
