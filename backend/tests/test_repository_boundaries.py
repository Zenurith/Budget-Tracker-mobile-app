from unittest.mock import Mock

import pytest
from pymongo.errors import DuplicateKeyError

from app.domain.ports import DuplicateRecordError
from app.repositories.documents import LocalRepository, MongoRepository


def test_sqlite_duplicate_is_translated_and_rolled_back():
    repo = LocalRepository(':memory:')
    try:
        first = {'id': 'first', 'email': 'alex@example.com'}
        repo.put('users', first)
        with pytest.raises(DuplicateRecordError):
            repo.put('users', {'id': 'second', 'email': first['email']})
        assert repo.find('users') == [first]
        repo.put('users', {'id': 'second', 'email': 'other@example.com'})
        assert len(repo.find('users')) == 2
    finally:
        repo.close()


def test_mongo_duplicate_is_translated_without_masking_other_errors():
    # Adapter contract test only: no MongoDB integration is claimed.
    repo = MongoRepository.__new__(MongoRepository)
    collection = Mock()
    repo.db = {'users': collection}
    collection.replace_one.side_effect = DuplicateKeyError('duplicate')
    with pytest.raises(DuplicateRecordError):
        repo.put('users', {'id': 'first'})
    collection.replace_one.side_effect = RuntimeError('unavailable')
    with pytest.raises(RuntimeError, match='unavailable'):
        repo.put('users', {'id': 'first'})
