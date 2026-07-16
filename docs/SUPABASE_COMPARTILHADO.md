# Supabase compartilhado com o FiNanças

O projeto remoto do Supabase hospeda os dois produtos. O Transdocs preserva
suas tabelas, politicas e buckets originais; o FiNanças usa tabelas e buckets
adicionais no mesmo projeto.

## Convencao de migrations

O historico remoto e unico. Por isso, migrations do FiNanças tambem ficam
espelhadas em `supabase/migrations` deste repositorio e devem ser aplicadas a
partir daqui com `supabase db push`.

As tabelas financeiras atuais sao:

- `perfis`, `contas`, `categorias`, `cartoes_credito` e `movimentacoes`
- `recorrencias`, `dividas`, `parcelas_divida`, `orcamentos` e `metas`
- `documentos_financeiros`, `capturas_ia`, `propostas_ia`, `insights_ia` e
  `usos_ia`

Os buckets privados adicionais sao `documentos-financeiros` e
`audios-financeiros`. Todas as tabelas de produto usam RLS por `auth.uid()`.
