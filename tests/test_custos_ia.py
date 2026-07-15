from decimal import Decimal

from app.dominio.custos_ia import calcular_metricas_analise


def test_calcula_tokens_e_custo_estimado_em_reais() -> None:
    metricas = calcular_metricas_analise(
        {
            "tokens_entrada": 10_000,
            "tokens_saida": 2_000,
            "modelo_ia": "gpt-5.4-mini",
            "estrategia": "texto",
            "concluido_em": "2026-07-15T03:00:00+00:00",
        },
        preco_entrada_usd_milhao=Decimal("0.75"),
        preco_saida_usd_milhao=Decimal("4.50"),
        cotacao_usd_brl=Decimal("5.50"),
    )

    assert metricas is not None
    assert metricas["tokens_total"] == 12_000
    assert metricas["custo_estimado_usd"] == 0.0165
    assert metricas["custo_estimado_brl"] == 0.0908


def test_nao_inventa_custo_sem_registro_de_tokens() -> None:
    assert (
        calcular_metricas_analise(
            {"tokens_entrada": None, "tokens_saida": None},
            preco_entrada_usd_milhao=Decimal("0.75"),
            preco_saida_usd_milhao=Decimal("4.50"),
            cotacao_usd_brl=Decimal("5.50"),
        )
        is None
    )
