import logging
from uuid import UUID

from app.aplicacao.preenchimentos.catalogo import TIPO_ESCRITURA_VENDA_COMPRA
from app.core.configuracao import Configuracoes, obter_configuracoes
from app.core.erros import ErroConfiguracao
from app.dominio.arquivos import validar_arquivo
from app.dominio.falhas import FalhaLeituraDocumento, FalhaOpenAI
from app.dominio.preenchimentos import ResultadoPreenchimento
from app.infraestrutura.arquivos.docx import (
    analisar_docx,
    corresponde_escritura_venda_compra,
)
from app.infraestrutura.openai.preenchedor import (
    FonteParaPreenchimento,
    obter_extrator_preenchimento_openai,
)
from app.infraestrutura.supabase.armazenamento_preenchimentos import (
    ArmazenamentoPreenchimentos,
    obter_armazenamento_preenchimentos,
)
from app.infraestrutura.supabase.repositorio_preenchimentos import (
    RepositorioPreenchimentos,
    obter_repositorio_preenchimentos,
)

logger = logging.getLogger(__name__)


class ProcessadorPreenchimento:
    def __init__(
        self,
        repositorio: RepositorioPreenchimentos,
        armazenamento: ArmazenamentoPreenchimentos,
        configuracoes: Configuracoes,
    ) -> None:
        self._repositorio = repositorio
        self._armazenamento = armazenamento
        self._configuracoes = configuracoes

    def processar(self, preenchimento_id: UUID, usuario_id: UUID) -> None:
        preenchimento = self._repositorio.reivindicar(preenchimento_id, usuario_id)
        if not preenchimento:
            return
        try:
            minuta = self._armazenamento.baixar(preenchimento["caminho_minuta"])
            analise = analisar_docx(minuta)
            self._validar_tipo(preenchimento["tipo_documento"], analise)
            if not analise.campos:
                resultado = ResultadoPreenchimento.criar(
                    tipo_documento=preenchimento["tipo_documento"],
                    campos=[],
                    alertas=[
                        "Nenhuma lacuna explícita foi encontrada; o arquivo pode ser "
                        "devolvido sem alterações."
                    ],
                )
                self._concluir(preenchimento_id, usuario_id, resultado, modelo=None)
                return
            fontes = self._carregar_fontes(preenchimento_id, usuario_id)
            fontes.extend(self._carregar_fontes_texto(preenchimento))
            resposta = obter_extrator_preenchimento_openai().analisar(
                tipo_documento=preenchimento["tipo_documento"],
                texto_minuta=analise.texto,
                campos=analise.campos,
                fontes=fontes,
                instrucoes_negociacao=preenchimento.get("instrucoes_negociacao", ""),
                modo_criacao=preenchimento.get("modo_criacao", "completar_minuta"),
            )
            self._concluir(
                preenchimento_id,
                usuario_id,
                resposta.resultado,
                modelo=resposta.modelo,
                tokens_entrada=resposta.tokens_entrada,
                tokens_saida=resposta.tokens_saida,
            )
        except FalhaLeituraDocumento:
            self._registrar_falha(preenchimento_id, usuario_id, "erro_arquivo")
        except (FalhaOpenAI, ErroConfiguracao):
            self._registrar_falha(preenchimento_id, usuario_id, "erro_openai")
        except Exception as erro:
            logger.exception(
                "Falha interna no preenchimento",
                extra={
                    "preenchimento_id": str(preenchimento_id),
                    "tipo_erro": type(erro).__name__,
                },
            )
            self._registrar_falha(preenchimento_id, usuario_id, "erro_interno")

    def _carregar_fontes(
        self, preenchimento_id: UUID, usuario_id: UUID
    ) -> list[FonteParaPreenchimento]:
        fontes: list[FonteParaPreenchimento] = []
        for registro in self._repositorio.listar_fontes(preenchimento_id, usuario_id):
            conteudo = self._armazenamento.baixar(registro["caminho_storage"])
            arquivo = validar_arquivo(
                conteudo=conteudo,
                nome=registro["nome_original"],
                tipo_mime=registro["tipo_mime"],
                limite_bytes=self._configuracoes.limite_upload_bytes,
            )
            fontes.append(
                FonteParaPreenchimento(
                    id=str(registro["id"]),
                    categoria=registro["categoria"],
                    nome=registro["nome_original"],
                    arquivo=arquivo,
                )
            )
        return fontes

    def _carregar_fontes_texto(
        self, preenchimento: dict
    ) -> list[FonteParaPreenchimento]:
        fontes: list[FonteParaPreenchimento] = []
        for indice, registro in enumerate(preenchimento.get("fontes_texto") or [], 1):
            if not isinstance(registro, dict):
                continue
            categoria = registro.get("categoria")
            nome = registro.get("nome")
            texto = registro.get("texto")
            if not all(isinstance(valor, str) and valor for valor in (categoria, nome, texto)):
                continue
            fontes.append(
                FonteParaPreenchimento(
                    id=f"texto_{indice}",
                    categoria=categoria,
                    nome=nome,
                    texto=texto,
                )
            )
        return fontes

    def _validar_tipo(self, tipo_documento: str, analise) -> None:
        if (
            tipo_documento == TIPO_ESCRITURA_VENDA_COMPRA
            and not corresponde_escritura_venda_compra(analise)
        ):
            raise FalhaLeituraDocumento(
                "A minuta não corresponde a uma escritura pública de venda e compra."
            )

    def _concluir(
        self,
        preenchimento_id: UUID,
        usuario_id: UUID,
        resultado: ResultadoPreenchimento,
        *,
        modelo: str | None,
        tokens_entrada: int | None = None,
        tokens_saida: int | None = None,
    ) -> None:
        status = "aguardando_dados" if resultado.total_pendentes else "pronto_para_gerar"
        self._repositorio.atualizar(
            preenchimento_id,
            usuario_id,
            {
                "status": status,
                "resultado": resultado.model_dump(mode="json"),
                "modelo_ia": modelo,
                "tokens_entrada": tokens_entrada,
                "tokens_saida": tokens_saida,
                "codigo_erro": None,
            },
        )

    def _registrar_falha(
        self, preenchimento_id: UUID, usuario_id: UUID, codigo: str
    ) -> None:
        try:
            self._repositorio.atualizar(
                preenchimento_id,
                usuario_id,
                {"status": codigo, "codigo_erro": codigo},
            )
        except Exception as erro:
            logger.exception(
                "Falha ao persistir erro do preenchimento",
                extra={
                    "preenchimento_id": str(preenchimento_id),
                    "tipo_erro": type(erro).__name__,
                },
            )


def obter_processador_preenchimento() -> ProcessadorPreenchimento:
    return ProcessadorPreenchimento(
        obter_repositorio_preenchimentos(),
        obter_armazenamento_preenchimentos(),
        obter_configuracoes(),
    )
