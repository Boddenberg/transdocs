import logging
from dataclasses import replace
from datetime import UTC, datetime
from uuid import UUID

from app.core.configuracao import Configuracoes, obter_configuracoes
from app.core.erros import ErroConfiguracao
from app.dominio.arquivos import ArquivoValidado, validar_arquivo
from app.dominio.documentos import TipoDocumentoEnviado
from app.dominio.falhas import FalhaLeituraDocumento, FalhaOpenAI
from app.infraestrutura.arquivos.leitor_pdf import (
    extrair_primeira_pagina_pdf,
    extrair_texto_pdf,
)
from app.infraestrutura.openai.extrator import ExtratorOpenAI, obter_extrator_openai
from app.infraestrutura.supabase.armazenamento import (
    ArmazenamentoDocumentos,
    obter_armazenamento,
)
from app.infraestrutura.supabase.repositorio_documentos import (
    RepositorioDocumentos,
    obter_repositorio_documentos,
)

logger = logging.getLogger(__name__)


class ProcessadorDocumento:
    def __init__(
        self,
        repositorio: RepositorioDocumentos,
        armazenamento: ArmazenamentoDocumentos,
        configuracoes: Configuracoes,
    ) -> None:
        self._repositorio = repositorio
        self._armazenamento = armazenamento
        self._configuracoes = configuracoes

    def processar(self, documento_id: UUID, usuario_id: UUID) -> None:
        documento = self._repositorio.reivindicar_processamento(documento_id, usuario_id)
        if not documento:
            return
        processamento = self._repositorio.iniciar_processamento(
            {
                "documento_id": str(documento_id),
                "usuario_id": str(usuario_id),
                "status": "iniciado",
            }
        )
        try:
            arquivo = self._carregar_arquivo(documento)
            extrator = obter_extrator_openai()
            resposta, total_paginas = self._extrair(
                arquivo,
                extrator,
                somente_primeira_pagina=bool(documento.get("somente_primeira_pagina")),
            )
            self._repositorio.salvar_extracao(
                {
                    "documento_id": str(documento_id),
                    "usuario_id": str(usuario_id),
                    "resultado": resposta.resultado.model_dump(mode="json"),
                    "modelo_ia": resposta.modelo,
                    "versao_schema": 1,
                }
            )
            self._repositorio.atualizar(
                documento_id,
                usuario_id,
                {
                    "status": "concluido",
                    "codigo_erro": None,
                    "total_paginas": total_paginas,
                },
            )
            self._repositorio.concluir_processamento(
                processamento["id"],
                {
                    "status": "concluido",
                    "estrategia": resposta.estrategia,
                    "modelo_ia": resposta.modelo,
                    "tokens_entrada": resposta.tokens_entrada,
                    "tokens_saida": resposta.tokens_saida,
                    "concluido_em": _agora(),
                },
            )
        except FalhaLeituraDocumento:
            self._registrar_falha(documento_id, usuario_id, processamento["id"], "erro_leitura")
        except (FalhaOpenAI, ErroConfiguracao):
            self._registrar_falha(documento_id, usuario_id, processamento["id"], "erro_openai")
        except Exception as erro:  # rede de segurança do trabalho em background
            logger.exception(
                "Falha interna no processamento",
                extra={"documento_id": str(documento_id), "tipo_erro": type(erro).__name__},
            )
            self._registrar_falha(documento_id, usuario_id, processamento["id"], "erro_interno")

    def _carregar_arquivo(self, documento: dict) -> ArquivoValidado:
        conteudo = self._armazenamento.baixar(documento["caminho_storage"])
        return validar_arquivo(
            conteudo=conteudo,
            nome=documento["nome_original"],
            tipo_mime=documento["tipo_mime"],
            limite_bytes=self._configuracoes.limite_upload_bytes,
        )

    def _extrair(
        self,
        arquivo: ArquivoValidado,
        extrator: ExtratorOpenAI,
        *,
        somente_primeira_pagina: bool,
    ):
        if arquivo.tipo == TipoDocumentoEnviado.IMAGEM:
            return extrator.extrair_de_imagem(arquivo), 1
        texto = extrair_texto_pdf(
            arquivo.conteudo,
            self._configuracoes.limite_texto_extraido,
            paginas_maximas=1 if somente_primeira_pagina else None,
        )
        if texto.possui_texto_legivel:
            return extrator.extrair_de_texto(texto.texto), texto.paginas
        arquivo_para_visao = arquivo
        if somente_primeira_pagina:
            arquivo_para_visao = replace(
                arquivo,
                conteudo=extrair_primeira_pagina_pdf(arquivo.conteudo),
            )
        return extrator.extrair_de_pdf_visual(arquivo_para_visao), texto.paginas

    def _registrar_falha(
        self,
        documento_id: UUID,
        usuario_id: UUID,
        processamento_id: UUID | str,
        codigo: str,
    ) -> None:
        try:
            self._repositorio.atualizar(
                documento_id,
                usuario_id,
                {"status": codigo, "codigo_erro": codigo},
            )
            self._repositorio.concluir_processamento(
                processamento_id,
                {"status": "erro", "codigo_erro": codigo, "concluido_em": _agora()},
            )
        except Exception as erro:
            logger.exception(
                "Falha ao persistir estado do processamento",
                extra={"documento_id": str(documento_id), "tipo_erro": type(erro).__name__},
            )


def _agora() -> str:
    return datetime.now(UTC).isoformat()


def obter_processador_documento() -> ProcessadorDocumento:
    return ProcessadorDocumento(
        obter_repositorio_documentos(),
        obter_armazenamento(),
        obter_configuracoes(),
    )
