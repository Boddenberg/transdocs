from uuid import UUID, uuid4

from app.core.configuracao import Configuracoes, obter_configuracoes
from app.core.erros import ErroServicoExterno
from app.infraestrutura.supabase.cliente import obter_cliente_supabase
from supabase import Client


class ArmazenamentoPreenchimentos:
    def __init__(self, cliente: Client, configuracoes: Configuracoes) -> None:
        self._cliente = cliente
        self._configuracoes = configuracoes

    def montar_caminho(
        self,
        *,
        usuario_id: UUID,
        preenchimento_id: UUID,
        grupo: str,
        nome_seguro: str,
    ) -> str:
        return f"{usuario_id}/{preenchimento_id}/{grupo}/{uuid4()}-{nome_seguro}"

    def salvar(self, caminho: str, conteudo: bytes, tipo_mime: str) -> None:
        try:
            self._bucket().upload(
                caminho,
                conteudo,
                file_options={"content-type": tipo_mime, "upsert": "false"},
            )
        except Exception as erro:
            raise ErroServicoExterno(
                "Supabase Storage", "Não foi possível armazenar o arquivo do preenchimento."
            ) from erro

    def baixar(self, caminho: str) -> bytes:
        try:
            return self._bucket().download(caminho)
        except Exception as erro:
            raise ErroServicoExterno(
                "Supabase Storage", "Não foi possível ler o arquivo do preenchimento."
            ) from erro

    def excluir(self, caminhos: list[str]) -> None:
        if not caminhos:
            return
        try:
            self._bucket().remove(caminhos)
        except Exception as erro:
            raise ErroServicoExterno(
                "Supabase Storage", "Não foi possível excluir os arquivos do preenchimento."
            ) from erro

    def criar_url_assinada(self, caminho: str) -> str:
        try:
            resposta = self._bucket().create_signed_url(
                caminho, self._configuracoes.validade_url_assinada_segundos
            )
        except Exception as erro:
            raise ErroServicoExterno(
                "Supabase Storage", "Não foi possível preparar o arquivo preenchido."
            ) from erro
        url = resposta.get("signedURL") or resposta.get("signedUrl") or resposta.get("signed_url")
        if not url:
            raise ErroServicoExterno(
                "Supabase Storage", "Não foi possível preparar o arquivo preenchido."
            )
        return str(url)

    def _bucket(self):
        return self._cliente.storage.from_(self._configuracoes.supabase_bucket_preenchimentos)


def obter_armazenamento_preenchimentos() -> ArmazenamentoPreenchimentos:
    return ArmazenamentoPreenchimentos(obter_cliente_supabase(), obter_configuracoes())
