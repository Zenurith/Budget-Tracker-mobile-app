"""Replay-safe transaction mutations with explicit optimistic conflict checks."""
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from hashlib import sha256
import json
from uuid import NAMESPACE_URL, uuid5

from . import finance
from .commands import Transaction
from .errors import DomainError, ErrorKind


@dataclass(frozen=True, kw_only=True)
class Operation:
    operation_id: str
    action: str
    transaction_id: str | None = None
    expected_version: str | None = None
    transaction: Transaction | None = None


def apply(data: Operation, user, db):
    if data.action not in ('create', 'update', 'delete'):
        raise DomainError(ErrorKind.INVALID_INPUT, 'Choose a supported transaction action.')
    creating, deleting = data.action == 'create', data.action == 'delete'
    if ((creating and (data.transaction_id or data.expected_version))
            or (not creating and (not data.transaction_id or not data.expected_version))
            or (deleting and data.transaction is not None)
            or (not deleting and data.transaction is None)):
        raise DomainError(ErrorKind.INVALID_INPUT, 'Include the reviewed transaction version for edits and deletions.')
    digest = sha256(json.dumps(asdict(data), sort_keys=True, default=str).encode()).hexdigest()
    key = str(uuid5(NAMESPACE_URL, f"pocketwise:transaction:{user['id']}:{data.operation_id}"))
    with db.atomic(user['id']) as tx:
        if not tx.get('users', id=user['id']):
            raise DomainError(ErrorKind.UNAUTHORIZED, 'Please sign in again.')
        previous = tx.get('transaction_operations', id=key, user_id=user['id'])
        if previous:
            if previous['fingerprint'] != digest:
                raise DomainError(ErrorKind.CONFLICT, 'This operation ID was used for a different request.')
            return previous['result']
        if not creating:
            current = finance.owned('transactions', data.transaction_id, user, tx)
            if finance.transaction_view(current)['version'] != data.expected_version:
                raise DomainError(ErrorKind.CONFLICT, 'This transaction changed on the server. Review both versions before choosing which to keep.')
        if creating:
            record = finance.add_transaction(data.transaction, user, tx)
        elif deleting:
            finance.delete_transaction(data.transaction_id, user, tx)
            record = None
        else:
            record = finance.edit_transaction(data.transaction_id, data.transaction, user, tx)
        result = {'operation_id': data.operation_id, 'action': data.action,
                  'transaction': finance.transaction_view(record) if record else None}
        tx.put('transaction_operations', dict(id=key, user_id=user['id'], fingerprint=digest,
                                             result=result, created_at=datetime.now(timezone.utc).isoformat()))
        return result
