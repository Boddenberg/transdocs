from io import BytesIO
from zipfile import ZIP_DEFLATED, ZipFile

from app.dominio.preenchimentos import validar_arquivo_docx
from app.infraestrutura.arquivos.docx import (
    analisar_docx,
    corresponde_escritura_venda_compra,
    preencher_docx,
)


def _docx_minimo() -> bytes:
    documento = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p><w:r><w:t>ESCRITURA PÚBLICA DE VENDA E COMPRA</w:t></w:r></w:p>
    <w:p><w:r><w:t>CPF n° ___</w:t></w:r>
      <w:r><w:rPr><w:b/></w:rPr><w:t>_____</w:t></w:r>
      <w:r><w:t>; texto preservado.</w:t></w:r></w:p>
  </w:body>
</w:document>""".encode()
    tipos = b"""<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="xml" ContentType="application/xml"/>
</Types>"""
    saida = BytesIO()
    with ZipFile(saida, "w", ZIP_DEFLATED) as pacote:
        pacote.writestr("[Content_Types].xml", tipos)
        pacote.writestr("word/document.xml", documento)
        pacote.writestr("word/styles.xml", b"<styles/>")
    return saida.getvalue()


def test_identifica_e_preenche_marcador_dividido_sem_reconstruir_o_pacote() -> None:
    original = _docx_minimo()
    analise = analisar_docx(original)

    assert corresponde_escritura_venda_compra(analise)
    assert len(analise.campos) == 1
    assert analise.campos[0].marcador == "________"

    preenchido = preencher_docx(
        original,
        campos=analise.campos,
        substituicoes={analise.campos[0].id: "123.456.789-00"},
    )
    nova_analise = analisar_docx(preenchido)
    assert "CPF n° 123.456.789-00; texto preservado." in nova_analise.texto
    assert not nova_analise.campos

    with ZipFile(BytesIO(original)) as antes, ZipFile(BytesIO(preenchido)) as depois:
        assert antes.read("word/styles.xml") == depois.read("word/styles.xml")
        assert antes.read("[Content_Types].xml") == depois.read("[Content_Types].xml")
        assert antes.read("word/document.xml") != depois.read("word/document.xml")


def test_valida_minuta_docx_por_assinatura_e_partes_obrigatorias() -> None:
    validado = validar_arquivo_docx(
        conteudo=_docx_minimo(),
        nome="Minha Minuta.docx",
        tipo_mime="application/octet-stream",
        limite_bytes=1_000_000,
    )

    assert validado.nome_original == "Minha Minuta.docx"
    assert validado.nome_seguro == "minha-minuta.docx"
    assert len(validado.hash_sha256) == 64
