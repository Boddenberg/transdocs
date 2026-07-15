from functools import lru_cache

from openai import OpenAI

from app.core.configuracao import Configuracoes, obter_configuracoes
from app.core.erros import ErroConfiguracao, ErroRequisicao
from app.dominio.audio import AudioValidado
from app.dominio.falhas import FalhaOpenAI


class TranscritorAudioOpenAI:
    def __init__(self, cliente: OpenAI, configuracoes: Configuracoes) -> None:
        self._cliente = cliente
        self._configuracoes = configuracoes

    def transcrever(self, audio: AudioValidado) -> str:
        try:
            resposta = self._cliente.audio.transcriptions.create(
                model=self._configuracoes.openai_modelo_transcricao,
                file=(audio.nome, audio.conteudo, audio.tipo_mime),
                language="pt",
                prompt=(
                    "Transcreva fielmente em português do Brasil. Preserve nomes próprios, "
                    "números de documentos, valores, datas e condições de pagamento."
                ),
            )
        except Exception as erro:
            raise FalhaOpenAI("Falha ao transcrever o áudio.") from erro
        texto_bruto = getattr(resposta, "text", None)
        if not isinstance(texto_bruto, str) or not texto_bruto.strip():
            raise ErroRequisicao("Não foi possível identificar fala neste áudio.")
        texto = texto_bruto.strip()
        if len(texto) > 8000:
            raise ErroRequisicao(
                "A transcrição ficou longa demais. Envie um áudio mais curto."
            )
        return texto


@lru_cache
def obter_transcritor_audio_openai() -> TranscritorAudioOpenAI:
    configuracoes = obter_configuracoes()
    if not configuracoes.openai_api_key:
        raise ErroConfiguracao("OpenAI", ["OPENAI_API_KEY"])
    return TranscritorAudioOpenAI(
        OpenAI(
            api_key=configuracoes.openai_api_key,
            timeout=configuracoes.openai_timeout_segundos,
            max_retries=2,
        ),
        configuracoes,
    )
