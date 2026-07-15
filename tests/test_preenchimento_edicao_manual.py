import pytest

from app.aplicacao.preenchimentos.servico import (
    _registrar_edicoes_manuais,
    _resolver_substituicoes,
    _validar_valores_manuais,
)
from app.core.erros import ErroRequisicao
from app.dominio.preenchimentos import (
    ResultadoPreenchimento,
    StatusCampoPreenchimento,
)
from app.infraestrutura.arquivos.docx import analisar_docx
from tests.test_preenchimento_docx import _docx_minimo


def _resultado(status: StatusCampoPreenchimento, valor: str | None):
    campo = analisar_docx(_docx_minimo()).campos[0]
    campo.status = status
    campo.valor = valor
    return ResultadoPreenchimento.criar(
        tipo_documento="escritura_publica_venda_compra",
        campos=[campo],
    )


def test_valor_manual_substitui_sugestao_e_preserva_original_para_auditoria() -> None:
    resultado = _resultado(StatusCampoPreenchimento.ENCONTRADO, "111.111.111-11")
    campo = resultado.campos[0]

    substituicoes = _resolver_substituicoes(
        resultado,
        ids_selecionados={campo.id},
        valores_manuais={campo.id: "222.222.222-22"},
    )
    auditado = _registrar_edicoes_manuais(
        resultado, {campo.id: "222.222.222-22"}
    )

    assert substituicoes == {campo.id: "222.222.222-22"}
    assert auditado.campos[0].valor == "222.222.222-22"
    assert auditado.campos[0].valor_original == "111.111.111-11"
    assert auditado.campos[0].editado_pelo_usuario is True
    assert resultado.campos[0].valor == "111.111.111-11"


def test_lacuna_sem_fonte_pode_ser_preenchida_explicitamente_pelo_usuario() -> None:
    resultado = _resultado(StatusCampoPreenchimento.AUSENTE, None)
    campo = resultado.campos[0]

    substituicoes = _resolver_substituicoes(
        resultado,
        ids_selecionados={campo.id},
        valores_manuais={campo.id: "valor informado pelo usuário"},
    )

    assert substituicoes == {campo.id: "valor informado pelo usuário"}


def test_campo_sem_fonte_e_sem_valor_manual_continua_bloqueado() -> None:
    resultado = _resultado(StatusCampoPreenchimento.AUSENTE, None)
    campo = resultado.campos[0]

    with pytest.raises(ErroRequisicao, match="Preencha manualmente"):
        _resolver_substituicoes(
            resultado,
            ids_selecionados={campo.id},
            valores_manuais={},
        )


def test_edicao_de_campo_nao_selecionado_e_rejeitada() -> None:
    resultado = _resultado(StatusCampoPreenchimento.ENCONTRADO, "original")
    campo = resultado.campos[0]

    with pytest.raises(ErroRequisicao, match="selecionado"):
        _validar_valores_manuais(
            {campo.id: "editado"},
            campos_por_id={campo.id: campo},
            ids_selecionados=set(),
        )
