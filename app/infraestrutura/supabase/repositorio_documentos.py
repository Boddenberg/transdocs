import unicodedata
from typing import Any
from uuid import UUID

from app.core.erros import ErroServicoExterno
from app.infraestrutura.supabase.cliente import obter_cliente_supabase
from supabase import Client

CAMPOS_LISTAGEM = ",".join(
    (
        "id",
        "usuario_id",
        "nome_original",
        "nome_seguro",
        "tipo_mime",
        "tipo_arquivo",
        "tamanho_bytes",
        "total_paginas",
        "somente_primeira_pagina",
        "status",
        "revisado",
        "codigo_erro",
        "criado_em",
        "atualizado_em",
        "ultima_alteracao_em",
    )
)


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

    def buscar_por_hash(
        self,
        hash_sha256: str,
        usuario_id: UUID,
        *,
        somente_primeira_pagina: bool,
    ) -> dict[str, Any] | None:
        resposta = self._executar(
            lambda: (
                self._cliente.table("documentos")
                .select("*")
                .eq("hash_sha256", hash_sha256)
                .eq("usuario_id", str(usuario_id))
                .eq("somente_primeira_pagina", somente_primeira_pagina)
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
        consulta = (
            self._cliente.table("documentos")
            .select(CAMPOS_LISTAGEM)
            .eq("usuario_id", str(usuario_id))
        )
        if busca:
            termo = _limpar_busca(busca)
            if termo:
                consulta = consulta.ilike("texto_busca", f"%{termo}%")
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

    def reivindicar_processamento(
        self, documento_id: UUID, usuario_id: UUID
    ) -> dict[str, Any] | None:
        resposta = self._executar(
            lambda: (
                self._cliente.table("documentos")
                .update({"status": "processando", "codigo_erro": None})
                .eq("id", str(documento_id))
                .eq("usuario_id", str(usuario_id))
                .eq("status", "pendente")
                .execute()
            ),
            "iniciar o processamento",
        )
        return _primeiro(resposta.data)

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

    def listar_extracoes(
        self, documento_ids: list[str], usuario_id: UUID
    ) -> list[dict[str, Any]]:
        if not documento_ids:
            return []
        resposta = self._executar(
            lambda: (
                self._cliente.table("extracoes_documentos")
                .select("documento_id,resultado")
                .eq("usuario_id", str(usuario_id))
                .in_("documento_id", documento_ids)
                .execute()
            ),
            "consultar os dados principais",
        )
        return list(resposta.data or [])

    def listar_processamentos_recentes(
        self, documento_ids: list[str], usuario_id: UUID
    ) -> list[dict[str, Any]]:
        if not documento_ids:
            return []
        resposta = self._executar(
            lambda: (
                self._cliente.table("processamentos")
                .select(
                    "documento_id,tokens_entrada,tokens_saida,modelo_ia,"
                    "estrategia,concluido_em,iniciado_em"
                )
                .eq("usuario_id", str(usuario_id))
                .eq("status", "concluido")
                .in_("documento_id", documento_ids)
                .order("iniciado_em", desc=True)
                .execute()
            ),
            "consultar o consumo das análises",
        )
        return list(resposta.data or [])

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
    sem_acentos = "".join(
        caractere
        for caractere in unicodedata.normalize("NFKD", valor.casefold())
        if not unicodedata.combining(caractere)
    )
    return "".join(caractere for caractere in sem_acentos if caractere.isalnum())[:100]


def obter_repositorio_documentos() -> RepositorioDocumentos:
    return RepositorioDocumentos(obter_cliente_supabase())
