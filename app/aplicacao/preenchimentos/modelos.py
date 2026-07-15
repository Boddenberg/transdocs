import hashlib
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from uuid import UUID, uuid4

from app.aplicacao.preenchimentos.catalogo import (
    TIPO_ESCRITURA_VENDA_COMPRA,
    obter_tipo_preenchimento,
)
from app.core.configuracao import Configuracoes, obter_configuracoes
from app.core.erros import ErroNaoEncontrado, ErroRequisicao
from app.dominio.preenchimentos import ArquivoDocxValidado, validar_arquivo_docx
from app.infraestrutura.arquivos.docx import analisar_docx, corresponde_escritura_venda_compra
from app.infraestrutura.supabase.armazenamento_preenchimentos import (
    ArmazenamentoPreenchimentos,
    obter_armazenamento_preenchimentos,
)
from app.infraestrutura.supabase.repositorio_preenchimentos import (
    RepositorioPreenchimentos,
    obter_repositorio_preenchimentos,
)

MODELO_SISTEMA_ESCRITURA_ID = "sistema:escritura_venda_compra_estruturada_v1"
_CAMINHO_MODELO_SISTEMA = (
    Path(__file__).resolve().parents[2]
    / "recursos"
    / "modelos"
    / "escritura_venda_compra_estruturada.docx"
)


@dataclass(frozen=True, slots=True)
class ModeloResolvido:
    id: str
    nome: str
    arquivo: ArquivoDocxValidado


class ServicoModelosPreenchimento:
    def __init__(
        self,
        repositorio: RepositorioPreenchimentos,
        armazenamento: ArmazenamentoPreenchimentos,
        configuracoes: Configuracoes,
    ) -> None:
        self._repositorio = repositorio
        self._armazenamento = armazenamento
        self._configuracoes = configuracoes

    def listar(
        self, *, usuario_id: UUID, tipo_documento: str | None = None
    ) -> list[dict[str, Any]]:
        if tipo_documento:
            obter_tipo_preenchimento(tipo_documento)
        modelos: list[dict[str, Any]] = []
        if tipo_documento in {None, TIPO_ESCRITURA_VENDA_COMPRA}:
            modelos.append(self._modelo_sistema_publico())
        modelos.extend(
            _publicar_modelo(item)
            for item in self._repositorio.listar_modelos(
                usuario_id=usuario_id,
                tipo_documento=tipo_documento,
            )
        )
        return modelos

    def criar(
        self,
        *,
        usuario_id: UUID,
        tipo_documento: str,
        nome: str,
        descricao: str,
        arquivo: ArquivoDocxValidado,
    ) -> dict[str, Any]:
        obter_tipo_preenchimento(tipo_documento)
        nome = _limpar_texto(nome, campo="nome", limite=120, obrigatorio=True)
        descricao = _limpar_texto(
            descricao, campo="descrição", limite=400, obrigatorio=False
        )
        analise = analisar_docx(arquivo.conteudo)
        if (
            tipo_documento == TIPO_ESCRITURA_VENDA_COMPRA
            and not corresponde_escritura_venda_compra(analise)
        ):
            raise ErroRequisicao(
                "O modelo não corresponde a uma escritura pública de venda e compra."
            )
        total_blocos = sum(
            campo.marcador.strip().upper().startswith("[PREENCHER:")
            or campo.marcador.strip().upper().startswith("[CAMPO:")
            for campo in analise.campos
        )
        if not total_blocos:
            raise ErroRequisicao(
                "O modelo reutilizável precisa ter ao menos um marcador "
                "[PREENCHER:NOME_DO_BLOCO] ou [CAMPO:NOME_DO_CAMPO]."
            )

        modelo_id = uuid4()
        caminho = self._armazenamento.montar_caminho(
            usuario_id=usuario_id,
            preenchimento_id=modelo_id,
            grupo="modelos",
            nome_seguro=arquivo.nome_seguro,
        )
        self._armazenamento.salvar(caminho, arquivo.conteudo, arquivo.tipo_mime)
        try:
            criado = self._repositorio.criar_modelo(
                {
                    "id": str(modelo_id),
                    "usuario_id": str(usuario_id),
                    "tipo_documento": tipo_documento,
                    "nome": nome,
                    "descricao": descricao,
                    "nome_arquivo": arquivo.nome_original,
                    "caminho_storage": caminho,
                    "hash_sha256": arquivo.hash_sha256,
                    "tamanho_bytes": arquivo.tamanho_bytes,
                    "total_campos": len(analise.campos),
                    "total_blocos": total_blocos,
                }
            )
        except Exception:
            self._armazenamento.excluir([caminho])
            raise
        return _publicar_modelo(criado)

    def resolver(self, *, usuario_id: UUID, modelo_id: str) -> ModeloResolvido:
        if modelo_id == MODELO_SISTEMA_ESCRITURA_ID:
            conteudo = _CAMINHO_MODELO_SISTEMA.read_bytes()
            return ModeloResolvido(
                id=MODELO_SISTEMA_ESCRITURA_ID,
                nome="Escritura de venda e compra — modelo estruturado",
                arquivo=validar_arquivo_docx(
                    conteudo=conteudo,
                    nome="escritura-venda-compra-modelo-estruturado.docx",
                    tipo_mime=None,
                    limite_bytes=self._configuracoes.limite_upload_bytes,
                ),
            )
        try:
            modelo_uuid = UUID(modelo_id)
        except ValueError as erro:
            raise ErroNaoEncontrado("Modelo de preenchimento") from erro
        registro = self._repositorio.buscar_modelo(modelo_uuid, usuario_id)
        if registro is None:
            raise ErroNaoEncontrado("Modelo de preenchimento")
        conteudo = self._armazenamento.baixar(registro["caminho_storage"])
        if hashlib.sha256(conteudo).hexdigest() != registro["hash_sha256"]:
            raise ErroRequisicao("O arquivo do modelo foi alterado e não pode ser usado.")
        arquivo = validar_arquivo_docx(
            conteudo=conteudo,
            nome=registro["nome_arquivo"],
            tipo_mime=None,
            limite_bytes=self._configuracoes.limite_upload_bytes,
        )
        return ModeloResolvido(id=str(modelo_uuid), nome=registro["nome"], arquivo=arquivo)

    def excluir(self, *, usuario_id: UUID, modelo_id: UUID) -> None:
        registro = self._repositorio.buscar_modelo(modelo_id, usuario_id)
        if registro is None:
            raise ErroNaoEncontrado("Modelo de preenchimento")
        self._repositorio.excluir_modelo(modelo_id, usuario_id)
        self._armazenamento.excluir([registro["caminho_storage"]])

    def _modelo_sistema_publico(self) -> dict[str, Any]:
        conteudo = _CAMINHO_MODELO_SISTEMA.read_bytes()
        analise = analisar_docx(conteudo)
        return {
            "id": MODELO_SISTEMA_ESCRITURA_ID,
            "nome": "Escritura de venda e compra — modelo estruturado",
            "descricao": (
                "Modelo-base com qualificação das partes, imóvel, preço, pagamento, "
                "tributos, certidões, arquivamentos e encerramento."
            ),
            "tipo_documento": TIPO_ESCRITURA_VENDA_COMPRA,
            "origem": "sistema",
            "nome_arquivo": "escritura-venda-compra-modelo-estruturado.docx",
            "total_campos": len(analise.campos),
            "total_blocos": len(analise.campos),
            "criado_em": None,
        }


def _publicar_modelo(modelo: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": modelo["id"],
        "nome": modelo["nome"],
        "descricao": modelo.get("descricao", ""),
        "tipo_documento": modelo["tipo_documento"],
        "origem": "usuario",
        "nome_arquivo": modelo["nome_arquivo"],
        "total_campos": modelo["total_campos"],
        "total_blocos": modelo["total_blocos"],
        "criado_em": modelo.get("criado_em"),
    }


def _limpar_texto(valor: str, *, campo: str, limite: int, obrigatorio: bool) -> str:
    limpo = " ".join(valor.split())
    if obrigatorio and not limpo:
        raise ErroRequisicao(f"Informe o {campo} do modelo.")
    if len(limpo) > limite:
        raise ErroRequisicao(f"O {campo} do modelo excede o limite permitido.")
    return limpo


def obter_servico_modelos_preenchimento() -> ServicoModelosPreenchimento:
    return ServicoModelosPreenchimento(
        obter_repositorio_preenchimentos(),
        obter_armazenamento_preenchimentos(),
        obter_configuracoes(),
    )
