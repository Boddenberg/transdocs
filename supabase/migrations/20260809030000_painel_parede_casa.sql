-- Uma credencial de leitura para o painel de parede da Casa.
--
-- O painel é um tablet velho pendurado na cozinha: não faz login, não escreve
-- nada e não deve carregar a credencial de quem administra. Por isso não
-- reaproveita a chave da ponte do WhatsApp — aquela dispara pulso e consome
-- caixa de saída, e um aparelho que fica exposto na parede não é lugar para
-- ela. Aqui a chave só abre uma página que lê.
--
-- A chave bruta nunca entra no banco: somente SHA-256 e um prefixo de
-- identificação, como na ponte. A tabela não é exposta nem ao usuário
-- autenticado; geração, revogação e leitura passam pelo backend com a service
-- role.

create table public.paineis_parede_casa (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  vinculo_id uuid not null references public.vinculos_casal(id) on delete cascade,
  chave_hash text not null unique
    check (chave_hash ~ '^[0-9a-f]{64}$'),
  prefixo text not null
    check (char_length(prefixo) between 8 and 28),
  criado_em timestamptz not null default now(),
  revogado_em timestamptz
);

-- Um painel ativo por residência. Trocar a chave revoga a anterior, que é o
-- que faz "perdi o tablet" ter uma resposta de um clique.
create unique index paineis_parede_casa_ativo_idx
  on public.paineis_parede_casa (vinculo_id)
  where revogado_em is null;

create index paineis_parede_casa_usuario_idx
  on public.paineis_parede_casa (usuario_id, criado_em desc);

alter table public.paineis_parede_casa enable row level security;
alter table public.paineis_parede_casa force row level security;

revoke all on public.paineis_parede_casa from anon, authenticated;
