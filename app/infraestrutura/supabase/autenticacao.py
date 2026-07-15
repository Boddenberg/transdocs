from functools import lru_cache
from typing import Any
from uuid import UUID

import httpx

from app.core.configuracao import Configuracoes, obter_configuracoes
from app.core.erros import (
    ErroAplicacao,
    ErroConfiguracao,
    ErroConflito,
    ErroNaoAutorizado,
    ErroRequisicao,
    ErroServicoExterno,
)
from app.dominio.autenticacao import UsuarioAutenticado


class AutenticacaoSupabase:
    def __init__(self, configuracoes: Configuracoes) -> None:
        self._configuracoes = configuracoes

    def cadastrar(self, *, email: str, senha: str, nome: str) -> dict[str, Any]:
        resposta = self._requisitar(
            "POST",
            "/auth/v1/signup",
            json={"email": email, "password": senha, "data": {"nome": nome}},
        )
        return self._normalizar_resposta_de_sessao(resposta)

    def entrar(self, *, email: str, senha: str) -> dict[str, Any]:
        resposta = self._requisitar(
            "POST",
            "/auth/v1/token?grant_type=password",
            json={"email": email, "password": senha},
        )
        return self._normalizar_resposta_de_sessao(resposta)

    def solicitar_recuperacao(self, *, email: str, redirecionamento: str | None) -> None:
        corpo: dict[str, str] = {"email": email}
        if redirecionamento:
            corpo["redirect_to"] = redirecionamento
        self._requisitar("POST", "/auth/v1/recover", json=corpo)

    def sair(self, token: str) -> None:
        self._requisitar("POST", "/auth/v1/logout", token=token)

    def validar_token(self, token: str) -> UsuarioAutenticado:
        dados = self._requisitar("GET", "/auth/v1/user", token=token)
        identificador = dados.get("id")
        if not identificador:
            raise ErroNaoAutorizado()
        try:
            usuario_id = UUID(str(identificador))
        except ValueError as erro:
            raise ErroNaoAutorizado() from erro
        return UsuarioAutenticado(id=usuario_id, email=dados.get("email"))

    def _requisitar(
        self,
        metodo: str,
        caminho: str,
        *,
        json: dict[str, Any] | None = None,
        token: str | None = None,
    ) -> dict[str, Any]:
        self._validar_configuracao()
        cabecalhos = {
            "apikey": self._configuracoes.supabase_anon_key,
            "Content-Type": "application/json",
        }
        if token:
            cabecalhos["Authorization"] = f"Bearer {token}"
        try:
            resposta = httpx.request(
                metodo,
                f"{self._configuracoes.supabase_url.rstrip('/')}{caminho}",
                headers=cabecalhos,
                json=json,
                timeout=12,
            )
        except httpx.HTTPError as erro:
            raise ErroServicoExterno(
                "Supabase Auth", "A autenticação está temporariamente indisponível."
            ) from erro
        if resposta.status_code >= 400:
            self._traduzir_erro(resposta)
        if not resposta.content:
            return {}
        try:
            return resposta.json()
        except ValueError as erro:
            raise ErroServicoExterno(
                "Supabase Auth", "A autenticação retornou uma resposta inválida."
            ) from erro

    def _validar_configuracao(self) -> None:
        ausentes = []
        if not self._configuracoes.supabase_url:
            ausentes.append("SUPABASE_URL")
        if not self._configuracoes.supabase_anon_key:
            ausentes.append("SUPABASE_ANON_KEY")
        if ausentes:
            raise ErroConfiguracao("Supabase Auth", ausentes)

    @staticmethod
    def _traduzir_erro(resposta: httpx.Response) -> None:
        codigo = resposta.status_code
        if codigo in {401, 403}:
            raise ErroNaoAutorizado("E-mail, senha ou sessão inválidos.")
        if codigo == 422:
            raise ErroRequisicao("Os dados de cadastro não foram aceitos.")
        if codigo == 429:
            raise ErroAplicacao(
                status=429,
                codigo="muitas_tentativas",
                mensagem="Aguarde um pouco antes de tentar novamente.",
            )
        if codigo == 400:
            try:
                texto = str(resposta.json().get("msg", "")).lower()
            except ValueError:
                texto = ""
            if "already" in texto or "registered" in texto:
                raise ErroConflito("Já existe uma conta com este e-mail.")
            raise ErroRequisicao("Não foi possível autenticar com os dados informados.")
        raise ErroServicoExterno(
            "Supabase Auth", "A autenticação está temporariamente indisponível."
        )

    @staticmethod
    def _normalizar_resposta_de_sessao(dados: dict[str, Any]) -> dict[str, Any]:
        usuario = dados.get("user") or {}
        return {
            "access_token": dados.get("access_token"),
            "refresh_token": dados.get("refresh_token"),
            "expires_in": dados.get("expires_in"),
            "token_type": dados.get("token_type") or "bearer",
            "usuario": {
                "id": usuario.get("id"),
                "email": usuario.get("email"),
                "nome": (usuario.get("user_metadata") or {}).get("nome"),
            },
            "confirmacao_email_necessaria": not bool(dados.get("access_token")),
        }


@lru_cache
def obter_autenticacao_supabase() -> AutenticacaoSupabase:
    return AutenticacaoSupabase(obter_configuracoes())

