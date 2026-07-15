import json
from types import SimpleNamespace

from app.core.configuracao import Configuracoes
from app.infraestrutura.arquivos.docx import analisar_docx
from app.infraestrutura.openai.preenchedor import ExtratorPreenchimentoOpenAI
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
                        "fonte_id": "minuta_base",
                        "pagina": 1,
                        "trecho": "CPF 999.999.999-99",
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
