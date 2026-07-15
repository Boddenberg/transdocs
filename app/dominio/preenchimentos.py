import hashlib
import re
import zipfile
from dataclasses import dataclass
from enum import StrEnum
from io import BytesIO
from pathlib import Path
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.core.erros import ErroRequisicao

MIME_DOCX = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"


class StatusPreenchimento(StrEnum):
    PENDENTE = "pendente"
    PROCESSANDO = "processando"
    AGUARDANDO_DADOS = "aguardando_dados"
    PRONTO_PARA_GERAR = "pronto_para_gerar"
    CONCLUIDO = "concluido"
    ERRO_ARQUIVO = "erro_arquivo"
    ERRO_OPENAI = "erro_openai"
    ERRO_INTERNO = "erro_interno"


class StatusCampoPreenchimento(StrEnum):
    ENCONTRADO = "encontrado"
    AUSENTE = "ausente"
    AMBIGUO = "ambiguo"


class ModoPreenchimento(StrEnum):
    LITERAL = "literal"
    COMPOSTO = "composto"


class LocalizadorCampoDocx(BaseModel):
    model_config = ConfigDict(extra="forbid")

    parte: str
    paragrafo: int = Field(ge=0)
    inicio: int = Field(ge=0)
    fim: int = Field(ge=1)
    marcador: str


class EvidenciaCampoPreenchimento(BaseModel):
    model_config = ConfigDict(extra="forbid")

    fonte_id: str
    fonte_nome: str = Field(max_length=255)
    categoria_fonte: str = Field(max_length=80)
    pagina: int | None = Field(default=None, ge=1)
    trecho: str = Field(max_length=1200)


class CampoPreenchimento(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str
    rotulo: str
    marcador: str
    contexto: str
    status: StatusCampoPreenchimento
    valor: str | None = Field(default=None, max_length=8000)
    valor_original: str | None = Field(default=None, max_length=8000)
    editado_pelo_usuario: bool = False
    modo_preenchimento: ModoPreenchimento = ModoPreenchimento.LITERAL
    evidencias: list[EvidenciaCampoPreenchimento] = Field(
        default_factory=list, max_length=20
    )
    fonte_id: str | None = None
    fonte_nome: str | None = Field(default=None, max_length=255)
    categoria_fonte: str | None = Field(default=None, max_length=80)
    pagina: int | None = Field(default=None, ge=1)
    trecho: str | None = Field(default=None, max_length=1200)
    confianca: float = Field(default=0, ge=0, le=1)
    autoaplicavel: bool = False
    justificativa: str = Field(default="", max_length=800)
    localizador: LocalizadorCampoDocx

    @field_validator(
        "valor",
        "valor_original",
        "trecho",
        "fonte_id",
        "fonte_nome",
        "categoria_fonte",
    )
    @classmethod
    def limpar_opcional(cls, valor: Any) -> Any:
        if isinstance(valor, str):
            return valor.strip() or None
        return valor


class ResultadoPreenchimento(BaseModel):
    model_config = ConfigDict(extra="forbid")

    tipo_documento: str
    campos: list[CampoPreenchimento] = Field(default_factory=list)
    alertas: list[str] = Field(default_factory=list)
    total_campos: int = Field(ge=0)
    total_encontrados: int = Field(ge=0)
    total_pendentes: int = Field(ge=0)

    @classmethod
    def criar(
        cls,
        *,
        tipo_documento: str,
        campos: list[CampoPreenchimento],
        alertas: list[str] | None = None,
    ) -> "ResultadoPreenchimento":
        encontrados = sum(campo.status == StatusCampoPreenchimento.ENCONTRADO for campo in campos)
        return cls(
            tipo_documento=tipo_documento,
            campos=campos,
            alertas=alertas or [],
            total_campos=len(campos),
            total_encontrados=encontrados,
            total_pendentes=len(campos) - encontrados,
        )


@dataclass(frozen=True, slots=True)
class ArquivoDocxValidado:
    conteudo: bytes
    nome_original: str
    nome_seguro: str
    tipo_mime: str
    hash_sha256: str

    @property
    def tamanho_bytes(self) -> int:
        return len(self.conteudo)


def validar_arquivo_docx(
    *, conteudo: bytes, nome: str | None, tipo_mime: str | None, limite_bytes: int
) -> ArquivoDocxValidado:
    if not conteudo:
        raise ErroRequisicao("A minuta enviada está vazia.")
    if len(conteudo) > limite_bytes:
        raise ErroRequisicao(
            "A minuta excede o limite permitido.", {"limite_bytes": limite_bytes}
        )
    nome_original = Path(nome or "minuta.docx").name[:255]
    if Path(nome_original).suffix.casefold() != ".docx":
        raise ErroRequisicao("Envie a minuta no formato DOCX.")
    mime = (tipo_mime or "").split(";", 1)[0].strip().lower()
    if mime not in {MIME_DOCX, "application/zip", "application/octet-stream", ""}:
        raise ErroRequisicao("O tipo do arquivo não corresponde a uma minuta DOCX.")
    try:
        with zipfile.ZipFile(BytesIO(conteudo)) as pacote:
            nomes = set(pacote.namelist())
            if "[Content_Types].xml" not in nomes or "word/document.xml" not in nomes:
                raise ErroRequisicao("O arquivo não contém um documento Word válido.")
            pacote.read("word/document.xml")
    except ErroRequisicao:
        raise
    except (zipfile.BadZipFile, KeyError, OSError) as erro:
        raise ErroRequisicao("Não foi possível abrir a minuta DOCX.") from erro

    base = re.sub(r"[^a-zA-Z0-9_-]+", "-", Path(nome_original).stem).strip("-").lower()
    return ArquivoDocxValidado(
        conteudo=conteudo,
        nome_original=nome_original,
        nome_seguro=f"{(base or 'minuta')[:120]}.docx",
        tipo_mime=MIME_DOCX,
        hash_sha256=hashlib.sha256(conteudo).hexdigest(),
    )
