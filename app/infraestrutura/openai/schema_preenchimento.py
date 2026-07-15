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
    dado_imovel = {
        "type": "object",
        "additionalProperties": False,
        "required": ["tipo", "valor", "confianca", "precisa_revisao", "evidencia"],
        "properties": {
            "tipo": {"type": "string"},
            "valor": {"type": "string"},
            "confianca": {"type": "number", "minimum": 0, "maximum": 1},
            "precisa_revisao": {"type": "boolean"},
            "evidencia": evidencia,
        },
    }
    ato_registral = {
        "type": "object",
        "additionalProperties": False,
        "required": [
            "ordem",
            "identificador",
            "data",
            "natureza",
            "resumo",
            "titulares",
            "valor",
            "referencia_cancelamento",
            "situacao",
            "evidencia",
        ],
        "properties": {
            "ordem": {"type": "integer"},
            "identificador": {"type": "string"},
            "data": {"type": ["string", "null"]},
            "natureza": {
                "type": "string",
                "enum": ["abertura", "aquisicao", "onus", "cancelamento", "averbacao", "outro"],
            },
            "resumo": {"type": "string"},
            "titulares": {"type": "array", "items": {"type": "string"}},
            "valor": {"type": ["string", "null"]},
            "referencia_cancelamento": {"type": ["string", "null"]},
            "situacao": {
                "type": "string",
                "enum": ["ativo", "cancelado", "historico", "incerto"],
            },
            "evidencia": evidencia,
        },
    }
    onus_restricao = {
        "type": "object",
        "additionalProperties": False,
        "required": ["tipo", "ato", "resumo", "situacao", "cancelado_por", "evidencia"],
        "properties": {
            "tipo": {"type": "string"},
            "ato": {"type": "string"},
            "resumo": {"type": "string"},
            "situacao": {
                "type": "string",
                "enum": ["ativo", "cancelado", "historico", "incerto"],
            },
            "cancelado_por": {"type": ["string", "null"]},
            "evidencia": evidencia,
        },
    }
    analise_imovel = {
        "type": "object",
        "additionalProperties": False,
        "required": [
            "identificacao",
            "descricao",
            "proprietarios_atuais",
            "forma_aquisicao",
            "valor_venal",
            "atos_registrais",
            "onus_restricoes",
            "divergencias",
            "alertas",
        ],
        "properties": {
            "identificacao": {"type": "array", "items": dado_imovel},
            "descricao": {"type": "array", "items": dado_imovel},
            "proprietarios_atuais": {"type": "array", "items": dado_imovel},
            "forma_aquisicao": {"type": "array", "items": dado_imovel},
            "valor_venal": {"type": "array", "items": dado_imovel},
            "atos_registrais": {"type": "array", "items": ato_registral},
            "onus_restricoes": {"type": "array", "items": onus_restricao},
            "divergencias": {"type": "array", "items": {"type": "string"}},
            "alertas": {"type": "array", "items": {"type": "string"}},
        },
    }
    return {
        "type": "json_schema",
        "name": "preenchimento_seguro_escritura",
        "strict": True,
        "schema": {
            "type": "object",
            "additionalProperties": False,
            "required": ["campos", "analise_imovel", "alertas"],
            "properties": {
                "campos": {"type": "array", "items": item},
                "analise_imovel": analise_imovel,
                "alertas": {"type": "array", "items": {"type": "string"}},
            },
        },
    }
