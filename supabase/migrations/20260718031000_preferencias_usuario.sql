begin;

create table if not exists public.preferencias_usuario (
  usuario_id uuid primary key references auth.users(id) on delete cascade,
  panorama_incluir_historico boolean not null default false,
  panorama_meses_historico integer not null default 6
    check (panorama_meses_historico between 1 and 24),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

drop trigger if exists preferencias_usuario_atualizado_em on public.preferencias_usuario;
create trigger preferencias_usuario_atualizado_em
before update on public.preferencias_usuario
for each row execute function public.definir_atualizado_em();

alter table public.preferencias_usuario enable row level security;
alter table public.preferencias_usuario force row level security;

drop policy if exists preferencias_do_proprio_usuario on public.preferencias_usuario;
create policy preferencias_do_proprio_usuario
on public.preferencias_usuario
for all
using (auth.uid() = usuario_id)
with check (auth.uid() = usuario_id);

commit;
