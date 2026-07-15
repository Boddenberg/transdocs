from functools import lru_cache

from app.core.configuracao import obter_configuracoes
from app.core.erros import ErroConfiguracao
from supabase import Client, create_client


@lru_cache
def obter_cliente_supabase() -> Client:
    configuracoes = obter_configuracoes()
    ausentes = []
    if not configuracoes.supabase_url:
        ausentes.append("SUPABASE_URL")
    if not configuracoes.supabase_service_role_key:
        ausentes.append("SUPABASE_SERVICE_ROLE_KEY")
    if ausentes:
        raise ErroConfiguracao("Supabase", ausentes)
    return create_client(
        configuracoes.supabase_url,
        configuracoes.supabase_service_role_key,
    )
