from typing import Annotated, Any
from uuid import UUID

from fastapi import APIRouter, BackgroundTasks, File, Form, Query, UploadFile
from pydantic import BaseModel, Field
from starlette.concurrency import run_in_threadpool

from app.api.dependencias import UsuarioAtual
from app.aplicacao.preenchimentos.catalogo import listar_tipos_preenchimento
from app.aplicacao.preenchimentos.modelos import obter_servico_modelos_preenchimento
from app.aplicacao.preenchimentos.processador import obter_processador_preenchimento
from app.aplicacao.preenchimentos.servico import (
    FonteUploadPreenchimento,
    obter_servico_preenchimentos,
)
from app.core.configuracao import obter_configuracoes
from app.core.erros import ErroRequisicao, ErroServicoExterno
from app.dominio.arquivos import validar_arquivo
from app.dominio.audio import validar_audio
from app.dominio.documentos import TipoDocumentoEnviado
from app.dominio.falhas import FalhaOpenAI
from app.dominio.preenchimentos import validar_arquivo_docx
from app.infraestrutura.openai.transcritor import obter_transcritor_audio_openai

router = APIRouter(prefix="/preenchimentos", tags=["preenchimentos"])


class GeracaoPreenchimento(BaseModel):
    campos_incluir: list[str] = Field(default_factory=list, max_length=200)
    valores_campos: dict[str, str] = Field(default_factory=dict, max_length=200)
    permitir_incompleto: bool = False


class TranscricaoAudio(BaseModel):
    texto: str = Field(max_length=8000)


@router.get("/tipos")
def listar_tipos(usuario: UsuarioAtual) -> list[dict[str, Any]]:
    del usuario
    return listar_tipos_preenchimento()


@router.post("/transcrever-audio")
async def transcrever_audio(
    usuario: UsuarioAtual,
    arquivo: Annotated[UploadFile, File(description="Áudio da negociação")],
) -> TranscricaoAudio:
    del usuario
    configuracoes = obter_configuracoes()
    conteudo = await _ler_com_limite(
        arquivo,
        configuracoes.limite_analise_completa_bytes,
    )
    audio = validar_audio(
        conteudo=conteudo,
        nome=arquivo.filename,
        tipo_mime=arquivo.content_type,
        limite_bytes=configuracoes.limite_analise_completa_bytes,
    )
    try:
        texto = await run_in_threadpool(
            obter_transcritor_audio_openai().transcrever,
            audio,
        )
    except FalhaOpenAI as erro:
        raise ErroServicoExterno(
            "OpenAI",
            "Não foi possível transcrever o áudio agora. Tente novamente.",
        ) from erro
    return TranscricaoAudio(texto=texto)


@router.get("/modelos")
def listar_modelos(
    usuario: UsuarioAtual,
    tipo_documento: Annotated[str | None, Query(max_length=80)] = None,
) -> list[dict[str, Any]]:
    return obter_servico_modelos_preenchimento().listar(
        usuario_id=usuario.id,
        tipo_documento=tipo_documento,
    )


@router.post("/modelos", status_code=201)
async def criar_modelo(
    usuario: UsuarioAtual,
    tipo_documento: Annotated[str, Form(max_length=80)],
    nome: Annotated[str, Form(max_length=120)],
    arquivo: Annotated[UploadFile, File(description="Modelo DOCX estruturado")],
    descricao: Annotated[str, Form(max_length=400)] = "",
) -> dict[str, Any]:
    configuracoes = obter_configuracoes()
    conteudo = await _ler_com_limite(arquivo, configuracoes.limite_upload_bytes)
    validado = validar_arquivo_docx(
        conteudo=conteudo,
        nome=arquivo.filename,
        tipo_mime=arquivo.content_type,
        limite_bytes=configuracoes.limite_upload_bytes,
    )
    return obter_servico_modelos_preenchimento().criar(
        usuario_id=usuario.id,
        tipo_documento=tipo_documento,
        nome=nome,
        descricao=descricao,
        arquivo=validado,
    )


@router.delete("/modelos/{modelo_id}")
def excluir_modelo(modelo_id: UUID, usuario: UsuarioAtual) -> dict[str, bool]:
    obter_servico_modelos_preenchimento().excluir(
        usuario_id=usuario.id,
        modelo_id=modelo_id,
    )
    return {"excluido": True}


@router.post("", status_code=202)
async def criar_preenchimento(
    usuario: UsuarioAtual,
    tarefas: BackgroundTasks,
    tipo_documento: Annotated[str, Form(max_length=80)],
    arquivo_base: Annotated[UploadFile | None, File(description="Minuta DOCX")] = None,
    modelo_id: Annotated[str | None, Form(max_length=120)] = None,
    instrucoes_negociacao: Annotated[str, Form(max_length=8000)] = "",
    categorias_fontes: Annotated[list[str] | None, Form()] = None,
    arquivos_fontes: Annotated[list[UploadFile] | None, File()] = None,
) -> dict[str, Any]:
    configuracoes = obter_configuracoes()
    if (arquivo_base is None) == (modelo_id is None):
        raise ErroRequisicao(
            "Escolha um modelo pronto ou envie uma minuta DOCX, mas não os dois."
        )
    if modelo_id is not None:
        modelo = obter_servico_modelos_preenchimento().resolver(
            usuario_id=usuario.id,
            modelo_id=modelo_id,
        )
        base = modelo.arquivo
        modo_criacao = "documento_completo"
        modelo_referencia = modelo.id
        modelo_nome = modelo.nome
    else:
        assert arquivo_base is not None
        conteudo_base = await _ler_com_limite(
            arquivo_base, configuracoes.limite_upload_bytes
        )
        base = validar_arquivo_docx(
            conteudo=conteudo_base,
            nome=arquivo_base.filename,
            tipo_mime=arquivo_base.content_type,
            limite_bytes=configuracoes.limite_upload_bytes,
        )
        modo_criacao = "completar_minuta"
        modelo_referencia = None
        modelo_nome = None
    fontes = await _validar_fontes(
        categorias_fontes or [],
        arquivos_fontes or [],
        limite_arquivo=configuracoes.limite_upload_bytes,
        limite_imagem=configuracoes.limite_analise_completa_bytes,
        limite_total=configuracoes.limite_fontes_preenchimento_bytes,
    )
    preenchimento = obter_servico_preenchimentos().criar(
        usuario_id=usuario.id,
        tipo_documento=tipo_documento,
        arquivo_base=base,
        fontes=fontes,
        instrucoes_negociacao=instrucoes_negociacao,
        modo_criacao=modo_criacao,
        modelo_referencia=modelo_referencia,
        modelo_nome=modelo_nome,
    )
    preenchimento_id = UUID(preenchimento["id"])
    tarefas.add_task(
        obter_processador_preenchimento().processar, preenchimento_id, usuario.id
    )
    return preenchimento


@router.get("")
def listar_preenchimentos(
    usuario: UsuarioAtual,
    limite: Annotated[int, Query(ge=1, le=50)] = 20,
    deslocamento: Annotated[int, Query(ge=0)] = 0,
) -> list[dict[str, Any]]:
    return obter_servico_preenchimentos().listar(
        usuario_id=usuario.id, limite=limite, deslocamento=deslocamento
    )


@router.get("/{preenchimento_id}")
def buscar_preenchimento(
    preenchimento_id: UUID, usuario: UsuarioAtual
) -> dict[str, Any]:
    return obter_servico_preenchimentos().buscar(preenchimento_id, usuario.id)


@router.post("/{preenchimento_id}/fontes", status_code=202)
async def adicionar_fontes(
    preenchimento_id: UUID,
    usuario: UsuarioAtual,
    tarefas: BackgroundTasks,
    categorias_fontes: Annotated[list[str], Form()],
    arquivos_fontes: Annotated[list[UploadFile], File()],
) -> dict[str, Any]:
    configuracoes = obter_configuracoes()
    fontes = await _validar_fontes(
        categorias_fontes,
        arquivos_fontes,
        limite_arquivo=configuracoes.limite_upload_bytes,
        limite_imagem=configuracoes.limite_analise_completa_bytes,
        limite_total=configuracoes.limite_fontes_preenchimento_bytes,
    )
    preenchimento = obter_servico_preenchimentos().adicionar_fontes(
        preenchimento_id=preenchimento_id,
        usuario_id=usuario.id,
        fontes=fontes,
    )
    tarefas.add_task(
        obter_processador_preenchimento().processar, preenchimento_id, usuario.id
    )
    return preenchimento


@router.post("/{preenchimento_id}/gerar")
def gerar_documento(
    preenchimento_id: UUID,
    dados: GeracaoPreenchimento,
    usuario: UsuarioAtual,
) -> dict[str, Any]:
    return obter_servico_preenchimentos().gerar(
        preenchimento_id=preenchimento_id,
        usuario_id=usuario.id,
        campos_incluir=dados.campos_incluir,
        valores_campos=dados.valores_campos,
        permitir_incompleto=dados.permitir_incompleto,
    )


@router.get("/{preenchimento_id}/arquivo")
def criar_url_resultado(
    preenchimento_id: UUID, usuario: UsuarioAtual
) -> dict[str, Any]:
    return obter_servico_preenchimentos().criar_url_resultado(
        preenchimento_id, usuario.id
    )


async def _validar_fontes(
    categorias: list[str],
    arquivos: list[UploadFile],
    *,
    limite_arquivo: int,
    limite_imagem: int,
    limite_total: int,
) -> list[FonteUploadPreenchimento]:
    if len(categorias) != len(arquivos):
        raise ErroRequisicao("Cada documento comprobatório precisa de uma categoria.")
    if len(arquivos) > 20:
        raise ErroRequisicao("Envie no máximo 20 documentos comprobatórios por vez.")
    fontes: list[FonteUploadPreenchimento] = []
    tamanho_total = 0
    for categoria, arquivo in zip(categorias, arquivos, strict=True):
        conteudo = await _ler_com_limite(arquivo, limite_arquivo)
        tamanho_total += len(conteudo)
        if tamanho_total > limite_total:
            raise ErroRequisicao(
                "O conjunto de documentos comprobatórios excede o limite permitido.",
                {"limite_bytes": limite_total},
            )
        validado = validar_arquivo(
            conteudo=conteudo,
            nome=arquivo.filename,
            tipo_mime=arquivo.content_type,
            limite_bytes=limite_arquivo,
        )
        if (
            validado.tipo == TipoDocumentoEnviado.IMAGEM
            and validado.tamanho_bytes > limite_imagem
        ):
            raise ErroRequisicao(
                "Cada imagem comprobatória deve ter no máximo "
                f"{limite_imagem // (1024 * 1024)} MB."
            )
        fontes.append(
            FonteUploadPreenchimento(
                categoria=categoria,
                arquivo=validado,
            )
        )
    return fontes


async def _ler_com_limite(arquivo: UploadFile, limite: int) -> bytes:
    conteudo = bytearray()
    while bloco := await arquivo.read(1024 * 1024):
        conteudo.extend(bloco)
        if len(conteudo) > limite:
            return bytes(conteudo)
    return bytes(conteudo)
