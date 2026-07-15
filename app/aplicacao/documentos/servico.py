from datetime import UTC, datetime
from typing import Any
from uuid import UUID, uuid4

from app.core.configuracao import Configuracoes, obter_configuracoes
from app.core.erros import ErroConflito, ErroNaoEncontrado, ErroRequisicao
from app.dominio.arquivos import ArquivoValidado
from app.dominio.documentos import ResultadoExtracao, grupos_do_resultado
from app.infraestrutura.supabase.armazenamento import (
    ArmazenamentoDocumentos,
    obter_armazenamento,
)
from app.infraestrutura.supabase.repositorio_documentos import (
    RepositorioDocumentos,
    obter_repositorio_documentos,
)


class ServicoDocumentos:
    def __init__(
        self,
        repositorio: RepositorioDocumentos,
        armazenamento: ArmazenamentoDocumentos,
        configuracoes: Configuracoes,
    ) -> None:
        self._repositorio = repositorio
        self._armazenamento = armazenamento
        self._configuracoes = configuracoes

    def registrar_upload(self, arquivo: ArquivoValidado, usuario_id: UUID) -> dict[str, Any]:
        existente = self._repositorio.buscar_por_hash(arquivo.hash_sha256, usuario_id)
        if existente:
            raise ErroConflito("Este arquivo já está no seu histórico. Abra o documento existente.")

        documento_id = uuid4()
        caminho = self._armazenamento.montar_caminho(
            usuario_id=usuario_id,
            documento_id=documento_id,
            nome_seguro=arquivo.nome_seguro,
        )
        documento = self._repositorio.criar(
            {
                "id": str(documento_id),
                "usuario_id": str(usuario_id),
                "nome_original": arquivo.nome_original,
                "nome_seguro": arquivo.nome_seguro,
                "tipo_mime": arquivo.tipo_mime,
                "tipo_arquivo": arquivo.tipo.value,
                "tamanho_bytes": arquivo.tamanho_bytes,
                "caminho_storage": caminho,
                "hash_sha256": arquivo.hash_sha256,
                "status": "pendente",
            }
        )
        try:
            self._armazenamento.salvar(caminho, arquivo)
        except Exception:
            self._repositorio.excluir(documento_id, usuario_id)
            raise
        return documento

    def listar(
        self,
        *,
        usuario_id: UUID,
        busca: str | None,
        status: str | None,
        limite: int,
        deslocamento: int,
    ) -> list[dict[str, Any]]:
        return self._repositorio.listar(
            usuario_id=usuario_id,
            busca=busca,
            status=status,
            limite=limite,
            deslocamento=deslocamento,
        )

    def buscar_com_extracao(self, documento_id: UUID, usuario_id: UUID) -> dict[str, Any]:
        documento = self._exigir_documento(documento_id, usuario_id)
        extracao = self._repositorio.buscar_extracao(documento_id, usuario_id)
        return {**documento, "extracao": extracao}

    def buscar_resultado(self, documento_id: UUID, usuario_id: UUID) -> dict[str, Any]:
        self._exigir_documento(documento_id, usuario_id)
        extracao = self._repositorio.buscar_extracao(documento_id, usuario_id)
        if not extracao:
            raise ErroNaoEncontrado("Resultado da extração")
        return extracao

    def criar_url_assinada(self, documento_id: UUID, usuario_id: UUID) -> dict[str, Any]:
        documento = self._exigir_documento(documento_id, usuario_id)
        return {
            "url": self._armazenamento.criar_url_assinada(documento["caminho_storage"]),
            "expira_em_segundos": self._configuracoes.validade_url_assinada_segundos,
        }

    def excluir(self, documento_id: UUID, usuario_id: UUID) -> None:
        documento = self._exigir_documento(documento_id, usuario_id)
        self._armazenamento.excluir(documento["caminho_storage"])
        self._repositorio.excluir(documento_id, usuario_id)

    def marcar_revisado(
        self, documento_id: UUID, usuario_id: UUID, revisado: bool
    ) -> dict[str, Any]:
        self._exigir_documento(documento_id, usuario_id)
        return self._repositorio.atualizar(
            documento_id,
            usuario_id,
            {"revisado": revisado, "ultima_alteracao_em": _agora()},
        )

    def preparar_reprocessamento(self, documento_id: UUID, usuario_id: UUID) -> dict[str, Any]:
        documento = self._exigir_documento(documento_id, usuario_id)
        if documento["status"] in {"pendente", "processando"}:
            raise ErroConflito("Este documento já está aguardando processamento.")
        return self._repositorio.atualizar(
            documento_id,
            usuario_id,
            {"status": "pendente", "codigo_erro": None, "revisado": False},
        )

    def corrigir_campo(
        self,
        *,
        documento_id: UUID,
        usuario_id: UUID,
        grupo: str,
        indice: int,
        valor_informado: bool,
        valor: str | None,
        confirmado: bool | None,
    ) -> dict[str, Any]:
        self._exigir_documento(documento_id, usuario_id)
        if grupo not in grupos_do_resultado():
            raise ErroRequisicao("Grupo de extração inválido.")
        extracao = self._repositorio.buscar_extracao(documento_id, usuario_id)
        if not extracao:
            raise ErroNaoEncontrado("Resultado da extração")

        resultado = ResultadoExtracao.model_validate(extracao["resultado"])
        itens = list(getattr(resultado, grupo))
        if indice >= len(itens):
            raise ErroRequisicao("Campo de extração inválido.")
        anterior = itens[indice]
        alteracoes: dict[str, Any] = {}
        if valor_informado:
            alteracoes["valor"] = valor.strip() if isinstance(valor, str) else None
            alteracoes["editado"] = alteracoes["valor"] != anterior.valor
            alteracoes["precisa_revisao"] = not bool(alteracoes["valor"])
        if confirmado is not None:
            alteracoes["confirmado"] = confirmado
            if confirmado:
                alteracoes["precisa_revisao"] = False
        if not alteracoes:
            raise ErroRequisicao("Informe um valor ou estado de confirmação.")

        itens[indice] = anterior.model_copy(update=alteracoes)
        resultado_atualizado = resultado.model_copy(update={grupo: itens})
        extracao_atualizada = self._repositorio.salvar_extracao(
            {
                "documento_id": str(documento_id),
                "usuario_id": str(usuario_id),
                "resultado": resultado_atualizado.model_dump(mode="json"),
                "modelo_ia": extracao.get("modelo_ia"),
                "versao_schema": extracao.get("versao_schema", 1),
            }
        )
        self._repositorio.registrar_correcao(
            {
                "documento_id": str(documento_id),
                "extracao_id": extracao_atualizada["id"],
                "usuario_id": str(usuario_id),
                "caminho_campo": f"{grupo}.{indice}",
                "valor_anterior": anterior.model_dump(mode="json"),
                "valor_novo": itens[indice].model_dump(mode="json"),
                "confirmado": itens[indice].confirmado,
            }
        )
        self._repositorio.atualizar(
            documento_id,
            usuario_id,
            {"ultima_alteracao_em": _agora(), "revisado": False},
        )
        return extracao_atualizada

    def _exigir_documento(self, documento_id: UUID, usuario_id: UUID) -> dict[str, Any]:
        documento = self._repositorio.buscar(documento_id, usuario_id)
        if not documento:
            raise ErroNaoEncontrado("Documento")
        return documento


def _agora() -> str:
    return datetime.now(UTC).isoformat()


def obter_servico_documentos() -> ServicoDocumentos:
    return ServicoDocumentos(
        obter_repositorio_documentos(),
        obter_armazenamento(),
        obter_configuracoes(),
    )
