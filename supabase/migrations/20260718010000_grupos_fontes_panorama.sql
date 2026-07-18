begin;

create table if not exists public.grupos_fontes_panorama (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  nome text not null check (char_length(nome) between 1 and 80),
  ordem integer not null default 0 check (ordem >= 0),
  recolhido boolean not null default false,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (usuario_id, nome)
);

create table if not exists public.fontes_grupos_panorama (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  grupo_id uuid not null references public.grupos_fontes_panorama(id) on delete cascade,
  fonte_tipo text not null check (fonte_tipo in ('conta', 'divida')),
  fonte_id uuid not null,
  ordem integer not null default 0 check (ordem >= 0),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (usuario_id, fonte_tipo, fonte_id)
);

create index if not exists grupos_fontes_panorama_usuario_ordem_idx
  on public.grupos_fontes_panorama (usuario_id, ordem, nome);
create index if not exists fontes_grupos_panorama_grupo_ordem_idx
  on public.fontes_grupos_panorama (grupo_id, ordem);

create or replace function public.validar_fonte_grupo_panorama()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.grupos_fontes_panorama as grupo
    where grupo.id = new.grupo_id
      and grupo.usuario_id = new.usuario_id
  ) then
    raise exception 'Grupo de fontes nao pertence ao usuario.';
  end if;

  if new.fonte_tipo = 'conta' and not exists (
    select 1
    from public.contas as conta
    where conta.id = new.fonte_id
      and conta.usuario_id = new.usuario_id
  ) then
    raise exception 'Conta nao pertence ao usuario.';
  end if;

  if new.fonte_tipo = 'divida' and not exists (
    select 1
    from public.dividas as divida
    where divida.id = new.fonte_id
      and divida.usuario_id = new.usuario_id
  ) then
    raise exception 'Divida nao pertence ao usuario.';
  end if;

  return new;
end;
$$;

drop trigger if exists grupos_fontes_panorama_atualizado_em
  on public.grupos_fontes_panorama;
create trigger grupos_fontes_panorama_atualizado_em
before update on public.grupos_fontes_panorama
for each row execute function public.definir_atualizado_em();

drop trigger if exists fontes_grupos_panorama_atualizado_em
  on public.fontes_grupos_panorama;
create trigger fontes_grupos_panorama_atualizado_em
before update on public.fontes_grupos_panorama
for each row execute function public.definir_atualizado_em();

drop trigger if exists fontes_grupos_panorama_validar_fonte
  on public.fontes_grupos_panorama;
create trigger fontes_grupos_panorama_validar_fonte
before insert or update on public.fontes_grupos_panorama
for each row execute function public.validar_fonte_grupo_panorama();

alter table public.grupos_fontes_panorama enable row level security;
alter table public.fontes_grupos_panorama enable row level security;
alter table public.grupos_fontes_panorama force row level security;
alter table public.fontes_grupos_panorama force row level security;

drop policy if exists grupos_fontes_panorama_do_proprio_usuario
  on public.grupos_fontes_panorama;
create policy grupos_fontes_panorama_do_proprio_usuario
on public.grupos_fontes_panorama
for all to authenticated
using ((select auth.uid()) = usuario_id)
with check ((select auth.uid()) = usuario_id);

drop policy if exists fontes_grupos_panorama_do_proprio_usuario
  on public.fontes_grupos_panorama;
create policy fontes_grupos_panorama_do_proprio_usuario
on public.fontes_grupos_panorama
for all to authenticated
using ((select auth.uid()) = usuario_id)
with check ((select auth.uid()) = usuario_id);

commit;
