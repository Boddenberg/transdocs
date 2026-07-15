from uuid import UUID, uuid4

from app.core.configuracao import Configuracoes, obter_configuracoes
from app.core.erros import ErroServicoExterno
from app.dominio.sugestoes import AnexoSugestao
from app.infraestrutura.supabase.cliente import obter_cliente_supabase
from supabase import Client


class ArmazenamentoSugestoes:
    def __init__(self, cliente: Client, configuracoes: Configuracoes) -> None:
        self._cliente = cliente
        self._configuracoes = configuracoes

    def montar_caminho(self, *, usuario_id: UUID, sugestao_id: UUID, nome_seguro: str) -> str:
        return f"{usuario_id}/{sugestao_id}/{uuid4()}-{nome_seguro}"

    def salvar(self, caminho: str, anexo: AnexoSugestao) -> None:
        try:
            self._bucket().upload(
                caminho,
                anexo.conteudo,
                file_options={"content-type": anexo.tipo_mime, "upsert": "false"},
            )
        except Exception as erro:
            raise ErroServicoExterno(
                "Supabase Storage", "Não foi possível armazenar o anexo da sugestão."
            ) from erro

    def excluir(self, caminhos: list[str]) -> None:
        if not caminhos:
            return
        try:
            self._bucket().remove(caminhos)
        except Exception as erro:
            raise ErroServicoExterno(
                "Supabase Storage", "Não foi possível excluir os anexos da sugestão."
            ) from erro

    def criar_url_assinada(self, caminho: str) -> str:
        try:
            resposta = self._bucket().create_signed_url(
                caminho, self._configuracoes.validade_url_assinada_segundos
            )
        except Exception as erro:
            raise ErroServicoExterno(
                "Supabase Storage", "Não foi possível abrir o anexo da sugestão."
            ) from erro
        url = resposta.get("signedURL") or resposta.get("signedUrl") or resposta.get("signed_url")
        if not url:
            raise ErroServicoExterno(
                "Supabase Storage", "Não foi possível abrir o anexo da sugestão."
            )
        return str(url)

    def _bucket(self):
        return self._cliente.storage.from_(self._configuracoes.supabase_bucket_sugestoes)


def obter_armazenamento_sugestoes() -> ArmazenamentoSugestoes:
    return ArmazenamentoSugestoes(obter_cliente_supabase(), obter_configuracoes())
