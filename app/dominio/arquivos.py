import hashlib
import re
import unicodedata
from dataclasses import dataclass
from pathlib import Path

from app.core.erros import ErroRequisicao
from app.dominio.documentos import TipoDocumentoEnviado

TIPOS_PERMITIDOS = {
    "application/pdf": (TipoDocumentoEnviado.PDF, ".pdf"),
    "image/jpeg": (TipoDocumentoEnviado.IMAGEM, ".jpg"),
    "image/png": (TipoDocumentoEnviado.IMAGEM, ".png"),
    "image/webp": (TipoDocumentoEnviado.IMAGEM, ".webp"),
}


@dataclass(frozen=True, slots=True)
class ArquivoValidado:
    conteudo: bytes
    nome_original: str
    nome_seguro: str
    tipo_mime: str
    tipo: TipoDocumentoEnviado
    hash_sha256: str

    @property
    def tamanho_bytes(self) -> int:
        return len(self.conteudo)


def validar_arquivo(
    *, conteudo: bytes, nome: str | None, tipo_mime: str | None, limite_bytes: int
) -> ArquivoValidado:
    if not conteudo:
        raise ErroRequisicao("O arquivo enviado está vazio.")
    if len(conteudo) > limite_bytes:
        raise ErroRequisicao(
            "O arquivo excede o limite permitido.",
            {"limite_bytes": limite_bytes},
        )

    mime = _normalizar_mime(tipo_mime)
    if mime not in TIPOS_PERMITIDOS:
        raise ErroRequisicao("Envie um PDF, JPG, PNG ou WEBP.")
    _validar_assinatura(conteudo, mime)

    tipo, extensao = TIPOS_PERMITIDOS[mime]
    nome_original = Path(nome or f"documento{extensao}").name[:255]
    nome_seguro = _sanitizar_nome(Path(nome_original).stem, extensao)
    return ArquivoValidado(
        conteudo=conteudo,
        nome_original=nome_original,
        nome_seguro=nome_seguro,
        tipo_mime=mime,
        tipo=tipo,
        hash_sha256=hashlib.sha256(conteudo).hexdigest(),
    )


def _normalizar_mime(tipo_mime: str | None) -> str:
    mime = (tipo_mime or "").split(";", 1)[0].strip().lower()
    return "image/jpeg" if mime in {"image/jpg", "image/pjpeg"} else mime


def _validar_assinatura(conteudo: bytes, mime: str) -> None:
    valido = {
        "application/pdf": conteudo.startswith(b"%PDF-"),
        "image/jpeg": conteudo.startswith(b"\xff\xd8\xff"),
        "image/png": conteudo.startswith(b"\x89PNG\r\n\x1a\n"),
        "image/webp": conteudo.startswith(b"RIFF") and conteudo[8:12] == b"WEBP",
    }[mime]
    if not valido:
        raise ErroRequisicao("O conteúdo do arquivo não corresponde ao tipo informado.")


def _sanitizar_nome(nome: str, extensao: str) -> str:
    sem_acentos = unicodedata.normalize("NFKD", nome).encode("ascii", "ignore").decode()
    base = re.sub(r"[^a-zA-Z0-9_-]+", "-", sem_acentos).strip("-").lower()
    return f"{(base or 'documento')[:120]}{extensao}"
