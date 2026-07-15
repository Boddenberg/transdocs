from uuid import UUID, uuid4

import pytest

from app.aplicacao.sugestoes.servico import ServicoSugestoes
from app.core.configuracao import Configuracoes
from app.core.erros import ErroRequisicao
from app.dominio.sugestoes import CategoriaSugestao, validar_anexo_sugestao


class RepositorioFalso:
    def __init__(self) -> None:
        self.sugestao: dict | None = None
        self.anexos: list[dict] = []

    def criar(self, dados: dict) -> dict:
        self.sugestao = dados
        return {**dados, "criado_em": "2026-07-15T00:00:00Z"}

    def criar_anexos(self, dados: list[dict]) -> list[dict]:
        self.anexos = dados
        return [{**item, "id": str(uuid4())} for item in dados]

    def excluir(self, sugestao_id: UUID, usuario_id: UUID) -> None:
        self.sugestao = None


class ArmazenamentoFalso:
    def __init__(self) -> None:
        self.salvos: list[str] = []

    def montar_caminho(self, *, usuario_id: UUID, sugestao_id: UUID, nome_seguro: str) -> str:
        return f"{usuario_id}/{sugestao_id}/{nome_seguro}"

    def salvar(self, caminho: str, anexo) -> None:
        self.salvos.append(caminho)

    def excluir(self, caminhos: list[str]) -> None:
        self.salvos = [item for item in self.salvos if item not in caminhos]


def test_valida_print_png_e_sanitiza_nome() -> None:
    anexo = validar_anexo_sugestao(
        conteudo=b"\x89PNG\r\n\x1a\nconteudo",
        nome="Print da revisão 01.PNG",
        tipo_mime="image/png",
        limite_bytes=1024,
    )

    assert anexo.nome_original == "Print da revisão 01.PNG"
    assert anexo.nome_seguro == "print-da-revisao-01.png"
    assert anexo.tipo_mime == "image/png"


def test_rejeita_anexo_que_nao_e_imagem() -> None:
    with pytest.raises(ErroRequisicao, match="JPG, PNG ou WEBP"):
        validar_anexo_sugestao(
            conteudo=b"%PDF-1.7",
            nome="contrato.pdf",
            tipo_mime="application/pdf",
            limite_bytes=1024,
        )


def test_registra_sugestao_com_anexo_privado() -> None:
    repositorio = RepositorioFalso()
    armazenamento = ArmazenamentoFalso()
    servico = ServicoSugestoes(
        repositorio,  # type: ignore[arg-type]
        armazenamento,  # type: ignore[arg-type]
        Configuracoes(_env_file=None),
    )
    usuario_id = uuid4()
    anexo = validar_anexo_sugestao(
        conteudo=b"\xff\xd8\xffimagem",
        nome="erro.jpg",
        tipo_mime="image/jpeg",
        limite_bytes=1024,
    )

    criada = servico.registrar(
        usuario_id=usuario_id,
        usuario_email="teste@example.com",
        categoria=CategoriaSugestao.ERRO,
        mensagem="  O botão não respondeu.  ",
        pagina_origem="/app/documentos/123",
        anexos=[anexo],
    )

    assert criada["mensagem"] == "O botão não respondeu."
    assert criada["categoria"] == "erro"
    assert len(criada["anexos"]) == 1
    assert repositorio.anexos[0]["caminho_storage"].startswith(str(usuario_id))
    assert armazenamento.salvos == [repositorio.anexos[0]["caminho_storage"]]
