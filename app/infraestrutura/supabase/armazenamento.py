from uuid import UUID, uuid4

from app.core.configuracao import Configuracoes, obter_configuracoes
from app.core.erros import ErroServicoExterno
from app.dominio.arquivos import ArquivoValidado
from app.infraestrutura.supabase.cliente import obter_cliente_supabase
from supabase import Client


class ArmazenamentoDocumentos:
    def __init__(self, cliente: Client, configuracoes: Configuracoes) -> None:
        self._cliente = cliente
        self._configuracoes = configuracoes

    def montar_caminho(self, *, usuario_id: UUID, documento_id: UUID, nome_seguro: str) -> str:
        return f"{usuario_id}/{documento_id}/{uuid4()}-{nome_seguro}"

    def salvar(self, caminho: str, arquivo: ArquivoValidado) -> None:
        try:
            self._bucket().upload(
                caminho,
                arquivo.conteudo,
                file_options={"content-type": arquivo.tipo_mime, "upsert": "false"},
            )
        except Exception as erro:
            raise ErroServicoExterno(
                "Supabase Storage", "Não foi possível armazenar o documento."
            ) from erro

    def excluir(self, caminho: str) -> None:
        try:
            self._bucket().remove([caminho])
        except Exception as erro:
            raise ErroServicoExterno(
                "Supabase Storage", "Não foi possível excluir o arquivo agora."
            ) from erro

    def criar_url_assinada(self, caminho: str) -> str:
        try:
            resposta = self._bucket().create_signed_url(
                caminho, self._configuracoes.validade_url_assinada_segundos
            )
        except Exception as erro:
            raise ErroServicoExterno(
                "Supabase Storage", "Não foi possível abrir o documento agora."
            ) from erro
        url = resposta.get("signedURL") or resposta.get("signedUrl") or resposta.get("signed_url")
        if not url:
            raise ErroServicoExterno(
                "Supabase Storage", "Não foi possível abrir o documento agora."
            )
        return str(url)

    def baixar(self, caminho: str) -> bytes:
        try:
            return self._bucket().download(caminho)
        except Exception as erro:
            raise ErroServicoExterno(
                "Supabase Storage", "Não foi possível ler o documento agora."
            ) from erro

    def _bucket(self):
        return self._cliente.storage.from_(self._configuracoes.supabase_bucket_documentos)


def obter_armazenamento() -> ArmazenamentoDocumentos:
    return ArmazenamentoDocumentos(obter_cliente_supabase(), obter_configuracoes())
