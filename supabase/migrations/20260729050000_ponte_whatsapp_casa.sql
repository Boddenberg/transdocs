-- Uma credencial própria da residência para a ponte local do WhatsApp.
--
-- A chave bruta nunca entra no banco: somente SHA-256 e um prefixo de
-- identificação. A tabela não é exposta nem ao usuário autenticado; geração,
-- rotação, revogação e leitura passam pelo backend com a service role.

create table public.pontes_whatsapp_casa (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  vinculo_id uuid not null references public.vinculos_casal(id) on delete cascade,
  chave_hash text not null unique
    check (chave_hash ~ '^[0-9a-f]{64}$'),
  prefixo text not null
    check (char_length(prefixo) between 8 and 24),
  criada_em timestamptz not null default now(),
  revogada_em timestamptz
);

create unique index pontes_whatsapp_casa_ativa_idx
  on public.pontes_whatsapp_casa (vinculo_id)
  where revogada_em is null;

create index pontes_whatsapp_casa_usuario_idx
  on public.pontes_whatsapp_casa (usuario_id, criada_em desc);

alter table public.pontes_whatsapp_casa enable row level security;
alter table public.pontes_whatsapp_casa force row level security;

revoke all on public.pontes_whatsapp_casa from anon, authenticated;
