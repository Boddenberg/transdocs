import json
import logging
from datetime import UTC, datetime


class FormatadorJson(logging.Formatter):
    def format(self, registro: logging.LogRecord) -> str:
        evento = {
            "momento": datetime.now(UTC).isoformat(),
            "nivel": registro.levelname,
            "logger": registro.name,
            "mensagem": registro.getMessage(),
        }
        for campo in (
            "metodo",
            "caminho",
            "status",
            "duracao_ms",
            "documento_id",
            "tipo_erro",
        ):
            if hasattr(registro, campo):
                evento[campo] = getattr(registro, campo)
        return json.dumps(evento, ensure_ascii=False, default=str)


def configurar_logs() -> None:
    manipulador = logging.StreamHandler()
    manipulador.setFormatter(FormatadorJson())
    raiz = logging.getLogger()
    raiz.handlers.clear()
    raiz.addHandler(manipulador)
    raiz.setLevel(logging.INFO)
