from typing import Any

from app.core.erros import ErroRequisicao

TIPO_ESCRITURA_VENDA_COMPRA = "escritura_publica_venda_compra"

_TIPOS: dict[str, dict[str, Any]] = {
    TIPO_ESCRITURA_VENDA_COMPRA: {
        "id": TIPO_ESCRITURA_VENDA_COMPRA,
        "nome": "Escritura pública de venda e compra",
        "descricao": (
            "Monta campos e blocos marcados da escritura com dados declarados "
            "e documentos rastreáveis."
        ),
        "arquivo_base": {
            "rotulo": "Minuta da escritura",
            "descricao": "Arquivo DOCX que será preservado e preenchido nos marcadores existentes.",
            "obrigatorio": True,
            "aceita": [".docx"],
        },
        "fontes": [
            {
                "id": "documentos_caso",
                "nome": "Todos os documentos do caso",
                "descricao": (
                    "Envie juntos os documentos das partes, do imóvel, certidões e comprovantes. "
                    "A narrativa da negociação ajuda a atribuir os papéis sem depender da ordem."
                ),
                "multiplo": True,
                "obrigatorio": False,
            },
            {
                "id": "documentos_partes",
                "nome": "Documentos pessoais das partes",
                "descricao": "RG, CPF, CNH ou documentos equivalentes de vendedores e compradores.",
                "multiplo": True,
                "obrigatorio": False,
            },
            {
                "id": "estado_civil",
                "nome": "Estado civil e regime de bens",
                "descricao": "Certidões de nascimento, casamento, divórcio ou união estável.",
                "multiplo": True,
                "obrigatorio": False,
            },
            {
                "id": "enderecos",
                "nome": "Comprovantes de endereço",
                "descricao": "Documentos que comprovem o domicílio informado pelas partes.",
                "multiplo": True,
                "obrigatorio": False,
            },
            {
                "id": "matricula_imovel",
                "nome": "Matrícula do imóvel",
                "descricao": (
                    "Certidão de matrícula atualizada e documentos registrais relacionados."
                ),
                "multiplo": True,
                "obrigatorio": False,
            },
            {
                "id": "cadastro_municipal",
                "nome": "IPTU e cadastro municipal",
                "descricao": "Cadastro imobiliário, valor venal e documentos municipais.",
                "multiplo": True,
                "obrigatorio": False,
            },
            {
                "id": "cndt",
                "nome": "Certidões trabalhistas",
                "descricao": "CNDTs com número e data de validade.",
                "multiplo": True,
                "obrigatorio": False,
            },
            {
                "id": "itbi",
                "nome": "ITBI",
                "descricao": "Guia e comprovante de recolhimento do imposto de transmissão.",
                "multiplo": True,
                "obrigatorio": False,
            },
            {
                "id": "indisponibilidade",
                "nome": "Central de Indisponibilidade",
                "descricao": "Comprovantes das consultas e respectivos códigos HASH.",
                "multiplo": True,
                "obrigatorio": False,
            },
            {
                "id": "arquivamentos",
                "nome": "Outros arquivamentos",
                "descricao": "Outros documentos que devam ser relacionados no ato.",
                "multiplo": True,
                "obrigatorio": False,
            },
        ],
        "formatos_fontes": [".pdf", ".jpg", ".jpeg", ".png", ".webp"],
    }
}


def listar_tipos_preenchimento() -> list[dict[str, Any]]:
    return list(_TIPOS.values())


def obter_tipo_preenchimento(tipo_id: str) -> dict[str, Any]:
    tipo = _TIPOS.get(tipo_id)
    if tipo is None:
        raise ErroRequisicao("O tipo de documento selecionado não é suportado.")
    return tipo


def validar_categoria_fonte(tipo_id: str, categoria: str) -> str:
    tipo = obter_tipo_preenchimento(tipo_id)
    categorias = {item["id"] for item in tipo["fontes"]}
    if categoria not in categorias:
        raise ErroRequisicao("Uma categoria de documento comprobatório é inválida.")
    return categoria
