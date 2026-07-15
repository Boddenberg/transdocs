import unicodedata
from datetime import UTC, datetime
from typing import Any
from uuid import UUID, uuid4

from app.core.configuracao import Configuracoes, obter_configuracoes
from app.core.erros import ErroConflito, ErroNaoEncontrado, ErroRequisicao
from app.dominio.arquivos import ArquivoValidado
from app.dominio.custos_ia import calcular_metricas_analise
from app.dominio.documentos import (
    ResultadoExtracao,
    TipoDocumentoEnviado,
    grupos_do_resultado,
)
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

    def registrar_upload(
        self,
        arquivo: ArquivoValidado,
        usuario_id: UUID,
        *,
        somente_primeira_pagina: bool = False,
    ) -> dict[str, Any]:
        somente_primeira_pagina = bool(
            somente_primeira_pagina and arquivo.tipo == TipoDocumentoEnviado.PDF
        )
        if (
            arquivo.tipo == TipoDocumentoEnviado.IMAGEM
            and arquivo.tamanho_bytes > self._configuracoes.limite_analise_completa_bytes
        ):
            raise ErroRequisicao("Imagens podem ter no máximo 25 MB.")
        if (
            arquivo.tipo == TipoDocumentoEnviado.PDF
            and arquivo.tamanho_bytes > self._configuracoes.limite_analise_completa_bytes
            and not somente_primeira_pagina
        ):
            raise ErroRequisicao(
                "Para PDFs acima de 25 MB, marque a análise somente da primeira página."
            )

        existente = self._repositorio.buscar_por_hash(
            arquivo.hash_sha256,
            usuario_id,
            somente_primeira_pagina=somente_primeira_pagina,
        )
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
                "somente_primeira_pagina": somente_primeira_pagina,
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
        documentos = self._repositorio.listar(
            usuario_id=usuario_id,
            busca=busca,
            status=status,
            limite=limite,
            deslocamento=deslocamento,
        )
        documento_ids = [str(documento["id"]) for documento in documentos]
        extracoes = self._repositorio.listar_extracoes(documento_ids, usuario_id)
        processamentos = self._repositorio.listar_processamentos_recentes(
            documento_ids, usuario_id
        )
        extracoes_por_documento = {
            str(extracao["documento_id"]): extracao.get("resultado") or {}
            for extracao in extracoes
        }
        processamentos_por_documento: dict[str, dict[str, Any]] = {}
        for processamento in processamentos:
            processamentos_por_documento.setdefault(
                str(processamento["documento_id"]), processamento
            )

        resultado: list[dict[str, Any]] = []
        for documento in documentos:
            documento_id = str(documento["id"])
            dados_extraidos = extracoes_por_documento.get(documento_id, {})
            resultado.append(
                {
                    **documento,
                    "tipo_documento": dados_extraidos.get("tipo_documento"),
                    "dados_principais": extrair_dados_principais(dados_extraidos),
                    "analise": calcular_metricas_analise(
                        processamentos_por_documento.get(documento_id),
                        preco_entrada_usd_milhao=(
                            self._configuracoes.openai_preco_entrada_usd_milhao
                        ),
                        preco_saida_usd_milhao=(
                            self._configuracoes.openai_preco_saida_usd_milhao
                        ),
                        cotacao_usd_brl=self._configuracoes.cotacao_usd_brl,
                    ),
                }
            )
        return resultado

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


def extrair_dados_principais(resultado_bruto: dict[str, Any]) -> list[dict[str, str]]:
    try:
        resultado = ResultadoExtracao.model_validate(resultado_bruto)
    except (TypeError, ValueError):
        return []

    candidatos = (
        (resultado.pessoas, (), "Nome"),
        (resultado.documentos_identificados, ("cpf",), "CPF"),
        (resultado.documentos_identificados, ("cnpj",), "CNPJ"),
        (resultado.documentos_identificados, ("rg", "identidade"), "RG"),
        (resultado.empresas, ("razao social", "nome"), "Empresa"),
        (resultado.imoveis, ("matricula",), "Matrícula"),
    )
    principais: list[dict[str, str]] = []
    valores_usados: set[str] = set()
    for itens, tipos, rotulo in candidatos:
        item = next(
            (
                atual
                for atual in itens
                if atual.valor and _tipo_corresponde(atual.tipo, tipos)
            ),
            None,
        )
        if item and item.valor.casefold() not in valores_usados:
            principais.append({"rotulo": rotulo, "valor": item.valor})
            valores_usados.add(item.valor.casefold())
        if len(principais) == 3:
            break

    if len(principais) < 3:
        for itens in (
            resultado.documentos_identificados,
            resultado.pessoas,
            resultado.empresas,
            resultado.imoveis,
            resultado.enderecos,
            resultado.datas,
            resultado.valores,
        ):
            for item in itens:
                if not item.valor or item.valor.casefold() in valores_usados:
                    continue
                principais.append(
                    {"rotulo": _rotulo_tipo(item.tipo), "valor": item.valor}
                )
                valores_usados.add(item.valor.casefold())
                if len(principais) == 3:
                    return principais
    return principais


def _tipo_corresponde(tipo: str, opcoes: tuple[str, ...]) -> bool:
    normalizado = "".join(
        caractere
        for caractere in unicodedata.normalize("NFKD", tipo.casefold())
        if not unicodedata.combining(caractere)
    )
    normalizado = normalizado.replace("_", " ").replace("-", " ")
    return not opcoes or any(opcao in normalizado for opcao in opcoes)


def _rotulo_tipo(tipo: str) -> str:
    rotulo = tipo.replace("_", " ").replace("-", " ").strip()
    return (rotulo or "Dado").capitalize()[:40]


def obter_servico_documentos() -> ServicoDocumentos:
    return ServicoDocumentos(
        obter_repositorio_documentos(),
        obter_armazenamento(),
        obter_configuracoes(),
    )
