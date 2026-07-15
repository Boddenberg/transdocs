from dataclasses import dataclass
from io import BytesIO

from pypdf import PdfReader, PdfWriter

from app.dominio.falhas import FalhaLeituraDocumento


@dataclass(frozen=True, slots=True)
class TextoPdf:
    texto: str
    paginas: int
    possui_texto_legivel: bool


def extrair_texto_pdf(
    conteudo: bytes, limite_caracteres: int, *, paginas_maximas: int | None = None
) -> TextoPdf:
    try:
        leitor = PdfReader(BytesIO(conteudo), strict=False)
        if leitor.is_encrypted and leitor.decrypt("") == 0:
            raise FalhaLeituraDocumento("PDF protegido por senha.")
        partes: list[str] = []
        total = 0
        for numero, pagina in enumerate(leitor.pages, start=1):
            if paginas_maximas is not None and numero > paginas_maximas:
                break
            texto = (pagina.extract_text() or "").strip()
            if not texto:
                continue
            trecho = f"[PÁGINA {numero}]\n{texto}"
            restante = limite_caracteres - total
            if restante <= 0:
                break
            partes.append(trecho[:restante])
            total += len(partes[-1])
        texto_completo = "\n\n".join(partes)
        return TextoPdf(
            texto=texto_completo,
            paginas=len(leitor.pages),
            possui_texto_legivel=len(_somente_alfanumericos(texto_completo)) >= 80,
        )
    except FalhaLeituraDocumento:
        raise
    except Exception as erro:
        raise FalhaLeituraDocumento("Não foi possível ler o PDF.") from erro


def extrair_primeira_pagina_pdf(conteudo: bytes) -> bytes:
    try:
        leitor = PdfReader(BytesIO(conteudo), strict=False)
        if leitor.is_encrypted and leitor.decrypt("") == 0:
            raise FalhaLeituraDocumento("PDF protegido por senha.")
        if not leitor.pages:
            raise FalhaLeituraDocumento("O PDF não possui páginas.")
        escritor = PdfWriter()
        escritor.add_page(leitor.pages[0])
        saida = BytesIO()
        escritor.write(saida)
        return saida.getvalue()
    except FalhaLeituraDocumento:
        raise
    except Exception as erro:
        raise FalhaLeituraDocumento("Não foi possível preparar a primeira página.") from erro


def _somente_alfanumericos(texto: str) -> str:
    return "".join(caractere for caractere in texto if caractere.isalnum())
