from typing import Annotated

from fastapi import Depends, Header

from app.core.erros import ErroNaoAutorizado
from app.dominio.autenticacao import SessaoAutenticada, UsuarioAutenticado
from app.infraestrutura.supabase.autenticacao import (
    AutenticacaoSupabase,
    obter_autenticacao_supabase,
)

AutenticacaoAtual = Annotated[
    AutenticacaoSupabase, Depends(obter_autenticacao_supabase)
]


def obter_sessao_autenticada(
    autenticacao: AutenticacaoAtual,
    authorization: Annotated[str | None, Header(alias="Authorization")] = None,
) -> SessaoAutenticada:
    token = _extrair_token(authorization)
    usuario = autenticacao.validar_token(token)
    return SessaoAutenticada(usuario=usuario, token=token)


def obter_usuario_autenticado(
    sessao: Annotated[SessaoAutenticada, Depends(obter_sessao_autenticada)],
) -> UsuarioAutenticado:
    return sessao.usuario


def _extrair_token(authorization: str | None) -> str:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise ErroNaoAutorizado("Informe uma sessão para acessar esta rota.")
    token = authorization.split(" ", 1)[1].strip()
    if not token:
        raise ErroNaoAutorizado("Informe uma sessão para acessar esta rota.")
    return token


SessaoAtual = Annotated[SessaoAutenticada, Depends(obter_sessao_autenticada)]
UsuarioAtual = Annotated[UsuarioAutenticado, Depends(obter_usuario_autenticado)]
