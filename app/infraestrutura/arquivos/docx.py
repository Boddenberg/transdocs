import hashlib
import html
import re
import unicodedata
import zipfile
from collections import defaultdict
from dataclasses import dataclass
from io import BytesIO
from xml.sax.saxutils import escape

from app.dominio.falhas import FalhaLeituraDocumento
from app.dominio.preenchimentos import (
    CampoPreenchimento,
    LocalizadorCampoDocx,
    StatusCampoPreenchimento,
)

PADRAO_PARAGRAFO = re.compile(r"<w:p\b[^>]*>.*?</w:p>", re.DOTALL)
PADRAO_TEXTO = re.compile(r"<w:t\b[^>]*>(.*?)</w:t>", re.DOTALL)
PADRAO_MARCADOR = re.compile(
    r"<<\s*[A-Za-zÀ-ÿ0-9_.:/ -]{2,80}\s*>>"
    r"|\[(?:CAMPO|PREENCHER)\s*:[^\]]{2,120}\]"
    r"|_{3,}",
    re.IGNORECASE,
)


@dataclass(frozen=True, slots=True)
class DocumentoDocxAnalisado:
    texto: str
    campos: list[CampoPreenchimento]
    partes_textuais: tuple[str, ...]


def analisar_docx(conteudo: bytes) -> DocumentoDocxAnalisado:
    try:
        with zipfile.ZipFile(BytesIO(conteudo)) as pacote:
            partes = _listar_partes_textuais(pacote)
            textos: list[str] = []
            campos: list[CampoPreenchimento] = []
            for parte in partes:
                xml = pacote.read(parte).decode("utf-8")
                for indice, paragrafo in enumerate(PADRAO_PARAGRAFO.finditer(xml)):
                    texto = _texto_visivel(paragrafo.group(0))
                    if texto.strip():
                        textos.append(f"[{parte}#p{indice}] {texto}")
                    for marcador in PADRAO_MARCADOR.finditer(texto):
                        campos.append(
                            _criar_campo(
                                parte=parte,
                                paragrafo=indice,
                                texto=texto,
                                inicio=marcador.start(),
                                fim=marcador.end(),
                                marcador=marcador.group(0),
                            )
                        )
            return DocumentoDocxAnalisado(
                texto="\n\n".join(textos),
                campos=campos,
                partes_textuais=tuple(partes),
            )
    except (zipfile.BadZipFile, KeyError, UnicodeDecodeError, OSError) as erro:
        raise FalhaLeituraDocumento("Não foi possível ler a estrutura da minuta DOCX.") from erro


def corresponde_escritura_venda_compra(analise: DocumentoDocxAnalisado) -> bool:
    normalizado = _normalizar(analise.texto[:1500])
    return "escritura publica de venda e compra" in normalizado


def preencher_docx(
    conteudo: bytes,
    *,
    campos: list[CampoPreenchimento],
    substituicoes: dict[str, str],
) -> bytes:
    por_parte: dict[str, dict[int, list[tuple[LocalizadorCampoDocx, str]]]] = defaultdict(
        lambda: defaultdict(list)
    )
    campos_por_id = {campo.id: campo for campo in campos}
    for campo_id, valor_bruto in substituicoes.items():
        campo = campos_por_id.get(campo_id)
        if campo is None:
            raise FalhaLeituraDocumento("Um campo selecionado não pertence a esta minuta.")
        valor = _validar_valor(valor_bruto)
        por_parte[campo.localizador.parte][campo.localizador.paragrafo].append(
            (campo.localizador, valor)
        )

    try:
        origem = BytesIO(conteudo)
        saida = BytesIO()
        with zipfile.ZipFile(origem) as pacote, zipfile.ZipFile(saida, "w") as novo:
            novo.comment = pacote.comment
            for info in pacote.infolist():
                dados = pacote.read(info.filename)
                if info.filename in por_parte:
                    xml = dados.decode("utf-8")
                    dados = _preencher_parte(xml, por_parte[info.filename]).encode("utf-8")
                novo.writestr(info, dados)
        resultado = saida.getvalue()
        with zipfile.ZipFile(BytesIO(resultado)) as teste:
            teste.read("word/document.xml")
        return resultado
    except FalhaLeituraDocumento:
        raise
    except (zipfile.BadZipFile, KeyError, UnicodeDecodeError, OSError) as erro:
        raise FalhaLeituraDocumento("Não foi possível gerar o DOCX preenchido.") from erro


def _listar_partes_textuais(pacote: zipfile.ZipFile) -> list[str]:
    nomes = set(pacote.namelist())
    partes = ["word/document.xml"]
    opcionais = sorted(
        nome
        for nome in nomes
        if re.fullmatch(r"word/(?:header\d+|footer\d+|footnotes|endnotes)\.xml", nome)
    )
    return partes + opcionais


def _criar_campo(
    *, parte: str, paragrafo: int, texto: str, inicio: int, fim: int, marcador: str
) -> CampoPreenchimento:
    semente = f"{parte}|{paragrafo}|{inicio}|{fim}|{marcador}".encode()
    campo_id = f"campo_{hashlib.sha256(semente).hexdigest()[:16]}"
    antes = texto[max(0, inicio - 110) : inicio]
    depois = texto[fim : fim + 110]
    contexto = f"{antes}⟦{marcador}⟧{depois}".strip()
    return CampoPreenchimento(
        id=campo_id,
        rotulo=_rotulo_marcador(marcador, antes, depois),
        marcador=marcador,
        contexto=contexto,
        status=StatusCampoPreenchimento.AUSENTE,
        justificativa="Nenhuma fonte comprovou este campo até o momento.",
        localizador=LocalizadorCampoDocx(
            parte=parte,
            paragrafo=paragrafo,
            inicio=inicio,
            fim=fim,
            marcador=marcador,
        ),
    )


def _rotulo_marcador(marcador: str, antes: str, depois: str) -> str:
    if marcador.startswith("<<"):
        return marcador[2:-2].strip().replace("_", " ").title()
    if marcador.startswith("["):
        return marcador.split(":", 1)[-1].rstrip("]").strip()
    esquerda = " ".join(antes.split())[-55:]
    direita = " ".join(depois.split())[:55]
    if esquerda and direita:
        return f"Lacuna entre “{esquerda}” e “{direita}”"
    return "Lacuna explícita da minuta"


def _preencher_parte(
    xml: str, por_paragrafo: dict[int, list[tuple[LocalizadorCampoDocx, str]]]
) -> str:
    paragrafos = list(PADRAO_PARAGRAFO.finditer(xml))
    blocos: dict[int, str] = {}
    for indice, substituicoes in por_paragrafo.items():
        if indice >= len(paragrafos):
            raise FalhaLeituraDocumento("A estrutura da minuta mudou desde a análise.")
        bloco = paragrafos[indice].group(0)
        for localizador, valor in sorted(
            substituicoes, key=lambda item: item[0].inicio, reverse=True
        ):
            bloco = _substituir_no_paragrafo(bloco, localizador, valor)
        blocos[indice] = bloco
    for indice in sorted(blocos, reverse=True):
        paragrafo = paragrafos[indice]
        xml = xml[: paragrafo.start()] + blocos[indice] + xml[paragrafo.end() :]
    return xml


def _substituir_no_paragrafo(
    bloco: str, localizador: LocalizadorCampoDocx, valor: str
) -> str:
    nos = list(PADRAO_TEXTO.finditer(bloco))
    textos = [html.unescape(no.group(1)) for no in nos]
    visivel = "".join(textos)
    if visivel[localizador.inicio : localizador.fim] != localizador.marcador:
        raise FalhaLeituraDocumento("Um marcador da minuta mudou desde a análise.")

    cursor = 0
    primeiro: int | None = None
    ultimo: int | None = None
    inicios: list[int] = []
    for indice, texto in enumerate(textos):
        inicios.append(cursor)
        fim_no = cursor + len(texto)
        if localizador.inicio < fim_no and localizador.fim > cursor:
            primeiro = indice if primeiro is None else primeiro
            ultimo = indice
        cursor = fim_no
    if primeiro is None or ultimo is None:
        raise FalhaLeituraDocumento("Não foi possível localizar um marcador da minuta.")

    if primeiro == ultimo:
        inicio_local = localizador.inicio - inicios[primeiro]
        fim_local = localizador.fim - inicios[primeiro]
        textos[primeiro] = (
            textos[primeiro][:inicio_local] + valor + textos[primeiro][fim_local:]
        )
    else:
        inicio_local = localizador.inicio - inicios[primeiro]
        fim_local = localizador.fim - inicios[ultimo]
        textos[primeiro] = textos[primeiro][:inicio_local] + valor
        for indice in range(primeiro + 1, ultimo):
            textos[indice] = ""
        textos[ultimo] = textos[ultimo][fim_local:]

    for indice in range(len(nos) - 1, -1, -1):
        no = nos[indice]
        bloco = bloco[: no.start(1)] + escape(textos[indice]) + bloco[no.end(1) :]
    return bloco


def _texto_visivel(bloco: str) -> str:
    return "".join(html.unescape(no.group(1)) for no in PADRAO_TEXTO.finditer(bloco))


def _validar_valor(valor: str) -> str:
    limpo = valor.strip()
    if not limpo or len(limpo) > 8000:
        raise FalhaLeituraDocumento("Um valor selecionado é inválido para a minuta.")
    if any(ord(caractere) < 32 and caractere not in {"\t", "\n"} for caractere in limpo):
        raise FalhaLeituraDocumento("Um valor contém caracteres inválidos.")
    return " ".join(limpo.split())


def _normalizar(texto: str) -> str:
    sem_acentos = "".join(
        caractere
        for caractere in unicodedata.normalize("NFKD", texto.casefold())
        if not unicodedata.combining(caractere)
    )
    return " ".join(sem_acentos.split())
