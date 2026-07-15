from app.infraestrutura.supabase.repositorio_documentos import _limpar_busca


def test_busca_remove_acentos_e_separadores() -> None:
    assert _limpar_busca("  João da Silva  ") == "joaodasilva"
    assert _limpar_busca("123.456.789-00") == "12345678900"


def test_busca_descarta_curingas_do_postgrest() -> None:
    assert _limpar_busca("Maria%_Souza") == "mariasouza"
