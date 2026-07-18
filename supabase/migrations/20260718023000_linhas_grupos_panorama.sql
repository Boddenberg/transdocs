begin;

create table if not exists public.linhas_grupos_panorama (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  grupo_id uuid references public.grupos_fontes_panorama(id) on delete set null,
  fonte_chave text not null check (
    char_length(fonte_chave) between 3 and 300
    and fonte_chave ~ '^(entradas|contas_fixas|faturas_cartoes|dividas_financiamentos|despesas_variaveis|investimentos):.+'
  ),
  ordem integer not null default 0 check (ordem >= 0),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (usuario_id, fonte_chave)
);

create index if not exists linhas_grupos_panorama_grupo_ordem_idx
  on public.linhas_grupos_panorama (grupo_id, ordem, fonte_chave);

create or replace function public.validar_linha_grupo_panorama()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.grupo_id is not null and not exists (
    select 1
    from public.grupos_fontes_panorama as grupo
    where grupo.id = new.grupo_id
      and grupo.usuario_id = new.usuario_id
  ) then
    raise exception 'Grupo de linhas nao pertence ao usuario.';
  end if;

  return new;
end;
$$;

drop trigger if exists linhas_grupos_panorama_atualizado_em
  on public.linhas_grupos_panorama;
create trigger linhas_grupos_panorama_atualizado_em
before update on public.linhas_grupos_panorama
for each row execute function public.definir_atualizado_em();

drop trigger if exists linhas_grupos_panorama_validar_grupo
  on public.linhas_grupos_panorama;
create trigger linhas_grupos_panorama_validar_grupo
before insert or update on public.linhas_grupos_panorama
for each row execute function public.validar_linha_grupo_panorama();

alter table public.linhas_grupos_panorama enable row level security;
alter table public.linhas_grupos_panorama force row level security;

drop policy if exists linhas_grupos_panorama_do_proprio_usuario
  on public.linhas_grupos_panorama;
create policy linhas_grupos_panorama_do_proprio_usuario
on public.linhas_grupos_panorama
for all to authenticated
using ((select auth.uid()) = usuario_id)
with check ((select auth.uid()) = usuario_id);

commit;
