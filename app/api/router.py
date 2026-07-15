from fastapi import APIRouter

from app.api.rotas.autenticacao import router as router_autenticacao
from app.api.rotas.documentos import router as router_documentos

router_api = APIRouter()
router_api.include_router(router_autenticacao)
router_api.include_router(router_documentos)
