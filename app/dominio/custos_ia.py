from decimal import ROUND_HALF_UP, Decimal
from typing import Any

UM_MILHAO = Decimal("1000000")


def calcular_metricas_analise(
    processamento: dict[str, Any] | None,
    *,
    preco_entrada_usd_milhao: Decimal,
    preco_saida_usd_milhao: Decimal,
    cotacao_usd_brl: Decimal,
) -> dict[str, Any] | None:
    if not processamento:
        return None

    entrada_informada = processamento.get("tokens_entrada")
    saida_informada = processamento.get("tokens_saida")
    if entrada_informada is None and saida_informada is None:
        return None

    tokens_entrada = int(entrada_informada or 0)
    tokens_saida = int(saida_informada or 0)
    custo_usd = (
        Decimal(tokens_entrada) * preco_entrada_usd_milhao
        + Decimal(tokens_saida) * preco_saida_usd_milhao
    ) / UM_MILHAO
    custo_brl = custo_usd * cotacao_usd_brl

    return {
        "tokens_entrada": tokens_entrada,
        "tokens_saida": tokens_saida,
        "tokens_total": tokens_entrada + tokens_saida,
        "custo_estimado_usd": float(custo_usd.quantize(Decimal("0.000001"))),
        "custo_estimado_brl": float(
            custo_brl.quantize(Decimal("0.0001"), rounding=ROUND_HALF_UP)
        ),
        "cotacao_usd_brl": float(cotacao_usd_brl),
        "modelo_ia": processamento.get("modelo_ia"),
        "estrategia": processamento.get("estrategia"),
        "concluido_em": processamento.get("concluido_em"),
    }
