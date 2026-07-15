from fastapi import APIRouter

from app.api.rotas.autenticacao import router as router_autenticacao

router_api = APIRouter()
router_api.include_router(router_autenticacao)
