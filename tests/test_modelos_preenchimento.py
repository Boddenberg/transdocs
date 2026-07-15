from pathlib import Path
from uuid import UUID

from app.aplicacao.preenchimentos.modelos import (
    MODELO_SISTEMA_ESCRITURA_ID,
    ServicoModelosPreenchimento,
)
from app.core.configuracao import Configuracoes
from app.infraestrutura.arquivos.docx import (
    analisar_docx,
    corresponde_escritura_venda_compra,
)


class _RepositorioNaoUsado:
    pass


class _ArmazenamentoNaoUsado:
    pass


def test_modelo_estruturado_do_sistema_cobre_a_escritura_inteira() -> None:
    caminho = (
        Path(__file__).resolve().parents[1]
        / "app"
        / "recursos"
        / "modelos"
        / "escritura_venda_compra_estruturada.docx"
    )

    analise = analisar_docx(caminho.read_bytes())

    assert corresponde_escritura_venda_compra(analise)
    assert len(analise.campos) == 13
    assert all(campo.marcador.startswith("[PREENCHER:") for campo in analise.campos)


def test_resolve_modelo_do_sistema_sem_arquivo_enviado() -> None:
    servico = ServicoModelosPreenchimento(
        repositorio=_RepositorioNaoUsado(),  # type: ignore[arg-type]
        armazenamento=_ArmazenamentoNaoUsado(),  # type: ignore[arg-type]
        configuracoes=Configuracoes(_env_file=None),
    )

    modelo = servico.resolver(
        usuario_id=UUID("00000000-0000-0000-0000-000000000001"),
        modelo_id=MODELO_SISTEMA_ESCRITURA_ID,
    )

    assert modelo.id == MODELO_SISTEMA_ESCRITURA_ID
    assert modelo.arquivo.nome_original.endswith(".docx")
    assert modelo.arquivo.tamanho_bytes > 0
