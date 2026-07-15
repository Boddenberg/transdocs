from app.core.configuracao import Configuracoes


def test_migra_nome_antigo_configurado_no_ambiente(monkeypatch) -> None:
    monkeypatch.setenv("APP_NAME", "Transdocs")

    configuracoes = Configuracoes(_env_file=None)

    assert configuracoes.nome_aplicacao == "ThiagoDocs API"
