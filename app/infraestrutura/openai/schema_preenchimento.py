from typing import Any


def formato_resultado_preenchimento() -> dict[str, Any]:
    evidencia = {
        "type": "object",
        "additionalProperties": False,
        "required": ["fonte_id", "pagina", "trecho"],
        "properties": {
            "fonte_id": {"type": "string"},
            "pagina": {"type": ["integer", "null"]},
            "trecho": {"type": "string"},
        },
    }
    item = {
        "type": "object",
        "additionalProperties": False,
        "required": [
            "campo_id",
            "status",
            "valor",
            "modo_preenchimento",
            "evidencias",
            "confianca",
            "justificativa",
        ],
        "properties": {
            "campo_id": {"type": "string"},
            "status": {"type": "string", "enum": ["encontrado", "ausente", "ambiguo"]},
            "valor": {"type": ["string", "null"]},
            "modo_preenchimento": {
                "type": "string",
                "enum": ["literal", "composto"],
            },
            "evidencias": {"type": "array", "items": evidencia},
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
