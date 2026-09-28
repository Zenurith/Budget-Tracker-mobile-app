class DomainError(Exception):
    """Expected application failure, translated into HTTP only by the API layer."""
    def __init__(self, status_code: int, detail: str):
        super().__init__(detail)
        self.status_code = status_code
        self.detail = detail
