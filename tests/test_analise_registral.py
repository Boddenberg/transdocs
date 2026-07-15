from app.dominio.preenchimentos import SituacaoAtoRegistral
from app.infraestrutura.openai.preenchedor import (
    AnaliseImovelRespostaIA,
    _Evidencia,
    _validar_analise_imovel,
)

TEXTO_MATRICULA = """
R.1 - aquisição por ALFA DA SILVA.
R.2 - hipoteca em favor do BANCO TESTE.
Av.3 - fica cancelada a hipoteca registrada sob R.2.
R.4 - aquisição por BETA SOUZA.
Av.5 - caução do imóvel para garantia contratual.
"""


def _evidencia(trecho: str) -> dict:
    return {"fonte_id": "matricula", "pagina": 1, "trecho": trecho}


def test_organiza_cadeia_e_diferencia_onus_cancelado_de_ativo() -> None:
    bruto = AnaliseImovelRespostaIA.model_validate(
        {
            "proprietarios_atuais": [
                {
                    "tipo": "nome",
                    "valor": "BETA SOUZA",
                    "confianca": 0.98,
                    "precisa_revisao": False,
                    "evidencia": _evidencia("R.4 - aquisição por BETA SOUZA"),
                }
            ],
            "atos_registrais": [
                {
                    "ordem": 1,
                    "identificador": "R.1",
                    "data": None,
                    "natureza": "aquisicao",
                    "resumo": "Aquisição por Alfa.",
                    "titulares": ["ALFA DA SILVA"],
                    "valor": None,
                    "referencia_cancelamento": None,
                    "situacao": "historico",
                    "evidencia": _evidencia("R.1 - aquisição por ALFA DA SILVA"),
                },
                {
                    "ordem": 2,
                    "identificador": "R.2",
                    "data": None,
                    "natureza": "onus",
                    "resumo": "Hipoteca.",
                    "titulares": [],
                    "valor": None,
                    "referencia_cancelamento": None,
                    "situacao": "cancelado",
                    "evidencia": _evidencia("R.2 - hipoteca em favor do BANCO TESTE"),
                },
                {
                    "ordem": 3,
                    "identificador": "Av.3",
                    "data": None,
                    "natureza": "cancelamento",
                    "resumo": "Cancelamento da hipoteca R.2.",
                    "titulares": [],
                    "valor": None,
                    "referencia_cancelamento": "R.2",
                    "situacao": "historico",
                    "evidencia": _evidencia("cancelada a hipoteca registrada sob R.2"),
                },
                {
                    "ordem": 4,
                    "identificador": "R.4",
                    "data": None,
                    "natureza": "aquisicao",
                    "resumo": "Aquisição por Beta.",
                    "titulares": ["BETA SOUZA"],
                    "valor": None,
                    "referencia_cancelamento": None,
                    "situacao": "ativo",
                    "evidencia": _evidencia("R.4 - aquisição por BETA SOUZA"),
                },
            ],
            "onus_restricoes": [
                {
                    "tipo": "hipoteca",
                    "ato": "R.2",
                    "resumo": "Hipoteca posteriormente cancelada.",
                    "situacao": "cancelado",
                    "cancelado_por": "Av.3",
                    "evidencia": _evidencia("R.2 - hipoteca em favor do BANCO TESTE"),
                },
                {
                    "tipo": "caução",
                    "ato": "Av.5",
                    "resumo": "Caução sem cancelamento localizado.",
                    "situacao": "ativo",
                    "cancelado_por": None,
                    "evidencia": _evidencia("Av.5 - caução do imóvel"),
                },
            ],
        }
    )
    alertas: list[str] = []

    analise = _validar_analise_imovel(
        bruto,
        evidencias={
            "matricula": _Evidencia(
                "matricula",
                "matricula_imovel",
                "matricula-sintetica.pdf",
                TEXTO_MATRICULA,
                False,
            )
        },
        alertas=alertas,
    )

    assert analise.proprietarios_atuais[0].valor == "BETA SOUZA"
    assert analise.proprietarios_atuais[0].precisa_revisao is False
    assert analise.onus_restricoes[0].situacao == SituacaoAtoRegistral.CANCELADO
    assert analise.onus_restricoes[1].situacao == SituacaoAtoRegistral.ATIVO
    assert not alertas


def test_nao_aceita_cancelamento_sem_ato_posterior_comprovado() -> None:
    bruto = AnaliseImovelRespostaIA.model_validate(
        {
            "onus_restricoes": [
                {
                    "tipo": "caução",
                    "ato": "Av.5",
                    "resumo": "Caução declarada cancelada sem ato comprobatório.",
                    "situacao": "cancelado",
                    "cancelado_por": "Av.99",
                    "evidencia": _evidencia("Av.5 - caução do imóvel"),
                }
            ]
        }
    )
    alertas: list[str] = []

    analise = _validar_analise_imovel(
        bruto,
        evidencias={
            "matricula": _Evidencia(
                "matricula",
                "matricula_imovel",
                "matricula-sintetica.pdf",
                TEXTO_MATRICULA,
                False,
            )
        },
        alertas=alertas,
    )

    assert analise.onus_restricoes[0].situacao == SituacaoAtoRegistral.INCERTO
    assert "não foi comprovado" in alertas[0]
