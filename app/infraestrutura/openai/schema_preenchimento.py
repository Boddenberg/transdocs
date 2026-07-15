from typing import Any


def formato_resultado_preenchimento() -> dict[str, Any]:
    item = {
        "type": "object",
        "additionalProperties": False,
        "required": [
            "campo_id",
            "status",
            "valor",
            "fonte_id",
            "pagina",
            "trecho",
            "confianca",
            "justificativa",
        ],
        "properties": {
            "campo_id": {"type": "string"},
            "status": {"type": "string", "enum": ["encontrado", "ausente", "ambiguo"]},
            "valor": {"type": ["string", "null"]},
            "fonte_id": {"type": ["string", "null"]},
            "pagina": {"type": ["integer", "null"]},
            "trecho": {"type": ["string", "null"]},
            "confianca": {"type": "number", "minimum": 0, "maximum": 1},
            "justificativa": {"type": "string"},
        },
    }
    return {
        "type": "json_schema",
        "name": "preenchimento_seguro_escritura",
        "strict": True,
        "schema": {
            "type": "object",
            "additionalProperties": False,
            "required": ["campos", "alertas"],
            "properties": {
                "campos": {"type": "array", "items": item},
                "alertas": {"type": "array", "items": {"type": "string"}},
            },
        },
    }
