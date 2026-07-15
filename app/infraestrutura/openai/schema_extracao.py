from typing import Any


def formato_resultado_extracao() -> dict[str, Any]:
    item = _schema_item()
    parte = _schema_item(incluir_papel=True)
    return {
        "type": "json_schema",
        "name": "extracao_documental_transdocs",
        "strict": True,
        "schema": {
            "type": "object",
            "additionalProperties": False,
            "required": [
                "tipo_documento",
                "resumo",
                "pessoas",
                "empresas",
                "documentos_identificados",
                "enderecos",
                "datas",
                "valores",
                "imoveis",
                "campos_adicionais",
                "alertas",
                "campos_nao_encontrados",
            ],
            "properties": {
                "tipo_documento": {"type": ["string", "null"]},
                "resumo": {"type": ["string", "null"]},
                "pessoas": {"type": "array", "items": parte},
                "empresas": {"type": "array", "items": parte},
                "documentos_identificados": {"type": "array", "items": item},
                "enderecos": {"type": "array", "items": item},
                "datas": {"type": "array", "items": item},
                "valores": {"type": "array", "items": item},
                "imoveis": {"type": "array", "items": item},
                "campos_adicionais": {"type": "array", "items": item},
                "alertas": {"type": "array", "items": {"type": "string"}},
                "campos_nao_encontrados": {
                    "type": "array",
                    "items": {"type": "string"},
                },
            },
        },
    }


def _schema_item(*, incluir_papel: bool = False) -> dict[str, Any]:
    propriedades: dict[str, Any] = {
        "valor": {"type": ["string", "null"]},
        "tipo": {"type": "string"},
        # Restrições numéricas sobre campos anuláveis variam entre modelos;
        # o limite mínimo é aplicado pelo Pydantic após a resposta.
        "pagina": {"type": ["integer", "null"]},
        "trecho": {"type": ["string", "null"]},
        "confianca": {"type": "number", "minimum": 0, "maximum": 1},
        "precisa_revisao": {"type": "boolean"},
        "confirmado": {"type": "boolean"},
        "editado": {"type": "boolean"},
    }
    if incluir_papel:
        propriedades["papel"] = {"type": ["string", "null"]}
    return {
        "type": "object",
        "additionalProperties": False,
        "required": list(propriedades),
        "properties": propriedades,
    }
