import logging
from time import perf_counter
from uuid import uuid4

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware

from app.api.router import router_api
from app.core.configuracao import obter_configuracoes
from app.core.erros import registrar_tratadores_de_erro
from app.core.observabilidade import configurar_logs

configurar_logs()
logger = logging.getLogger(__name__)


def criar_aplicacao() -> FastAPI:
    configuracoes = obter_configuracoes()
    app = FastAPI(
        title=configuracoes.nome_aplicacao,
        version="0.1.0",
        description="Leitura assistida de documentos com conferência humana.",
    )
    app.add_middleware(
        CORSMiddleware,
        allow_origins=configuracoes.origens_cors or ["http://localhost:3000"],
        allow_credentials=True,
        allow_methods=["GET", "POST", "PATCH", "DELETE", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type", "X-Request-ID"],
        expose_headers=["X-Request-ID"],
    )
    registrar_tratadores_de_erro(app)

    @app.middleware("http")
    async def registrar_requisicao(requisicao: Request, chamar_proximo):
        inicio = perf_counter()
        identificador = requisicao.headers.get("X-Request-ID") or str(uuid4())
        resposta = await chamar_proximo(requisicao)
        resposta.headers["X-Request-ID"] = identificador
        logger.info(
            "Requisição concluída",
            extra={
                "metodo": requisicao.method,
                "caminho": requisicao.url.path,
                "status": resposta.status_code,
                "duracao_ms": round((perf_counter() - inicio) * 1000, 2),
            },
        )
        return resposta

    app.include_router(router_api, prefix=configuracoes.prefixo_api)

    @app.get("/health", tags=["saúde"])
    def saude() -> dict[str, object]:
        return {
            "status": "ok",
            "aplicacao": configuracoes.nome_aplicacao,
            "ambiente": configuracoes.ambiente,
            "supabase_configurado": configuracoes.supabase_configurado,
            "openai_configurada": configuracoes.openai_configurada,
        }

    return app


app = criar_aplicacao()
