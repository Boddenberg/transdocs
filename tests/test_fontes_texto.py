from types import SimpleNamespace

import pytest

from app.aplicacao.preenchimentos.catalogo import TIPO_ESCRITURA_VENDA_COMPRA
from app.aplicacao.preenchimentos.processador import ProcessadorPreenchimento
from app.aplicacao.preenchimentos.servico import (
    FonteTextoPreenchimento,
    ServicoPreenchimentos,
)
from app.core.erros import ErroRequisicao
from app.infraestrutura.openai.preenchedor import ExtratorPreenchimentoOpenAI


def test_valida_e_preserva_fonte_digitada() -> None:
    servico = ServicoPreenchimentos(None, None, None)  # type: ignore[arg-type]

    fontes = servico._validar_fontes_texto(
        TIPO_ESCRITURA_VENDA_COMPRA,
        [
            FonteTextoPreenchimento(
                categoria="documentos_vendedores",
                nome="Dados dos vendedores informados por texto",
                texto="  VENDEDORA TESTE, brasileira, solteira.  ",
            )
        ],
    )

    assert fontes[0].texto == "VENDEDORA TESTE, brasileira, solteira."


def test_rejeita_categoria_invalida_em_fonte_digitada() -> None:
    servico = ServicoPreenchimentos(None, None, None)  # type: ignore[arg-type]

    with pytest.raises(ErroRequisicao):
        servico._validar_fontes_texto(
            TIPO_ESCRITURA_VENDA_COMPRA,
            [FonteTextoPreenchimento("categoria_invalida", "Texto", "Conteúdo")],
        )


def test_processador_cria_fonte_textual_com_categoria_e_evidencia() -> None:
    processador = ProcessadorPreenchimento(None, None, None)  # type: ignore[arg-type]
    fontes = processador._carregar_fontes_texto(
        {
            "fontes_texto": [
                {
                    "categoria": "matricula_imovel",
                    "nome": "Matrícula informada por texto",
                    "texto": "R.1 - aquisição por PROPRIETÁRIA TESTE.",
                }
            ]
        }
    )
    extrator = ExtratorPreenchimentoOpenAI(
        None,  # type: ignore[arg-type]
        SimpleNamespace(limite_texto_extraido=20000),  # type: ignore[arg-type]
    )

    conteudo, evidencias = extrator._montar_conteudo(
        "[PREENCHER:DESCRICAO_DO_IMOVEL]",
        [],
        fontes,
        "",
    )

    assert "categoria=matricula_imovel" in conteudo[-1]["text"]
    assert evidencias["texto_1"].texto == "R.1 - aquisição por PROPRIETÁRIA TESTE."
