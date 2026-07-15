import json
from types import SimpleNamespace

from app.core.configuracao import Configuracoes
from app.infraestrutura.arquivos.docx import analisar_docx
from app.infraestrutura.openai.preenchedor import (
    ExtratorPreenchimentoOpenAI,
    _humanizar_alertas,
)
from tests.test_preenchimento_docx import _docx_minimo


class _RespostasFalsas:
    def __init__(self, conteudo: dict) -> None:
        self._conteudo = conteudo

    def create(self, **_kwargs):
        return SimpleNamespace(
            output_text=json.dumps(self._conteudo),
            usage=SimpleNamespace(input_tokens=10, output_tokens=5),
        )


def test_rebaixa_sugestao_que_nao_existe_na_evidencia_textual() -> None:
    campo = analisar_docx(_docx_minimo()).campos[0]
    cliente = SimpleNamespace(
        responses=_RespostasFalsas(
            {
                "campos": [
                    {
                        "campo_id": campo.id,
                        "status": "encontrado",
                        "valor": "999.999.999-99",
                        "modo_preenchimento": "literal",
                        "evidencias": [
                            {
                                "fonte_id": "minuta_base",
                                "pagina": 1,
                                "trecho": "CPF 999.999.999-99",
                            }
                        ],
                        "confianca": 0.99,
                        "justificativa": "Consta na minuta.",
                    }
                ],
                "alertas": [],
            }
        )
    )
    extrator = ExtratorPreenchimentoOpenAI(
        cliente,
        Configuracoes(_env_file=None, OPENAI_API_KEY="teste"),
    )

    resposta = extrator.analisar(
        tipo_documento="escritura_publica_venda_compra",
        texto_minuta="A minuta contém somente o CPF 123.456.789-00.",
        campos=[campo],
        fontes=[],
    )

    validado = resposta.resultado.campos[0]
    assert validado.status == "ambiguo"
    assert validado.valor is None
    assert validado.autoaplicavel is False
    assert resposta.resultado.total_pendentes == 1


def test_usa_declaracao_para_papel_e_condicao_expressamente_informados() -> None:
    campo = analisar_docx(_docx_minimo()).campos[0]
    cliente = SimpleNamespace(
        responses=_RespostasFalsas(
            {
                "campos": [
                    {
                        "campo_id": campo.id,
                        "status": "encontrado",
                        "valor": "R$ 100.000,00",
                        "modo_preenchimento": "literal",
                        "evidencias": [
                            {
                                "fonte_id": "declaracao_negociacao",
                                "pagina": None,
                                "trecho": "pelo preço de R$ 100.000,00",
                            }
                        ],
                        "confianca": 0.99,
                        "justificativa": "Preço declarado pelo usuário.",
                    }
                ],
                "alertas": [],
            }
        )
    )
    extrator = ExtratorPreenchimentoOpenAI(
        cliente,
        Configuracoes(_env_file=None, OPENAI_API_KEY="teste"),
    )

    resposta = extrator.analisar(
        tipo_documento="escritura_publica_venda_compra",
        texto_minuta="ESCRITURA PÚBLICA DE VENDA E COMPRA",
        campos=[campo],
        fontes=[],
        instrucoes_negociacao=(
            "Fulano é o vendedor e Beltrano é o comprador, "
            "pelo preço de R$ 100.000,00."
        ),
    )

    validado = resposta.resultado.campos[0]
    assert validado.status == "encontrado"
    assert validado.fonte_id == "declaracao_negociacao"
    assert validado.fonte_nome == "Informações declaradas da negociação"
    assert validado.autoaplicavel is True


def test_bloco_semantico_composto_exige_revisao_e_guarda_varias_evidencias() -> None:
    campo = analisar_docx(_docx_minimo()).campos[0].model_copy(
        update={"marcador": "[PREENCHER:PRECO_E_PAGAMENTO]"}
    )
    cliente = SimpleNamespace(
        responses=_RespostasFalsas(
            {
                "campos": [
                    {
                        "campo_id": campo.id,
                        "status": "encontrado",
                        "valor": (
                            "O preço é de R$ 100.000,00, pago mediante transferência bancária."
                        ),
                        "modo_preenchimento": "composto",
                        "evidencias": [
                            {
                                "fonte_id": "declaracao_negociacao",
                                "pagina": None,
                                "trecho": "preço de R$ 100.000,00",
                            },
                            {
                                "fonte_id": "declaracao_negociacao",
                                "pagina": None,
                                "trecho": "pago mediante transferência bancária",
                            },
                        ],
                        "confianca": 0.96,
                        "justificativa": "Bloco composto apenas com condições declaradas.",
                    }
                ],
                "alertas": [],
            }
        )
    )
    extrator = ExtratorPreenchimentoOpenAI(
        cliente,
        Configuracoes(_env_file=None, OPENAI_API_KEY="teste"),
    )

    resposta = extrator.analisar(
        tipo_documento="escritura_publica_venda_compra",
        texto_minuta="ESCRITURA PÚBLICA DE VENDA E COMPRA",
        campos=[campo],
        fontes=[],
        instrucoes_negociacao=(
            "O negócio tem preço de R$ 100.000,00, "
            "pago mediante transferência bancária."
        ),
    )

    validado = resposta.resultado.campos[0]
    assert validado.status == "encontrado"
    assert validado.modo_preenchimento == "composto"
    assert len(validado.evidencias) == 2
    assert validado.autoaplicavel is False
    assert "revise o texto integralmente" in resposta.resultado.alertas[0]


def test_remove_identificador_interno_dos_alertas() -> None:
    campo = analisar_docx(_docx_minimo()).campos[0]

    alertas = _humanizar_alertas(
        [f"{campo.id}: confira a diferença entre a minuta e a fonte."],
        [campo],
    )

    assert alertas == ["Lacuna 1: confira a diferença entre a minuta e a fonte."]
    assert "campo_" not in alertas[0]
