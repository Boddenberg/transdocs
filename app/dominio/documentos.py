from datetime import datetime
from enum import StrEnum
from typing import Any
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator


class StatusDocumento(StrEnum):
    PENDENTE = "pendente"
    PROCESSANDO = "processando"
    CONCLUIDO = "concluido"
    ERRO_LEITURA = "erro_leitura"
    ERRO_ARQUIVO = "erro_arquivo"
    ERRO_OPENAI = "erro_openai"
    ERRO_INTERNO = "erro_interno"


class TipoDocumentoEnviado(StrEnum):
    PDF = "pdf"
    IMAGEM = "imagem"


class ItemExtraido(BaseModel):
    model_config = ConfigDict(extra="forbid")

    valor: str | None = None
    tipo: str
    pagina: int | None = Field(default=None, ge=1)
    trecho: str | None = Field(default=None, max_length=800)
    confianca: float = Field(ge=0, le=1)
    precisa_revisao: bool
    confirmado: bool = False
    editado: bool = False

    @field_validator("valor", "trecho", mode="before")
    @classmethod
    def limpar_texto(cls, valor: Any) -> Any:
        if isinstance(valor, str):
            texto = valor.strip()
            return texto or None
        return valor


class ParteExtraida(ItemExtraido):
    papel: str | None = Field(default=None, max_length=160)


class ResultadoExtracao(BaseModel):
    model_config = ConfigDict(extra="forbid")

    tipo_documento: str | None = None
    resumo: str | None = Field(default=None, max_length=4000)
    pessoas: list[ParteExtraida] = Field(default_factory=list)
    empresas: list[ParteExtraida] = Field(default_factory=list)
    documentos_identificados: list[ItemExtraido] = Field(default_factory=list)
    enderecos: list[ItemExtraido] = Field(default_factory=list)
    datas: list[ItemExtraido] = Field(default_factory=list)
    valores: list[ItemExtraido] = Field(default_factory=list)
    imoveis: list[ItemExtraido] = Field(default_factory=list)
    campos_adicionais: list[ItemExtraido] = Field(default_factory=list)
    alertas: list[str] = Field(default_factory=list)
    campos_nao_encontrados: list[str] = Field(default_factory=list)

    @field_validator("tipo_documento", "resumo", mode="before")
    @classmethod
    def limpar_opcional(cls, valor: Any) -> Any:
        if isinstance(valor, str):
            return valor.strip() or None
        return valor


class Documento(BaseModel):
    id: UUID
    usuario_id: UUID
    nome_original: str
    nome_seguro: str
    tipo_mime: str
    tipo_arquivo: TipoDocumentoEnviado
    tamanho_bytes: int
    total_paginas: int | None
    caminho_storage: str
    hash_sha256: str
    status: StatusDocumento
    revisado: bool
    codigo_erro: str | None = None
    criado_em: datetime
    atualizado_em: datetime
    ultima_alteracao_em: datetime


class ExtracaoPersistida(BaseModel):
    documento_id: UUID
    resultado: ResultadoExtracao
    modelo_ia: str | None = None
    criado_em: datetime
    atualizado_em: datetime


def grupos_do_resultado() -> tuple[str, ...]:
    return (
        "pessoas",
        "empresas",
        "documentos_identificados",
        "enderecos",
        "datas",
        "valores",
        "imoveis",
        "campos_adicionais",
    )
