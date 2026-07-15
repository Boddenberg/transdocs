from io import BytesIO

from pypdf import PdfReader, PdfWriter

from app.infraestrutura.arquivos.leitor_pdf import (
    extrair_primeira_pagina_pdf,
    extrair_texto_pdf,
)


def _pdf_com_tres_paginas() -> bytes:
    escritor = PdfWriter()
    for _ in range(3):
        escritor.add_blank_page(width=300, height=400)
    saida = BytesIO()
    escritor.write(saida)
    return saida.getvalue()


def test_reduz_pdf_para_a_primeira_pagina() -> None:
    reduzido = extrair_primeira_pagina_pdf(_pdf_com_tres_paginas())

    assert len(PdfReader(BytesIO(reduzido)).pages) == 1


def test_leitura_limitada_mantem_total_de_paginas_original() -> None:
    resultado = extrair_texto_pdf(
        _pdf_com_tres_paginas(),
        limite_caracteres=10_000,
        paginas_maximas=1,
    )

    assert resultado.paginas == 3
