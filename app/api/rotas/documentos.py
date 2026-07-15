from typing import Annotated, Any
from uuid import UUID

from fastapi import APIRouter, BackgroundTasks, File, Form, Query, UploadFile
from pydantic import BaseModel, Field, model_validator

from app.api.dependencias import UsuarioAtual
from app.aplicacao.documentos.processador import obter_processador_documento
from app.aplicacao.documentos.servico import obter_servico_documentos
from app.core.configuracao import obter_configuracoes
from app.dominio.arquivos import validar_arquivo
from app.dominio.documentos import StatusDocumento

router = APIRouter(prefix="/documentos", tags=["documentos"])


class RevisaoDocumento(BaseModel):
    revisado: bool = True


class CorrecaoCampo(BaseModel):
    grupo: str = Field(max_length=80)
    indice: int = Field(ge=0)
    valor: str | None = Field(default=None, max_length=4000)
    confirmado: bool | None = None

    @model_validator(mode="after")
    def exigir_alteracao(self) -> "CorrecaoCampo":
        if "valor" not in self.model_fields_set and self.confirmado is None:
            raise ValueError("informe valor ou confirmado")
        return self


@router.post("", status_code=202)
async def enviar_documento(
    usuario: UsuarioAtual,
    tarefas: BackgroundTasks,
    arquivo: Annotated[UploadFile, File(description="PDF, JPG, PNG ou WEBP")],
    somente_primeira_pagina: Annotated[bool, Form()] = False,
) -> dict[str, Any]:
    configuracoes = obter_configuracoes()
    conteudo = await _ler_com_limite(arquivo, configuracoes.limite_upload_bytes)
    validado = validar_arquivo(
        conteudo=conteudo,
        nome=arquivo.filename,
        tipo_mime=arquivo.content_type,
        limite_bytes=configuracoes.limite_upload_bytes,
    )
    documento = obter_servico_documentos().registrar_upload(
        validado,
        usuario.id,
        somente_primeira_pagina=somente_primeira_pagina,
    )
    tarefas.add_task(
        obter_processador_documento().processar,
        UUID(documento["id"]),
        usuario.id,
    )
    return documento


@router.get("")
def listar_documentos(
    usuario: UsuarioAtual,
    busca: Annotated[str | None, Query(max_length=100)] = None,
    status: StatusDocumento | None = None,
    limite: Annotated[int, Query(ge=1, le=100)] = 50,
    deslocamento: Annotated[int, Query(ge=0)] = 0,
) -> list[dict[str, Any]]:
    return obter_servico_documentos().listar(
        usuario_id=usuario.id,
        busca=busca,
        status=status.value if status else None,
        limite=limite,
        deslocamento=deslocamento,
    )


@router.get("/{documento_id}")
def buscar_documento(documento_id: UUID, usuario: UsuarioAtual) -> dict[str, Any]:
    return obter_servico_documentos().buscar_com_extracao(documento_id, usuario.id)


@router.get("/{documento_id}/resultado")
def buscar_resultado(documento_id: UUID, usuario: UsuarioAtual) -> dict[str, Any]:
    return obter_servico_documentos().buscar_resultado(documento_id, usuario.id)


@router.get("/{documento_id}/arquivo")
def criar_url_documento(documento_id: UUID, usuario: UsuarioAtual) -> dict[str, Any]:
    return obter_servico_documentos().criar_url_assinada(documento_id, usuario.id)


@router.patch("/{documento_id}/revisao")
def revisar_documento(
    documento_id: UUID, dados: RevisaoDocumento, usuario: UsuarioAtual
) -> dict[str, Any]:
    return obter_servico_documentos().marcar_revisado(documento_id, usuario.id, dados.revisado)


@router.patch("/{documento_id}/resultado")
def corrigir_resultado(
    documento_id: UUID, dados: CorrecaoCampo, usuario: UsuarioAtual
) -> dict[str, Any]:
    return obter_servico_documentos().corrigir_campo(
        documento_id=documento_id,
        usuario_id=usuario.id,
        grupo=dados.grupo,
        indice=dados.indice,
        valor_informado="valor" in dados.model_fields_set,
        valor=dados.valor,
        confirmado=dados.confirmado,
    )


@router.post("/{documento_id}/reprocessar", status_code=202)
def reprocessar_documento(
    documento_id: UUID,
    usuario: UsuarioAtual,
    tarefas: BackgroundTasks,
) -> dict[str, Any]:
    documento = obter_servico_documentos().preparar_reprocessamento(documento_id, usuario.id)
    tarefas.add_task(obter_processador_documento().processar, documento_id, usuario.id)
    return documento


@router.delete("/{documento_id}", status_code=204)
def excluir_documento(documento_id: UUID, usuario: UsuarioAtual) -> None:
    obter_servico_documentos().excluir(documento_id, usuario.id)


async def _ler_com_limite(arquivo: UploadFile, limite: int) -> bytes:
    conteudo = bytearray()
    while bloco := await arquivo.read(1024 * 1024):
        conteudo.extend(bloco)
        if len(conteudo) > limite:
            # A validação central fornece a mensagem e o contrato de erro.
            return bytes(conteudo)
    return bytes(conteudo)
