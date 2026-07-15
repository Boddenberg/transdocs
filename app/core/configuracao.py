from decimal import Decimal
from functools import lru_cache
from typing import Annotated, Any

from pydantic import AliasChoices, Field, field_validator, model_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict


class Configuracoes(BaseSettings):
    nome_aplicacao: str = Field("ThiagoDocs API", validation_alias="APP_NAME")
    ambiente: str = Field("local", validation_alias="APP_ENV")
    prefixo_api: str = Field("/api/v1", validation_alias="API_PREFIX")
    origens_cors: Annotated[list[str], NoDecode] = Field(
        default_factory=list,
        validation_alias=AliasChoices("CORS_ORIGINS", "CORS_ORIGENS"),
    )

    supabase_url: str = Field("", validation_alias="SUPABASE_URL")
    supabase_anon_key: str = Field("", validation_alias="SUPABASE_ANON_KEY")
    supabase_service_role_key: str = Field("", validation_alias="SUPABASE_SERVICE_ROLE_KEY")
    supabase_bucket_documentos: str = Field(
        "documentos", validation_alias="SUPABASE_DOCUMENTS_BUCKET"
    )
    supabase_bucket_sugestoes: str = Field(
        "sugestoes", validation_alias="SUPABASE_SUGGESTIONS_BUCKET"
    )
    supabase_bucket_preenchimentos: str = Field(
        "preenchimentos", validation_alias="SUPABASE_FILLINGS_BUCKET"
    )
    sugestoes_admin_key: str = Field("", validation_alias="SUGGESTIONS_ADMIN_KEY")

    openai_api_key: str = Field("", validation_alias="OPENAI_API_KEY")
    openai_modelo: str = Field("gpt-5.4-mini", validation_alias="OPENAI_MODEL")
    openai_modelo_transcricao: str = Field(
        "gpt-4o-mini-transcribe",
        validation_alias="OPENAI_TRANSCRIPTION_MODEL",
    )
    openai_timeout_segundos: float = Field(90, validation_alias="OPENAI_TIMEOUT_SECONDS")
    openai_preco_entrada_usd_milhao: Decimal = Field(
        Decimal("0.75"), validation_alias="OPENAI_INPUT_USD_PER_MILLION"
    )
    openai_preco_saida_usd_milhao: Decimal = Field(
        Decimal("4.50"), validation_alias="OPENAI_OUTPUT_USD_PER_MILLION"
    )
    cotacao_usd_brl: Decimal = Field(Decimal("5.50"), validation_alias="USD_BRL_RATE")

    limite_upload_bytes: int = Field(50 * 1024 * 1024, validation_alias="MAX_UPLOAD_BYTES")
    limite_analise_completa_bytes: int = Field(
        25 * 1024 * 1024, validation_alias="MAX_FULL_ANALYSIS_BYTES"
    )
    limite_texto_extraido: int = Field(120_000, validation_alias="MAX_EXTRACTED_TEXT_CHARS")
    limite_fontes_preenchimento_bytes: int = Field(
        100 * 1024 * 1024, validation_alias="MAX_FILLING_SOURCES_BYTES"
    )
    validade_url_assinada_segundos: int = Field(300, validation_alias="SIGNED_URL_TTL_SECONDS")
    limite_anexo_sugestao_bytes: int = Field(
        10 * 1024 * 1024, validation_alias="MAX_SUGGESTION_ATTACHMENT_BYTES"
    )

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    @field_validator("origens_cors", mode="before")
    @classmethod
    def separar_origens(cls, valor: Any) -> list[str]:
        if not valor:
            return []
        if isinstance(valor, str):
            return [origem.strip().rstrip("/") for origem in valor.split(",") if origem.strip()]
        if isinstance(valor, list):
            return valor
        raise ValueError("CORS_ORIGINS deve ser uma lista separada por vírgulas")

    @field_validator("nome_aplicacao", mode="before")
    @classmethod
    def migrar_nome_legado(cls, valor: Any) -> Any:
        if isinstance(valor, str) and valor.strip().casefold() in {"transdocs", "transdocs api"}:
            return "ThiagoDocs API"
        return valor

    @model_validator(mode="after")
    def validar_producao(self) -> "Configuracoes":
        if self.ambiente.lower() == "production" and not self.origens_cors:
            raise ValueError("CORS_ORIGINS é obrigatório em produção")
        if "*" in self.origens_cors:
            raise ValueError("CORS_ORIGINS não aceita wildcard")
        return self

    @property
    def supabase_configurado(self) -> bool:
        return bool(self.supabase_url and self.supabase_anon_key and self.supabase_service_role_key)

    @property
    def openai_configurada(self) -> bool:
        return bool(self.openai_api_key and self.openai_modelo)


@lru_cache
def obter_configuracoes() -> Configuracoes:
    return Configuracoes()
