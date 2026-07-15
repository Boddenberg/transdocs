from typing import Any
from uuid import UUID

from app.core.erros import ErroServicoExterno
from app.infraestrutura.supabase.cliente import obter_cliente_supabase
from supabase import Client


class RepositorioPreenchimentos:
    def __init__(self, cliente: Client) -> None:
        self._cliente = cliente

    def criar(self, dados: dict[str, Any]) -> dict[str, Any]:
        return self._executar_um(
            lambda: self._cliente.table("preenchimentos").insert(dados).execute(),
            "criar o preenchimento",
        )

    def buscar(self, preenchimento_id: UUID, usuario_id: UUID) -> dict[str, Any] | None:
        resposta = self._executar(
            lambda: (
                self._cliente.table("preenchimentos")
                .select("*")
                .eq("id", str(preenchimento_id))
                .eq("usuario_id", str(usuario_id))
                .limit(1)
                .execute()
            ),
            "consultar o preenchimento",
        )
        return _primeiro(resposta.data)

    def listar(
        self, *, usuario_id: UUID, limite: int, deslocamento: int
    ) -> list[dict[str, Any]]:
        resposta = self._executar(
            lambda: (
                self._cliente.table("preenchimentos")
                .select("*")
                .eq("usuario_id", str(usuario_id))
                .order("criado_em", desc=True)
                .range(deslocamento, deslocamento + limite - 1)
                .execute()
            ),
            "listar os preenchimentos",
        )
        return list(resposta.data or [])

    def atualizar(
        self, preenchimento_id: UUID, usuario_id: UUID, dados: dict[str, Any]
    ) -> dict[str, Any]:
        return self._executar_um(
            lambda: (
                self._cliente.table("preenchimentos")
                .update(dados)
                .eq("id", str(preenchimento_id))
                .eq("usuario_id", str(usuario_id))
                .execute()
            ),
            "atualizar o preenchimento",
        )

    def reivindicar(
        self, preenchimento_id: UUID, usuario_id: UUID
    ) -> dict[str, Any] | None:
        resposta = self._executar(
            lambda: (
                self._cliente.table("preenchimentos")
                .update({"status": "processando", "codigo_erro": None})
                .eq("id", str(preenchimento_id))
                .eq("usuario_id", str(usuario_id))
                .eq("status", "pendente")
                .execute()
            ),
            "iniciar o preenchimento",
        )
        return _primeiro(resposta.data)

    def adicionar_fonte(self, dados: dict[str, Any]) -> dict[str, Any]:
        return self._executar_um(
            lambda: self._cliente.table("preenchimentos_fontes").insert(dados).execute(),
            "registrar a fonte do preenchimento",
        )

    def listar_fontes(
        self, preenchimento_id: UUID, usuario_id: UUID
    ) -> list[dict[str, Any]]:
        resposta = self._executar(
            lambda: (
                self._cliente.table("preenchimentos_fontes")
                .select("*")
                .eq("preenchimento_id", str(preenchimento_id))
                .eq("usuario_id", str(usuario_id))
                .order("criado_em")
                .execute()
            ),
            "consultar as fontes do preenchimento",
        )
        return list(resposta.data or [])

    def excluir_fontes_por_caminhos(
        self, *, usuario_id: UUID, caminhos: list[str]
    ) -> None:
        if not caminhos:
            return
        self._executar(
            lambda: (
                self._cliente.table("preenchimentos_fontes")
                .delete()
                .eq("usuario_id", str(usuario_id))
                .in_("caminho_storage", caminhos)
                .execute()
            ),
            "desfazer o registro das fontes",
        )

    def excluir(self, preenchimento_id: UUID, usuario_id: UUID) -> None:
        self._executar(
            lambda: (
                self._cliente.table("preenchimentos")
                .delete()
                .eq("id", str(preenchimento_id))
                .eq("usuario_id", str(usuario_id))
                .execute()
            ),
            "excluir o preenchimento",
        )

    def _executar(self, operacao, descricao: str):
        try:
            return operacao()
        except Exception as erro:
            raise ErroServicoExterno("Supabase", f"Não foi possível {descricao} agora.") from erro

    def _executar_um(self, operacao, descricao: str) -> dict[str, Any]:
        resposta = self._executar(operacao, descricao)
        registro = _primeiro(resposta.data)
        if registro is None:
            raise ErroServicoExterno("Supabase", f"Não foi possível {descricao} agora.")
        return registro


def _primeiro(dados: Any) -> dict[str, Any] | None:
    return dados[0] if isinstance(dados, list) and dados else None


def obter_repositorio_preenchimentos() -> RepositorioPreenchimentos:
    return RepositorioPreenchimentos(obter_cliente_supabase())
