from typing import Any
from uuid import UUID

from app.core.erros import ErroServicoExterno
from app.infraestrutura.supabase.cliente import obter_cliente_supabase
from supabase import Client


class RepositorioDocumentos:
    def __init__(self, cliente: Client) -> None:
        self._cliente = cliente

    def criar(self, dados: dict[str, Any]) -> dict[str, Any]:
        return self._executar_um(
            lambda: self._cliente.table("documentos").insert(dados).execute(),
            "registrar o documento",
        )

    def buscar(self, documento_id: UUID, usuario_id: UUID) -> dict[str, Any] | None:
        resposta = self._executar(
            lambda: (
                self._cliente.table("documentos")
                .select("*")
                .eq("id", str(documento_id))
                .eq("usuario_id", str(usuario_id))
                .limit(1)
                .execute()
            ),
            "consultar o documento",
        )
        return _primeiro(resposta.data)

    def buscar_por_hash(self, hash_sha256: str, usuario_id: UUID) -> dict[str, Any] | None:
        resposta = self._executar(
            lambda: (
                self._cliente.table("documentos")
                .select("*")
                .eq("hash_sha256", hash_sha256)
                .eq("usuario_id", str(usuario_id))
                .limit(1)
                .execute()
            ),
            "verificar o arquivo",
        )
        return _primeiro(resposta.data)

    def listar(
        self,
        *,
        usuario_id: UUID,
        busca: str | None,
        status: str | None,
        limite: int,
        deslocamento: int,
    ) -> list[dict[str, Any]]:
        consulta = self._cliente.table("documentos").select("*").eq("usuario_id", str(usuario_id))
        if busca:
            consulta = consulta.ilike("nome_original", f"%{_limpar_busca(busca)}%")
        if status:
            consulta = consulta.eq("status", status)
        resposta = self._executar(
            lambda: (
                consulta.order("criado_em", desc=True)
                .range(deslocamento, deslocamento + limite - 1)
                .execute()
            ),
            "listar os documentos",
        )
        return list(resposta.data or [])

    def atualizar(
        self, documento_id: UUID, usuario_id: UUID, dados: dict[str, Any]
    ) -> dict[str, Any]:
        return self._executar_um(
            lambda: (
                self._cliente.table("documentos")
                .update(dados)
                .eq("id", str(documento_id))
                .eq("usuario_id", str(usuario_id))
                .execute()
            ),
            "atualizar o documento",
        )

    def excluir(self, documento_id: UUID, usuario_id: UUID) -> None:
        self._executar(
            lambda: (
                self._cliente.table("documentos")
                .delete()
                .eq("id", str(documento_id))
                .eq("usuario_id", str(usuario_id))
                .execute()
            ),
            "excluir o documento",
        )

    def buscar_extracao(self, documento_id: UUID, usuario_id: UUID) -> dict[str, Any] | None:
        resposta = self._executar(
            lambda: (
                self._cliente.table("extracoes_documentos")
                .select("*")
                .eq("documento_id", str(documento_id))
                .eq("usuario_id", str(usuario_id))
                .limit(1)
                .execute()
            ),
            "consultar a extração",
        )
        return _primeiro(resposta.data)

    def salvar_extracao(self, dados: dict[str, Any]) -> dict[str, Any]:
        return self._executar_um(
            lambda: (
                self._cliente.table("extracoes_documentos")
                .upsert(dados, on_conflict="documento_id")
                .execute()
            ),
            "salvar a extração",
        )

    def registrar_correcao(self, dados: dict[str, Any]) -> None:
        self._executar(
            lambda: self._cliente.table("correcoes_extracao").insert(dados).execute(),
            "registrar a correção",
        )

    def iniciar_processamento(self, dados: dict[str, Any]) -> dict[str, Any]:
        return self._executar_um(
            lambda: self._cliente.table("processamentos").insert(dados).execute(),
            "iniciar o processamento",
        )

    def concluir_processamento(self, processamento_id: UUID | str, dados: dict[str, Any]) -> None:
        self._executar(
            lambda: (
                self._cliente.table("processamentos")
                .update(dados)
                .eq("id", str(processamento_id))
                .execute()
            ),
            "concluir o processamento",
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


def _limpar_busca(valor: str) -> str:
    return valor.replace("%", "").replace("_", "").strip()[:100]


def obter_repositorio_documentos() -> RepositorioDocumentos:
    return RepositorioDocumentos(obter_cliente_supabase())
