from types import SimpleNamespace

import pytest

from app.core.configuracao import Configuracoes
from app.core.erros import ErroRequisicao
from app.dominio.audio import validar_audio
from app.infraestrutura.openai.transcritor import TranscritorAudioOpenAI


class _TranscricoesFalsas:
    def __init__(self) -> None:
        self.parametros = None

    def create(self, **kwargs):
        self.parametros = kwargs
        return SimpleNamespace(
            text=(
                "João e Maria são os vendedores. O preço é de R$ 500.000,00."
            )
        )


def test_valida_e_transcreve_audio_sem_persistir_o_arquivo() -> None:
    audio = validar_audio(
        conteudo=b"\x1aE\xdf\xa3" + b"audio-webm",
        nome="negociacao.webm",
        tipo_mime="audio/webm;codecs=opus",
        limite_bytes=1_000_000,
    )
    transcricoes = _TranscricoesFalsas()
    cliente = SimpleNamespace(
        audio=SimpleNamespace(transcriptions=transcricoes)
    )
    transcritor = TranscritorAudioOpenAI(
        cliente,
        Configuracoes(_env_file=None, OPENAI_API_KEY="teste"),
    )

    texto = transcritor.transcrever(audio)

    assert texto.startswith("João e Maria")
    assert transcricoes.parametros["model"] == "gpt-4o-mini-transcribe"
    assert transcricoes.parametros["language"] == "pt"
    assert transcricoes.parametros["file"][0] == "negociacao.webm"


def test_rejeita_arquivo_com_extensao_de_audio_e_conteudo_incompativel() -> None:
    with pytest.raises(ErroRequisicao, match="não corresponde"):
        validar_audio(
            conteudo=b"isto nao e audio",
            nome="negociacao.mp3",
            tipo_mime="audio/mpeg",
            limite_bytes=1_000_000,
        )
