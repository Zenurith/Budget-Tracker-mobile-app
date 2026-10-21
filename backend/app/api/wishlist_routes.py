from fastapi import APIRouter, Depends, Query
from typing import Literal
from pydantic import BaseModel, ConfigDict, Field
from ..infrastructure import gemini_chat
from ..infrastructure.rate_limit import AuthRateLimiter
from ..domain import funding

class ChatMessage(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    role: Literal['user', 'assistant']
    text: str = Field(min_length=1, max_length=2000)


class ChatRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    message: str = Field(min_length=1, max_length=2000)
    history: list[ChatMessage] = Field(default_factory=list, max_length=6)


from . import wishlist_schemas as ws
from ..domain import wishlist, wishlist_commands as wc


def build_wishlist_router(current, repo):
    router = APIRouter()
    chat_limiter = AuthRateLimiter()

    @router.post('/wishlist/chat')
    def chat(data: ChatRequest, user=Depends(current), db=Depends(repo)):
        chat_limiter.check(user['id'])
        view = funding.availability(user, db)
        context = {k: view.get(k) for k in (
            'currency', 'usable', 'missing_inputs', 'stale_reasons', 'can_allocate')}
        context['currency'] = user['currency']
        if view['usable']:
            for key in ('free_to_allocate', 'coverage_shortfall', 'emergency_reserved',
                        'savings_reserved', 'wishlist_reserved', 'obligations_total'):
                context[key] = view.get(key)
        result = gemini_chat.reply(data.message, context, [m.model_dump() for m in data.history])
        draft = result.get('draft')
        if draft:
            # Refresh after provider latency; never derive cash from model output.
            fresh = funding.availability(user, db)
            label, reasons = wishlist.readiness(dict(draft, status='active'), 0, fresh)
            available = max(0, fresh['free_to_allocate']) if fresh['usable'] else None
            result['affordability'] = {
                'currency': user['currency'], 'readiness': label, 'reasons': reasons,
                'available_to_reserve': available,
                'funding_gap': max(0, draft['target_cost'] - available) if available is not None else None,
                'reserved': 0,
            }
        return result


    @router.get('/wishlist')
    def read(user=Depends(current), db=Depends(repo)):
        return wishlist.read(user, db)

    @router.post('/wishlist', status_code=201)
    def create(data: ws.Item, user=Depends(current), db=Depends(repo)):
        return wishlist.save(wc.Item(**data.model_dump()), user, db)

    @router.put('/wishlist/{id}')
    def update(id: str, data: ws.Item, user=Depends(current), db=Depends(repo)):
        return wishlist.save(wc.Item(**data.model_dump()), user, db, id)

    @router.delete('/wishlist/{id}')
    def delete(id: str, expected_revision: int=Query(ge=0), user=Depends(current), db=Depends(repo)):
        return wishlist.delete(id, expected_revision, user, db)

    @router.post('/wishlist/{id}/purchases')
    def purchase(id: str, data: ws.Purchase, user=Depends(current), db=Depends(repo)):
        return wishlist.purchase(id, wc.Purchase(**data.model_dump()), user, db)

    @router.post('/wishlist-purchases/{id}/reverse')
    def reverse(id: str, data: ws.Adjustment, user=Depends(current), db=Depends(repo)):
        return wishlist.adjust(id, 'reverse', wc.Adjustment(**data.model_dump()), user, db)

    @router.post('/wishlist-purchases/{id}/refund')
    def refund(id: str, data: ws.Adjustment, user=Depends(current), db=Depends(repo)):
        return wishlist.adjust(id, 'refund', wc.Adjustment(**data.model_dump()), user, db)

    return router
