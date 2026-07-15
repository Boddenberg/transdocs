from app.aplicacao.documentos.servico import extrair_dados_principais


def _item(tipo: str, valor: str) -> dict:
    return {
        "tipo": tipo,
        "valor": valor,
        "pagina": 1,
        "trecho": None,
        "confianca": 0.98,
        "precisa_revisao": False,
        "confirmado": False,
        "editado": False,
    }


def test_seleciona_nome_e_documentos_mais_uteis() -> None:
    resultado = {
        "tipo_documento": "Contrato de locação",
        "pessoas": [{**_item("nome completo", "Maria Joana"), "papel": "Locatária"}],
        "empresas": [],
        "documentos_identificados": [
            _item("CPF", "088.794.450-73"),
            _item("RG", "12.345.678-9"),
        ],
        "enderecos": [],
        "datas": [],
        "valores": [],
        "imoveis": [],
        "campos_adicionais": [],
        "alertas": [],
        "campos_nao_encontrados": [],
    }

    assert extrair_dados_principais(resultado) == [
        {"rotulo": "Nome", "valor": "Maria Joana"},
        {"rotulo": "CPF", "valor": "088.794.450-73"},
        {"rotulo": "RG", "valor": "12.345.678-9"},
    ]
