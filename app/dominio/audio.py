from dataclasses import dataclass
from pathlib import Path

from app.core.erros import ErroRequisicao

_EXTENSOES = {".flac", ".mp3", ".mp4", ".mpeg", ".mpga", ".m4a", ".ogg", ".wav", ".webm", ".aac"}
_MIMES = {
    "application/octet-stream",
    "application/ogg",
    "audio/aac",
    "audio/flac",
    "audio/mp4",
    "audio/mpeg",
    "audio/ogg",
    "audio/wav",
    "audio/webm",
    "audio/x-flac",
    "audio/x-m4a",
    "audio/x-wav",
    "video/mp4",
    "video/webm",
}


@dataclass(frozen=True, slots=True)
class AudioValidado:
    conteudo: bytes
    nome: str
    tipo_mime: str


def validar_audio(
    *,
    conteudo: bytes,
    nome: str | None,
    tipo_mime: str | None,
    limite_bytes: int,
) -> AudioValidado:
    if not conteudo:
        raise ErroRequisicao("O áudio enviado está vazio.")
    if len(conteudo) > limite_bytes:
        raise ErroRequisicao(
            "O áudio excede o limite permitido.",
            {"limite_bytes": limite_bytes},
        )
    nome_seguro = Path(nome or "audio.webm").name[:255]
    extensao = Path(nome_seguro).suffix.casefold()
    mime = (tipo_mime or "application/octet-stream").split(";", 1)[0].strip().lower()
    if extensao not in _EXTENSOES or mime not in _MIMES:
        raise ErroRequisicao(
            "Envie um áudio FLAC, MP3, MP4, M4A, OGG, WAV, WEBM ou AAC."
        )
    if not _assinatura_compativel(conteudo, extensao):
        raise ErroRequisicao("O conteúdo do arquivo não corresponde a um áudio suportado.")
    return AudioValidado(conteudo=conteudo, nome=nome_seguro, tipo_mime=mime)


def _assinatura_compativel(conteudo: bytes, extensao: str) -> bool:
    if extensao == ".webm":
        return conteudo.startswith(b"\x1aE\xdf\xa3")
    if extensao == ".wav":
        return conteudo.startswith(b"RIFF") and conteudo[8:12] == b"WAVE"
    if extensao == ".ogg":
        return conteudo.startswith(b"OggS")
    if extensao == ".flac":
        return conteudo.startswith(b"fLaC")
    if extensao in {".m4a", ".mp4"}:
        return len(conteudo) >= 12 and conteudo[4:8] == b"ftyp"
    if extensao == ".aac":
        return len(conteudo) >= 2 and conteudo[0] == 0xFF and conteudo[1] & 0xF0 == 0xF0
    if extensao in {".mp3", ".mpeg", ".mpga"}:
        return conteudo.startswith(b"ID3") or (
            len(conteudo) >= 2 and conteudo[0] == 0xFF and conteudo[1] & 0xE0 == 0xE0
        )
    return False
