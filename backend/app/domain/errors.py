from enum import Enum


class ErrorKind(Enum):
    UNAUTHORIZED = 'unauthorized'
    NOT_FOUND = 'not_found'
    CONFLICT = 'conflict'
    INVALID_INPUT = 'invalid_input'
    RATE_LIMITED = 'rate_limited'
    UNAVAILABLE = 'unavailable'


class DomainError(Exception):
    """Expected application failure; the transport chooses its HTTP status."""
    def __init__(self, kind: ErrorKind, detail: str):
        super().__init__(detail)
        self.kind = kind
        self.detail = detail
