from typing import Any
from uuid import UUID, uuid4

from app.core.configuracao import Configuracoes, obter_configuracoes
from app.core.erros import ErroRequisicao
from app.dominio.sugestoes import AnexoSugestao, CategoriaSugestao, StatusSugestao
from app.infraestrutura.supabase.armazenamento_sugestoes import (
    ArmazenamentoSugestoes,
    obter_armazenamento_sugestoes,
)
from app.infraestrutura.supabase.repositorio_sugestoes import (
    RepositorioSugestoes,
    obter_repositorio_sugestoes,
)


class ServicoSugestoes:
    def __init__(
        self,
        repositorio: RepositorioSugestoes,
        armazenamento: ArmazenamentoSugestoes,
        configuracoes: Configuracoes,
    ) -> None:
        self._repositorio = repositorio
        self._armazenamento = armazenamento
        self._configuracoes = configuracoes

    def registrar(
        self,
        *,
        usuario_id: UUID,
        usuario_email: str | None,
        categoria: CategoriaSugestao,
        mensagem: str,
        pagina_origem: str | None,
        anexos: list[AnexoSugestao],
    ) -> dict[str, Any]:
        mensagem = mensagem.strip()
        if not 3 <= len(mensagem) <= 5000:
            raise ErroRequisicao("Escreva uma mensagem entre 3 e 5.000 caracteres.")
        pagina = (pagina_origem or "").strip()[:500] or None
        if len(anexos) > 3:
            raise ErroRequisicao("Envie no máximo 3 imagens por mensagem.")

        sugestao_id = uuid4()
        sugestao = self._repositorio.criar(
            {
                "id": str(sugestao_id),
                "usuario_id": str(usuario_id),
                "usuario_email": usuario_email,
                "categoria": categoria.value,
                "mensagem": mensagem,
                "pagina_origem": pagina,
                "status": StatusSugestao.NOVA.value,
            }
        )
        caminhos_salvos: list[str] = []
        try:
            registros_anexos: list[dict[str, Any]] = []
            for anexo in anexos:
                caminho = self._armazenamento.montar_caminho(
                    usuario_id=usuario_id,
                    sugestao_id=sugestao_id,
                    nome_seguro=anexo.nome_seguro,
                )
                self._armazenamento.salvar(caminho, anexo)
                caminhos_salvos.append(caminho)
                registros_anexos.append(
                    {
                        "sugestao_id": str(sugestao_id),
                        "usuario_id": str(usuario_id),
                        "nome_original": anexo.nome_original,
                        "tipo_mime": anexo.tipo_mime,
                        "tamanho_bytes": anexo.tamanho_bytes,
                        "caminho_storage": caminho,
                    }
                )
            anexos_criados = self._repositorio.criar_anexos(registros_anexos)
        except Exception:
            try:
                self._armazenamento.excluir(caminhos_salvos)
            finally:
                self._repositorio.excluir(sugestao_id, usuario_id)
            raise
        return {**sugestao, "anexos": anexos_criados}

    def listar_todas(
        self,
        *,
        categoria: CategoriaSugestao | None,
        status: StatusSugestao | None,
        limite: int,
        deslocamento: int,
    ) -> dict[str, Any]:
        sugestoes = self._repositorio.listar_todas(
            categoria=categoria.value if categoria else None,
            status=status.value if status else None,
            limite=limite,
            deslocamento=deslocamento,
        )
        for sugestao in sugestoes:
            anexos = sugestao.pop("sugestoes_anexos", None) or sugestao.get("anexos") or []
            sugestao["anexos"] = [
                {
                    **anexo,
                    "url": self._armazenamento.criar_url_assinada(anexo["caminho_storage"]),
                    "expira_em_segundos": self._configuracoes.validade_url_assinada_segundos,
                }
                for anexo in anexos
            ]
        return {"itens": sugestoes, "limite": limite, "deslocamento": deslocamento}


def obter_servico_sugestoes() -> ServicoSugestoes:
    return ServicoSugestoes(
        obter_repositorio_sugestoes(),
        obter_armazenamento_sugestoes(),
        obter_configuracoes(),
    )
