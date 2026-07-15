import secrets
from typing import Annotated, Any

from fastapi import APIRouter, File, Form, Header, Query, UploadFile

from app.api.dependencias import UsuarioAtual
from app.aplicacao.sugestoes.servico import obter_servico_sugestoes
from app.core.configuracao import obter_configuracoes
from app.core.erros import ErroConfiguracao, ErroProibido, ErroRequisicao
from app.dominio.sugestoes import (
    AnexoSugestao,
    CategoriaSugestao,
    StatusSugestao,
    validar_anexo_sugestao,
)

router = APIRouter(prefix="/sugestoes", tags=["sugestões"])


@router.post("", status_code=201)
async def enviar_sugestao(
    usuario: UsuarioAtual,
    categoria: Annotated[CategoriaSugestao, Form()],
    mensagem: Annotated[str, Form(min_length=3, max_length=5000)],
    pagina_origem: Annotated[str | None, Form(max_length=500)] = None,
    anexos: Annotated[list[UploadFile] | None, File()] = None,
) -> dict[str, Any]:
    arquivos = anexos or []
    if len(arquivos) > 3:
        raise ErroRequisicao("Envie no máximo 3 imagens por mensagem.")
    configuracoes = obter_configuracoes()
    validados: list[AnexoSugestao] = []
    for arquivo in arquivos:
        conteudo = await _ler_com_limite(arquivo, configuracoes.limite_anexo_sugestao_bytes)
        validados.append(
            validar_anexo_sugestao(
                conteudo=conteudo,
                nome=arquivo.filename,
                tipo_mime=arquivo.content_type,
                limite_bytes=configuracoes.limite_anexo_sugestao_bytes,
            )
        )
    return obter_servico_sugestoes().registrar(
        usuario_id=usuario.id,
        usuario_email=usuario.email,
        categoria=categoria,
        mensagem=mensagem,
        pagina_origem=pagina_origem,
        anexos=validados,
    )


@router.get("")
def listar_todas_sugestoes(
    categoria: CategoriaSugestao | None = None,
    status: StatusSugestao | None = None,
    limite: Annotated[int, Query(ge=1, le=200)] = 100,
    deslocamento: Annotated[int, Query(ge=0)] = 0,
    x_admin_key: Annotated[str | None, Header(alias="X-Admin-Key")] = None,
) -> dict[str, Any]:
    _exigir_chave_admin(x_admin_key)
    return obter_servico_sugestoes().listar_todas(
        categoria=categoria,
        status=status,
        limite=limite,
        deslocamento=deslocamento,
    )


def _exigir_chave_admin(chave_informada: str | None) -> None:
    chave_configurada = obter_configuracoes().sugestoes_admin_key
    if not chave_configurada:
        raise ErroConfiguracao("Consulta administrativa de sugestões", ["SUGGESTIONS_ADMIN_KEY"])
    if not chave_informada or not secrets.compare_digest(chave_informada, chave_configurada):
        raise ErroProibido("Chave administrativa inválida.")


async def _ler_com_limite(arquivo: UploadFile, limite: int) -> bytes:
    conteudo = bytearray()
    while bloco := await arquivo.read(1024 * 1024):
        conteudo.extend(bloco)
        if len(conteudo) > limite:
            return bytes(conteudo)
    return bytes(conteudo)
