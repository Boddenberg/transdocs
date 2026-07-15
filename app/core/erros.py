import logging
from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

logger = logging.getLogger(__name__)


class ErroAplicacao(Exception):
    def __init__(
        self,
        *,
        status: int,
        codigo: str,
        mensagem: str,
        detalhes: dict[str, Any] | None = None,
    ) -> None:
        self.status = status
        self.codigo = codigo
        self.mensagem = mensagem
        self.detalhes = detalhes or {}


class ErroConfiguracao(ErroAplicacao):
    def __init__(self, servico: str, variaveis: list[str]) -> None:
        super().__init__(
            status=503,
            codigo="servico_nao_configurado",
            mensagem=f"{servico} ainda não foi configurado.",
            detalhes={"variaveis_necessarias": variaveis},
        )


class ErroRequisicao(ErroAplicacao):
    def __init__(self, mensagem: str, detalhes: dict[str, Any] | None = None) -> None:
        super().__init__(
            status=400,
            codigo="requisicao_invalida",
            mensagem=mensagem,
            detalhes=detalhes,
        )


class ErroNaoEncontrado(ErroAplicacao):
    def __init__(self, recurso: str) -> None:
        super().__init__(
            status=404,
            codigo="nao_encontrado",
            mensagem=f"{recurso} não encontrado.",
        )


class ErroConflito(ErroAplicacao):
    def __init__(self, mensagem: str) -> None:
        super().__init__(status=409, codigo="conflito", mensagem=mensagem)


class ErroServicoExterno(ErroAplicacao):
    def __init__(self, servico: str, mensagem: str) -> None:
        super().__init__(
            status=502,
            codigo="falha_servico_externo",
            mensagem=mensagem,
            detalhes={"servico": servico},
        )


def registrar_tratadores_de_erro(app: FastAPI) -> None:
    @app.exception_handler(ErroAplicacao)
    async def tratar_erro_aplicacao(_: Request, erro: ErroAplicacao) -> JSONResponse:
        return JSONResponse(
            status_code=erro.status,
            content={
                "erro": {
                    "codigo": erro.codigo,
                    "mensagem": erro.mensagem,
                    "detalhes": erro.detalhes,
                }
            },
        )

    @app.exception_handler(RequestValidationError)
    async def tratar_validacao(_: Request, __: RequestValidationError) -> JSONResponse:
        return JSONResponse(
            status_code=422,
            content={
                "erro": {
                    "codigo": "dados_invalidos",
                    "mensagem": "Revise os dados informados.",
                    "detalhes": {},
                }
            },
        )

    @app.exception_handler(Exception)
    async def tratar_erro_inesperado(requisicao: Request, erro: Exception) -> JSONResponse:
        logger.exception(
            "Erro não tratado",
            extra={
                "metodo": requisicao.method,
                "caminho": requisicao.url.path,
                "tipo_erro": type(erro).__name__,
            },
        )
        return JSONResponse(
            status_code=500,
            content={
                "erro": {
                    "codigo": "erro_interno",
                    "mensagem": "Não foi possível concluir a operação agora.",
                    "detalhes": {},
                }
            },
        )

