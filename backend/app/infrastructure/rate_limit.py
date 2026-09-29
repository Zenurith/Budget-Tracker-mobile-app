import time
from collections import defaultdict, deque
from threading import Lock
from ..domain.errors import DomainError, ErrorKind

class AuthRateLimiter:
    def __init__(self):
        self.attempts = defaultdict(deque)
        self.lock = Lock()

    def check(self, key):
        now = time.monotonic()
        with self.lock:
            for expired in list(self.attempts):
                if not self.attempts[expired] or self.attempts[expired][-1] < now - 60:
                    del self.attempts[expired]
            history = self.attempts[key]
            while history and history[0] < now - 60:
                history.popleft()
            if len(history) >= 20:
                raise DomainError(ErrorKind.RATE_LIMITED, 'Too many attempts. Please try again in a minute.')
            history.append(now)
