from decimal import Decimal

import pytest
from pydantic import ValidationError

from app.dominio.negociacao import (
    DadosNegociacao,
    formatar_reais,
    valor_monetario_por_extenso,
)


def test_valida_componentes_e_monta_declaracao_sem_calculo_da_ia() -> None:
    dados = DadosNegociacao.model_validate(
        {
            "preco_total": "R$ 150.000,00",
            "componentes": [
                {"meio": "sinal", "valor": "50.000,00"},
                {
                    "meio": "transferencia",
                    "valor": "100.000,00",
                    "vencimento": "na assinatura",
                },
            ],
            "imissao_posse": "na assinatura da escritura",
        }
    )

    declaracao = dados.como_declaracao()

    assert dados.preco_total == Decimal("150000.00")
    assert "R$ 150.000,00" in declaracao
    assert "cento e cinquenta mil reais" in declaracao
    assert "na assinatura da escritura" in declaracao


def test_rejeita_pagamento_cuja_soma_nao_corresponde_ao_preco() -> None:
    with pytest.raises(ValidationError, match="soma das formas de pagamento"):
        DadosNegociacao.model_validate(
            {
                "preco_total": "100.000,00",
                "componentes": [
                    {"meio": "sinal", "valor": "20.000,00"},
                    {"meio": "parcelamento", "valor": "70.000,00"},
                ],
            }
        )


@pytest.mark.parametrize(
    ("valor", "esperado"),
    [
        (Decimal("1"), "um real"),
        (Decimal("53.00"), "cinquenta e três reais"),
        (Decimal("53000.00"), "cinquenta e três mil reais"),
        (Decimal("1000000.00"), "um milhão de reais"),
        (Decimal("100000.50"), "cem mil reais e cinquenta centavos"),
    ],
)
def test_escreve_valores_por_extenso(valor: Decimal, esperado: str) -> None:
    assert valor_monetario_por_extenso(valor) == esperado


def test_formata_reais_no_padrao_brasileiro() -> None:
    assert formatar_reais(Decimal("1234567.8")) == "R$ 1.234.567,80"
