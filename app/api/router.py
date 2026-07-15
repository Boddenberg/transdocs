from fastapi import APIRouter

from app.api.rotas.autenticacao import router as router_autenticacao
from app.api.rotas.documentos import router as router_documentos
from app.api.rotas.preenchimentos import router as router_preenchimentos
from app.api.rotas.sugestoes import router as router_sugestoes

router_api = APIRouter()
router_api.include_router(router_autenticacao)
router_api.include_router(router_documentos)
router_api.include_router(router_preenchimentos)
router_api.include_router(router_sugestoes)
