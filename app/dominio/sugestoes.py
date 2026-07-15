import re
import unicodedata
from dataclasses import dataclass
from enum import StrEnum
from pathlib import Path

from app.core.erros import ErroRequisicao


class CategoriaSugestao(StrEnum):
    SUGESTAO = "sugestao"
    ERRO = "erro"
    DIFICULDADE = "dificuldade"
    OUTRO = "outro"


class StatusSugestao(StrEnum):
    NOVA = "nova"
    LIDA = "lida"
    RESOLVIDA = "resolvida"
    ARQUIVADA = "arquivada"


TIPOS_IMAGEM_PERMITIDOS = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
}


@dataclass(frozen=True, slots=True)
class AnexoSugestao:
    conteudo: bytes
    nome_original: str
    nome_seguro: str
    tipo_mime: str

    @property
    def tamanho_bytes(self) -> int:
        return len(self.conteudo)


def validar_anexo_sugestao(
    *, conteudo: bytes, nome: str | None, tipo_mime: str | None, limite_bytes: int
) -> AnexoSugestao:
    if not conteudo:
        raise ErroRequisicao("Um dos anexos está vazio.")
    if len(conteudo) > limite_bytes:
        raise ErroRequisicao(
            "Cada print ou foto pode ter no máximo 10 MB.",
            {"limite_bytes": limite_bytes},
        )

    mime = (tipo_mime or "").split(";", 1)[0].strip().lower()
    if mime in {"image/jpg", "image/pjpeg"}:
        mime = "image/jpeg"
    if mime not in TIPOS_IMAGEM_PERMITIDOS:
        raise ErroRequisicao("Anexe imagens JPG, PNG ou WEBP.")
    _validar_assinatura(conteudo, mime)

    extensao = TIPOS_IMAGEM_PERMITIDOS[mime]
    nome_original = Path(nome or f"anexo{extensao}").name[:255]
    return AnexoSugestao(
        conteudo=conteudo,
        nome_original=nome_original,
        nome_seguro=_sanitizar_nome(Path(nome_original).stem, extensao),
        tipo_mime=mime,
    )


def _validar_assinatura(conteudo: bytes, mime: str) -> None:
    valido = {
        "image/jpeg": conteudo.startswith(b"\xff\xd8\xff"),
        "image/png": conteudo.startswith(b"\x89PNG\r\n\x1a\n"),
        "image/webp": conteudo.startswith(b"RIFF") and conteudo[8:12] == b"WEBP",
    }[mime]
    if not valido:
        raise ErroRequisicao("O conteúdo do anexo não corresponde ao tipo informado.")


def _sanitizar_nome(nome: str, extensao: str) -> str:
    sem_acentos = unicodedata.normalize("NFKD", nome).encode("ascii", "ignore").decode()
    base = re.sub(r"[^a-zA-Z0-9_-]+", "-", sem_acentos).strip("-").lower()
    return f"{(base or 'anexo')[:120]}{extensao}"
