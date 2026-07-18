begin;

create table if not exists public.vinculos_casal (
  id uuid primary key default gen_random_uuid(),
  criador_id uuid not null references auth.users(id) on delete cascade,
  parceiro_id uuid references auth.users(id) on delete cascade,
  codigo_convite text not null unique check (char_length(codigo_convite) between 6 and 12),
  status text not null default 'pendente' check (status in ('pendente', 'ativo', 'encerrado')),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  check (parceiro_id is null or parceiro_id <> criador_id),
  check (status <> 'ativo' or parceiro_id is not null)
);

create unique index if not exists vinculos_casal_criador_aberto_idx
  on public.vinculos_casal (criador_id)
  where status in ('pendente', 'ativo');

create unique index if not exists vinculos_casal_parceiro_ativo_idx
  on public.vinculos_casal (parceiro_id)
  where status = 'ativo';

drop trigger if exists vinculos_casal_atualizado_em on public.vinculos_casal;
create trigger vinculos_casal_atualizado_em
before update on public.vinculos_casal
for each row execute function public.definir_atualizado_em();

alter table public.vinculos_casal enable row level security;
alter table public.vinculos_casal force row level security;

drop policy if exists vinculos_casal_dos_membros on public.vinculos_casal;
create policy vinculos_casal_dos_membros
on public.vinculos_casal
for all
using (auth.uid() in (criador_id, parceiro_id))
with check (auth.uid() in (criador_id, parceiro_id));

alter table public.movimentacoes
  add column if not exists compartilhada_casal boolean not null default false;

create index if not exists movimentacoes_casal_idx
  on public.movimentacoes (usuario_id, mes_competencia)
  where compartilhada_casal;

commit;
