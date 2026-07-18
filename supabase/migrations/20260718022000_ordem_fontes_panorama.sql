begin;

create table if not exists public.ordens_fontes_panorama (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  fonte_chave text not null check (
    char_length(fonte_chave) between 3 and 300
    and fonte_chave ~ '^(entradas|contas_fixas|faturas_cartoes|dividas_financiamentos|despesas_variaveis|investimentos):.+'
  ),
  ordem integer not null check (ordem >= 0),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (usuario_id, fonte_chave)
);

create index if not exists ordens_fontes_panorama_usuario_ordem_idx
  on public.ordens_fontes_panorama (usuario_id, ordem, fonte_chave);

drop trigger if exists ordens_fontes_panorama_atualizado_em
  on public.ordens_fontes_panorama;
create trigger ordens_fontes_panorama_atualizado_em
before update on public.ordens_fontes_panorama
for each row execute function public.definir_atualizado_em();

alter table public.ordens_fontes_panorama enable row level security;
alter table public.ordens_fontes_panorama force row level security;

drop policy if exists ordens_fontes_panorama_do_proprio_usuario
  on public.ordens_fontes_panorama;
create policy ordens_fontes_panorama_do_proprio_usuario
on public.ordens_fontes_panorama
for all to authenticated
using ((select auth.uid()) = usuario_id)
with check ((select auth.uid()) = usuario_id);

commit;
