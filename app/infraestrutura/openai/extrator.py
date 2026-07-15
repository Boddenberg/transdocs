import base64
import json
from dataclasses import dataclass
from functools import lru_cache
from typing import Any

from openai import OpenAI
from pydantic import ValidationError

from app.core.configuracao import Configuracoes, obter_configuracoes
from app.core.erros import ErroConfiguracao
from app.dominio.arquivos import ArquivoValidado
from app.dominio.documentos import ResultadoExtracao, grupos_do_resultado
from app.dominio.falhas import FalhaOpenAI
from app.infraestrutura.openai.prompt_extracao import (
    INSTRUCOES_EXTRACAO,
    ORIENTACAO_USUARIO,
)
from app.infraestrutura.openai.schema_extracao import formato_resultado_extracao


@dataclass(frozen=True, slots=True)
class RespostaExtracao:
    resultado: ResultadoExtracao
    modelo: str
    estrategia: str
    tokens_entrada: int | None
    tokens_saida: int | None


class ExtratorOpenAI:
    def __init__(self, cliente: OpenAI, configuracoes: Configuracoes) -> None:
        self._cliente = cliente
        self._configuracoes = configuracoes

    def extrair_de_texto(self, texto: str) -> RespostaExtracao:
        entrada = [
            {
                "role": "user",
                "content": [
                    {
                        "type": "input_text",
                        "text": f"{ORIENTACAO_USUARIO}\n\nCONTEÚDO:\n{texto}",
                    }
                ],
            }
        ]
        return self._consultar(entrada, "texto_pdf")

    def extrair_de_imagem(self, arquivo: ArquivoValidado) -> RespostaExtracao:
        codificado = base64.b64encode(arquivo.conteudo).decode("ascii")
        entrada = [
            {
                "role": "user",
                "content": [
                    {"type": "input_text", "text": ORIENTACAO_USUARIO},
                    {
                        "type": "input_image",
                        "image_url": f"data:{arquivo.tipo_mime};base64,{codificado}",
                        "detail": "high",
                    },
                ],
            }
        ]
        return self._consultar(entrada, "visao_imagem")

    def extrair_de_pdf_visual(self, arquivo: ArquivoValidado) -> RespostaExtracao:
        codificado = base64.b64encode(arquivo.conteudo).decode("ascii")
        entrada = [
            {
                "role": "user",
                "content": [
                    {"type": "input_text", "text": ORIENTACAO_USUARIO},
                    {
                        "type": "input_file",
                        "filename": arquivo.nome_seguro,
                        "file_data": f"data:application/pdf;base64,{codificado}",
                        "detail": "high",
                    },
                ],
            }
        ]
        return self._consultar(entrada, "visao_pdf")

    def _consultar(self, entrada: list[dict[str, Any]], estrategia: str) -> RespostaExtracao:
        try:
            resposta = self._cliente.responses.create(
                model=self._configuracoes.openai_modelo,
                instructions=INSTRUCOES_EXTRACAO,
                input=entrada,
                text={"format": formato_resultado_extracao()},
                store=False,
            )
            resultado = ResultadoExtracao.model_validate_json(resposta.output_text)
        except (ValidationError, json.JSONDecodeError) as erro:
            raise FalhaOpenAI("A resposta da IA não corresponde ao schema.") from erro
        except Exception as erro:
            raise FalhaOpenAI("Falha ao consultar a OpenAI.") from erro

        uso = getattr(resposta, "usage", None)
        return RespostaExtracao(
            resultado=_normalizar_revisao(resultado),
            modelo=self._configuracoes.openai_modelo,
            estrategia=estrategia,
            tokens_entrada=getattr(uso, "input_tokens", None),
            tokens_saida=getattr(uso, "output_tokens", None),
        )


def _normalizar_revisao(resultado: ResultadoExtracao) -> ResultadoExtracao:
    alteracoes: dict[str, Any] = {}
    for grupo in grupos_do_resultado():
        itens = []
        for item in getattr(resultado, grupo):
            itens.append(
                item.model_copy(
                    update={
                        "confirmado": False,
                        "editado": False,
                        "precisa_revisao": (
                            item.precisa_revisao or item.valor is None or item.confianca < 0.8
                        ),
                    }
                )
            )
        alteracoes[grupo] = itens
    return resultado.model_copy(update=alteracoes)


@lru_cache
def obter_extrator_openai() -> ExtratorOpenAI:
    configuracoes = obter_configuracoes()
    if not configuracoes.openai_api_key:
        raise ErroConfiguracao("OpenAI", ["OPENAI_API_KEY"])
    cliente = OpenAI(
        api_key=configuracoes.openai_api_key,
        timeout=configuracoes.openai_timeout_segundos,
        max_retries=2,
    )
    return ExtratorOpenAI(cliente, configuracoes)
