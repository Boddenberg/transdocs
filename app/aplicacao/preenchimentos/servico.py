import hashlib
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from uuid import UUID, uuid4

from app.aplicacao.preenchimentos.catalogo import (
    obter_tipo_preenchimento,
    validar_categoria_fonte,
)
from app.core.configuracao import Configuracoes, obter_configuracoes
from app.core.erros import ErroConflito, ErroNaoEncontrado, ErroRequisicao
from app.dominio.arquivos import ArquivoValidado
from app.dominio.preenchimentos import (
    ArquivoDocxValidado,
    ResultadoPreenchimento,
    StatusCampoPreenchimento,
)
from app.infraestrutura.arquivos.docx import preencher_docx
from app.infraestrutura.supabase.armazenamento_preenchimentos import (
    ArmazenamentoPreenchimentos,
    obter_armazenamento_preenchimentos,
)
from app.infraestrutura.supabase.repositorio_preenchimentos import (
    RepositorioPreenchimentos,
    obter_repositorio_preenchimentos,
)


@dataclass(frozen=True, slots=True)
class FonteUploadPreenchimento:
    categoria: str
    arquivo: ArquivoValidado


class ServicoPreenchimentos:
    def __init__(
        self,
        repositorio: RepositorioPreenchimentos,
        armazenamento: ArmazenamentoPreenchimentos,
        configuracoes: Configuracoes,
    ) -> None:
        self._repositorio = repositorio
        self._armazenamento = armazenamento
        self._configuracoes = configuracoes

    def criar(
        self,
        *,
        usuario_id: UUID,
        tipo_documento: str,
        arquivo_base: ArquivoDocxValidado,
        fontes: list[FonteUploadPreenchimento],
    ) -> dict[str, Any]:
        obter_tipo_preenchimento(tipo_documento)
        self._validar_fontes(tipo_documento, fontes)
        preenchimento_id = uuid4()
        caminho_base = self._armazenamento.montar_caminho(
            usuario_id=usuario_id,
            preenchimento_id=preenchimento_id,
            grupo="minuta",
            nome_seguro=arquivo_base.nome_seguro,
        )
        caminhos_salvos: list[str] = []
        criado = False
        try:
            self._armazenamento.salvar(
                caminho_base, arquivo_base.conteudo, arquivo_base.tipo_mime
            )
            caminhos_salvos.append(caminho_base)
            self._repositorio.criar(
                {
                    "id": str(preenchimento_id),
                    "usuario_id": str(usuario_id),
                    "tipo_documento": tipo_documento,
                    "nome_minuta": arquivo_base.nome_original,
                    "caminho_minuta": caminho_base,
                    "hash_minuta": arquivo_base.hash_sha256,
                    "tamanho_minuta_bytes": arquivo_base.tamanho_bytes,
                    "status": "pendente",
                    "resultado": {},
                }
            )
            criado = True
            for fonte in fontes:
                caminho = self._salvar_fonte(
                    preenchimento_id=preenchimento_id,
                    usuario_id=usuario_id,
                    fonte=fonte,
                )
                caminhos_salvos.append(caminho)
        except Exception:
            if criado:
                self._repositorio.excluir(preenchimento_id, usuario_id)
            self._armazenamento.excluir(caminhos_salvos)
            raise
        return self.buscar(preenchimento_id, usuario_id)

    def buscar(self, preenchimento_id: UUID, usuario_id: UUID) -> dict[str, Any]:
        preenchimento = self._obter(preenchimento_id, usuario_id)
        fontes = self._repositorio.listar_fontes(preenchimento_id, usuario_id)
        return _publicar(preenchimento, fontes=fontes)

    def listar(
        self, *, usuario_id: UUID, limite: int, deslocamento: int
    ) -> list[dict[str, Any]]:
        return [
            _publicar(item)
            for item in self._repositorio.listar(
                usuario_id=usuario_id, limite=limite, deslocamento=deslocamento
            )
        ]

    def adicionar_fontes(
        self,
        *,
        preenchimento_id: UUID,
        usuario_id: UUID,
        fontes: list[FonteUploadPreenchimento],
    ) -> dict[str, Any]:
        preenchimento = self._obter(preenchimento_id, usuario_id)
        if preenchimento["status"] in {"pendente", "processando"}:
            raise ErroConflito("Aguarde a análise atual antes de adicionar novas fontes.")
        if not fontes:
            raise ErroRequisicao("Adicione ao menos um documento comprobatório.")
        self._validar_fontes(preenchimento["tipo_documento"], fontes)
        caminhos_salvos: list[str] = []
        try:
            for fonte in fontes:
                caminhos_salvos.append(
                    self._salvar_fonte(
                        preenchimento_id=preenchimento_id,
                        usuario_id=usuario_id,
                        fonte=fonte,
                    )
                )
            self._repositorio.atualizar(
                preenchimento_id,
                usuario_id,
                {
                    "status": "pendente",
                    "resultado": {},
                    "codigo_erro": None,
                    "caminho_resultado": None,
                    "nome_resultado": None,
                },
            )
        except Exception:
            self._repositorio.excluir_fontes_por_caminhos(
                usuario_id=usuario_id, caminhos=caminhos_salvos
            )
            self._armazenamento.excluir(caminhos_salvos)
            raise
        return self.buscar(preenchimento_id, usuario_id)

    def gerar(
        self,
        *,
        preenchimento_id: UUID,
        usuario_id: UUID,
        campos_incluir: list[str],
        permitir_incompleto: bool,
    ) -> dict[str, Any]:
        preenchimento = self._obter(preenchimento_id, usuario_id)
        if preenchimento["status"] in {"pendente", "processando"}:
            raise ErroConflito("A análise ainda está em andamento.")
        if preenchimento["status"].startswith("erro_"):
            raise ErroConflito("Reenvie as fontes antes de gerar o documento.")
        try:
            resultado = ResultadoPreenchimento.model_validate(preenchimento["resultado"])
        except Exception as erro:
            raise ErroConflito("O preenchimento ainda não possui uma análise válida.") from erro
        ids_selecionados = set(campos_incluir)
        if len(ids_selecionados) != len(campos_incluir):
            raise ErroRequisicao("A seleção contém campos repetidos.")
        campos_por_id = {campo.id: campo for campo in resultado.campos}
        desconhecidos = ids_selecionados - campos_por_id.keys()
        if desconhecidos:
            raise ErroRequisicao("A seleção contém campos que não pertencem à minuta.")
        invalidos = [
            campo.rotulo
            for campo in resultado.campos
            if campo.id in ids_selecionados
            and (campo.status != StatusCampoPreenchimento.ENCONTRADO or not campo.valor)
        ]
        if invalidos:
            raise ErroRequisicao(
                "Somente campos comprovados podem ser incluídos.", {"campos": invalidos}
            )
        pendentes = [
            campo.rotulo
            for campo in resultado.campos
            if campo.status != StatusCampoPreenchimento.ENCONTRADO
            or campo.id not in ids_selecionados
        ]
        if pendentes and not permitir_incompleto:
            raise ErroConflito(
                "Ainda faltam dados comprovados para gerar a versão completa."
            )

        minuta = self._armazenamento.baixar(preenchimento["caminho_minuta"])
        substituicoes = {
            campo.id: campo.valor or ""
            for campo in resultado.campos
            if campo.id in ids_selecionados
        }
        documento = preencher_docx(
            minuta,
            campos=resultado.campos,
            substituicoes=substituicoes,
        )
        nome_resultado = _nome_resultado(preenchimento["nome_minuta"])
        caminho_resultado = self._armazenamento.montar_caminho(
            usuario_id=usuario_id,
            preenchimento_id=preenchimento_id,
            grupo="resultado",
            nome_seguro=_nome_seguro(nome_resultado),
        )
        self._armazenamento.salvar(
            caminho_resultado,
            documento,
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        )
        try:
            atualizado = self._repositorio.atualizar(
                preenchimento_id,
                usuario_id,
                {
                    "status": "concluido",
                    "caminho_resultado": caminho_resultado,
                    "nome_resultado": nome_resultado,
                    "codigo_erro": None,
                },
            )
        except Exception:
            self._armazenamento.excluir([caminho_resultado])
            raise
        return _publicar(
            atualizado,
            fontes=self._repositorio.listar_fontes(preenchimento_id, usuario_id),
        )

    def criar_url_resultado(self, preenchimento_id: UUID, usuario_id: UUID) -> dict[str, Any]:
        preenchimento = self._obter(preenchimento_id, usuario_id)
        caminho = preenchimento.get("caminho_resultado")
        if not caminho:
            raise ErroConflito("Gere o documento antes de baixá-lo.")
        return {
            "url": self._armazenamento.criar_url_assinada(caminho),
            "nome_arquivo": preenchimento.get("nome_resultado") or "documento-preenchido.docx",
            "expira_em_segundos": self._configuracoes.validade_url_assinada_segundos,
        }

    def _salvar_fonte(
        self,
        *,
        preenchimento_id: UUID,
        usuario_id: UUID,
        fonte: FonteUploadPreenchimento,
    ) -> str:
        caminho = self._armazenamento.montar_caminho(
            usuario_id=usuario_id,
            preenchimento_id=preenchimento_id,
            grupo="fontes",
            nome_seguro=fonte.arquivo.nome_seguro,
        )
        self._armazenamento.salvar(
            caminho, fonte.arquivo.conteudo, fonte.arquivo.tipo_mime
        )
        try:
            self._repositorio.adicionar_fonte(
                {
                    "preenchimento_id": str(preenchimento_id),
                    "usuario_id": str(usuario_id),
                    "categoria": fonte.categoria,
                    "nome_original": fonte.arquivo.nome_original,
                    "nome_seguro": fonte.arquivo.nome_seguro,
                    "tipo_mime": fonte.arquivo.tipo_mime,
                    "tipo_arquivo": fonte.arquivo.tipo.value,
                    "tamanho_bytes": fonte.arquivo.tamanho_bytes,
                    "caminho_storage": caminho,
                    "hash_sha256": fonte.arquivo.hash_sha256,
                }
            )
        except Exception:
            self._armazenamento.excluir([caminho])
            raise
        return caminho

    def _validar_fontes(
        self, tipo_documento: str, fontes: list[FonteUploadPreenchimento]
    ) -> None:
        if len(fontes) > 20:
            raise ErroRequisicao("Envie no máximo 20 documentos comprobatórios por vez.")
        for fonte in fontes:
            validar_categoria_fonte(tipo_documento, fonte.categoria)

    def _obter(self, preenchimento_id: UUID, usuario_id: UUID) -> dict[str, Any]:
        preenchimento = self._repositorio.buscar(preenchimento_id, usuario_id)
        if not preenchimento:
            raise ErroNaoEncontrado("Preenchimento")
        return preenchimento


def _publicar(
    preenchimento: dict[str, Any], *, fontes: list[dict[str, Any]] | None = None
) -> dict[str, Any]:
    publico = dict(preenchimento)
    publico.pop("caminho_minuta", None)
    publico.pop("caminho_resultado", None)
    if fontes is not None:
        publico["fontes"] = [
            {
                chave: valor
                for chave, valor in fonte.items()
                if chave not in {"caminho_storage", "nome_seguro", "usuario_id"}
            }
            for fonte in fontes
        ]
    return publico


def _nome_resultado(nome_minuta: str) -> str:
    base = Path(nome_minuta).stem.strip() or "escritura"
    return f"{base[:160]}-preenchida.docx"


def _nome_seguro(nome: str) -> str:
    base = re.sub(r"[^a-zA-Z0-9_-]+", "-", Path(nome).stem).strip("-").lower()
    digest = hashlib.sha256(nome.encode()).hexdigest()[:8]
    return f"{(base or 'documento')[:110]}-{digest}.docx"


def obter_servico_preenchimentos() -> ServicoPreenchimentos:
    return ServicoPreenchimentos(
        obter_repositorio_preenchimentos(),
        obter_armazenamento_preenchimentos(),
        obter_configuracoes(),
    )
