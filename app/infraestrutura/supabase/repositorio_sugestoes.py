from typing import Any
from uuid import UUID

from app.core.erros import ErroServicoExterno
from app.infraestrutura.supabase.cliente import obter_cliente_supabase
from supabase import Client


class RepositorioSugestoes:
    def __init__(self, cliente: Client) -> None:
        self._cliente = cliente

    def criar(self, dados: dict[str, Any]) -> dict[str, Any]:
        return self._executar_um(
            lambda: self._cliente.table("sugestoes").insert(dados).execute(),
            "registrar a sugestão",
        )

    def criar_anexos(self, dados: list[dict[str, Any]]) -> list[dict[str, Any]]:
        if not dados:
            return []
        resposta = self._executar(
            lambda: self._cliente.table("sugestoes_anexos").insert(dados).execute(),
            "registrar os anexos da sugestão",
        )
        return list(resposta.data or [])

    def excluir(self, sugestao_id: UUID, usuario_id: UUID) -> None:
        self._executar(
            lambda: (
                self._cliente.table("sugestoes")
                .delete()
                .eq("id", str(sugestao_id))
                .eq("usuario_id", str(usuario_id))
                .execute()
            ),
            "desfazer o registro da sugestão",
        )

    def listar_todas(
        self,
        *,
        categoria: str | None,
        status: str | None,
        limite: int,
        deslocamento: int,
    ) -> list[dict[str, Any]]:
        consulta = self._cliente.table("sugestoes").select("*,sugestoes_anexos(*)")
        if categoria:
            consulta = consulta.eq("categoria", categoria)
        if status:
            consulta = consulta.eq("status", status)
        resposta = self._executar(
            lambda: (
                consulta.order("criado_em", desc=True)
                .range(deslocamento, deslocamento + limite - 1)
                .execute()
            ),
            "listar as sugestões",
        )
        return list(resposta.data or [])

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


def obter_repositorio_sugestoes() -> RepositorioSugestoes:
    return RepositorioSugestoes(obter_cliente_supabase())
