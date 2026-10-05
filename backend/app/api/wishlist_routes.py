from fastapi import APIRouter, Depends, Query
from . import wishlist_schemas as ws
from ..domain import wishlist, wishlist_commands as wc


def build_wishlist_router(current, repo):
    router = APIRouter()

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
