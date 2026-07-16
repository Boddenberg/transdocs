from decimal import ROUND_HALF_UP, Decimal, InvalidOperation
from enum import StrEnum
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


class MeioPagamento(StrEnum):
    TRANSFERENCIA = "transferencia"
    PIX = "pix"
    CHEQUE_ADMINISTRATIVO = "cheque_administrativo"
    FINANCIAMENTO = "financiamento"
    SINAL = "sinal"
    PARCELAMENTO = "parcelamento"
    OUTRO = "outro"


_NOMES_MEIOS = {
    MeioPagamento.TRANSFERENCIA: "transferência bancária",
    MeioPagamento.PIX: "Pix",
    MeioPagamento.CHEQUE_ADMINISTRATIVO: "cheque administrativo",
    MeioPagamento.FINANCIAMENTO: "financiamento",
    MeioPagamento.SINAL: "sinal",
    MeioPagamento.PARCELAMENTO: "parcelamento",
    MeioPagamento.OUTRO: "outro meio informado",
}


class ComponentePagamento(BaseModel):
    model_config = ConfigDict(extra="forbid")

    meio: MeioPagamento
    valor: Decimal = Field(gt=0, max_digits=17, decimal_places=2)
    descricao: str = Field(default="", max_length=500)
    vencimento: str = Field(default="", max_length=120)
    favorecido: str = Field(default="", max_length=200)

    @field_validator("valor", mode="before")
    @classmethod
    def normalizar_valor(cls, valor: Any) -> Decimal:
        return normalizar_valor_monetario(valor)

    @field_validator("descricao", "vencimento", "favorecido", mode="before")
    @classmethod
    def limpar_texto(cls, valor: Any) -> str:
        return _limpar_texto(valor)


class DadosNegociacao(BaseModel):
    model_config = ConfigDict(extra="forbid")

    preco_total: Decimal = Field(gt=0, max_digits=17, decimal_places=2)
    moeda: Literal["BRL"] = "BRL"
    componentes: list[ComponentePagamento] = Field(min_length=1, max_length=20)
    imissao_posse: str = Field(default="", max_length=1000)
    clausulas_adicionais: str = Field(default="", max_length=6000)
    observacoes: str = Field(default="", max_length=2000)

    @field_validator("preco_total", mode="before")
    @classmethod
    def normalizar_preco(cls, valor: Any) -> Decimal:
        return normalizar_valor_monetario(valor)

    @field_validator("imissao_posse", "clausulas_adicionais", "observacoes", mode="before")
    @classmethod
    def limpar_textos(cls, valor: Any) -> str:
        return _limpar_texto(valor, preservar_quebras=True)

    @model_validator(mode="after")
    def validar_soma(self) -> "DadosNegociacao":
        soma = sum((item.valor for item in self.componentes), Decimal("0"))
        if soma != self.preco_total:
            raise ValueError(
                "A soma das formas de pagamento deve ser igual ao preço total."
            )
        return self

    @property
    def preco_por_extenso(self) -> str:
        return valor_monetario_por_extenso(self.preco_total)

    def como_declaracao(self) -> str:
        linhas = [
            "DADOS ESTRUTURADOS DA NEGOCIAÇÃO INFORMADOS PELO USUÁRIO:",
            f"Preço total: {formatar_reais(self.preco_total)} "
            f"({self.preco_por_extenso}).",
        ]
        for indice, item in enumerate(self.componentes, start=1):
            detalhes = [
                f"Parcela de pagamento {indice}",
                _NOMES_MEIOS[item.meio],
                formatar_reais(item.valor),
            ]
            if item.vencimento:
                detalhes.append(f"vencimento ou momento: {item.vencimento}")
            if item.favorecido:
                detalhes.append(f"favorecido: {item.favorecido}")
            if item.descricao:
                detalhes.append(f"detalhes: {item.descricao}")
            linhas.append("; ".join(detalhes) + ".")
        if self.imissao_posse:
            linhas.append(f"Imissão na posse: {self.imissao_posse}")
        if self.clausulas_adicionais:
            linhas.append(f"Cláusulas adicionais: {self.clausulas_adicionais}")
        if self.observacoes:
            linhas.append(f"Observações: {self.observacoes}")
        return "\n".join(linhas)


def normalizar_valor_monetario(valor: Any) -> Decimal:
    if isinstance(valor, Decimal):
        numero = valor
    elif isinstance(valor, int | float):
        numero = Decimal(str(valor))
    elif isinstance(valor, str):
        texto = valor.strip().replace("R$", "").replace(" ", "")
        if not texto:
            raise ValueError("Informe um valor monetário.")
        if "," in texto:
            texto = texto.replace(".", "").replace(",", ".")
        elif "." in texto:
            grupos = texto.split(".")
            if len(grupos) > 1 and all(len(grupo) == 3 for grupo in grupos[1:]):
                texto = "".join(grupos)
        try:
            numero = Decimal(texto)
        except InvalidOperation as erro:
            raise ValueError("Informe um valor monetário válido.") from erro
    else:
        raise ValueError("Informe um valor monetário válido.")
    return numero.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def formatar_reais(valor: Decimal) -> str:
    quantizado = normalizar_valor_monetario(valor)
    inteiro, centavos = f"{quantizado:.2f}".split(".")
    grupos = []
    while inteiro:
        grupos.append(inteiro[-3:])
        inteiro = inteiro[:-3]
    return f"R$ {'.'.join(reversed(grupos))},{centavos}"


def valor_monetario_por_extenso(valor: Decimal) -> str:
    quantizado = normalizar_valor_monetario(valor)
    inteiro = int(quantizado)
    centavos = int((quantizado - inteiro) * 100)
    if inteiro > 999_999_999_999_999:
        raise ValueError("O valor excede o limite aceito para escrita por extenso.")

    partes = []
    if inteiro:
        reais = _numero_por_extenso(inteiro)
        preposicao = " de" if inteiro >= 1_000_000 and inteiro % 1_000_000 == 0 else ""
        partes.append(f"{reais}{preposicao} {'real' if inteiro == 1 else 'reais'}")
    if centavos:
        partes.append(
            f"{_numero_por_extenso(centavos)} {'centavo' if centavos == 1 else 'centavos'}"
        )
    return " e ".join(partes) if partes else "zero reais"


def _numero_por_extenso(numero: int) -> str:
    if numero == 0:
        return "zero"
    escalas = (
        (1_000_000_000_000, "trilhão", "trilhões"),
        (1_000_000_000, "bilhão", "bilhões"),
        (1_000_000, "milhão", "milhões"),
        (1_000, "mil", "mil"),
    )
    partes: list[str] = []
    restante = numero
    for divisor, singular, plural in escalas:
        quantidade, restante = divmod(restante, divisor)
        if not quantidade:
            continue
        if divisor == 1_000 and quantidade == 1:
            partes.append("mil")
        else:
            partes.append(
                f"{_numero_por_extenso(quantidade)} "
                f"{singular if quantidade == 1 else plural}"
            )
    if restante:
        partes.append(_ate_999(restante))
    return " e ".join(partes)


def _ate_999(numero: int) -> str:
    unidades = (
        "zero",
        "um",
        "dois",
        "três",
        "quatro",
        "cinco",
        "seis",
        "sete",
        "oito",
        "nove",
    )
    especiais = {
        10: "dez",
        11: "onze",
        12: "doze",
        13: "treze",
        14: "quatorze",
        15: "quinze",
        16: "dezesseis",
        17: "dezessete",
        18: "dezoito",
        19: "dezenove",
    }
    dezenas = {
        20: "vinte",
        30: "trinta",
        40: "quarenta",
        50: "cinquenta",
        60: "sessenta",
        70: "setenta",
        80: "oitenta",
        90: "noventa",
    }
    centenas = {
        100: "cento",
        200: "duzentos",
        300: "trezentos",
        400: "quatrocentos",
        500: "quinhentos",
        600: "seiscentos",
        700: "setecentos",
        800: "oitocentos",
        900: "novecentos",
    }
    if numero < 10:
        return unidades[numero]
    if numero < 20:
        return especiais[numero]
    if numero < 100:
        dezena = numero // 10 * 10
        unidade = numero % 10
        return dezenas[dezena] + (f" e {unidades[unidade]}" if unidade else "")
    if numero == 100:
        return "cem"
    centena = numero // 100 * 100
    resto = numero % 100
    return centenas[centena] + (f" e {_ate_999(resto)}" if resto else "")


def _limpar_texto(valor: Any, *, preservar_quebras: bool = False) -> str:
    if valor is None:
        return ""
    if not isinstance(valor, str):
        raise ValueError("O texto informado é inválido.")
    if any(
        ord(caractere) < 32 and caractere not in {"\t", "\n", "\r"}
        for caractere in valor
    ):
        raise ValueError("O texto informado contém caracteres inválidos.")
    if preservar_quebras:
        return "\n".join(" ".join(linha.split()) for linha in valor.strip().splitlines())
    return " ".join(valor.split())
