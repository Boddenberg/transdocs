begin;

create table if not exists public.sugestoes (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  usuario_email text check (usuario_email is null or char_length(usuario_email) <= 320),
  categoria text not null check (categoria in ('sugestao', 'erro', 'dificuldade', 'outro')),
  mensagem text not null check (char_length(mensagem) between 3 and 5000),
  pagina_origem text check (pagina_origem is null or char_length(pagina_origem) <= 500),
  status text not null default 'nova' check (status in ('nova', 'lida', 'resolvida', 'arquivada')),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (id, usuario_id)
);

create table if not exists public.sugestoes_anexos (
  id uuid primary key default gen_random_uuid(),
  sugestao_id uuid not null,
  usuario_id uuid not null references auth.users(id) on delete cascade,
  nome_original text not null check (char_length(nome_original) between 1 and 255),
  tipo_mime text not null check (tipo_mime in ('image/jpeg', 'image/png', 'image/webp')),
  tamanho_bytes bigint not null check (tamanho_bytes > 0 and tamanho_bytes <= 10485760),
  caminho_storage text not null unique,
  criado_em timestamptz not null default now(),
  foreign key (sugestao_id, usuario_id)
    references public.sugestoes(id, usuario_id) on delete cascade
);

create index if not exists sugestoes_criado_idx
  on public.sugestoes (criado_em desc);
create index if not exists sugestoes_status_criado_idx
  on public.sugestoes (status, criado_em desc);
create index if not exists sugestoes_usuario_criado_idx
  on public.sugestoes (usuario_id, criado_em desc);
create index if not exists sugestoes_anexos_sugestao_idx
  on public.sugestoes_anexos (sugestao_id, criado_em);

drop trigger if exists sugestoes_atualizado_em on public.sugestoes;
create trigger sugestoes_atualizado_em
before update on public.sugestoes
for each row execute function public.definir_atualizado_em();

alter table public.sugestoes enable row level security;
alter table public.sugestoes_anexos enable row level security;
alter table public.sugestoes force row level security;
alter table public.sugestoes_anexos force row level security;

drop policy if exists sugestoes_do_proprio_usuario on public.sugestoes;
create policy sugestoes_do_proprio_usuario on public.sugestoes
for all to authenticated
using ((select auth.uid()) = usuario_id)
with check ((select auth.uid()) = usuario_id);

drop policy if exists sugestoes_anexos_do_proprio_usuario on public.sugestoes_anexos;
create policy sugestoes_anexos_do_proprio_usuario on public.sugestoes_anexos
for all to authenticated
using ((select auth.uid()) = usuario_id)
with check (
  (select auth.uid()) = usuario_id
  and exists (
    select 1 from public.sugestoes s
    where s.id = sugestao_id and s.usuario_id = (select auth.uid())
  )
);

revoke all on public.sugestoes from anon;
revoke all on public.sugestoes_anexos from anon;
grant select, insert on public.sugestoes to authenticated;
grant select, insert on public.sugestoes_anexos to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'sugestoes',
  'sugestoes',
  false,
  10485760,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists storage_sugestoes_select on storage.objects;
create policy storage_sugestoes_select on storage.objects
for select to authenticated
using (
  bucket_id = 'sugestoes'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists storage_sugestoes_insert on storage.objects;
create policy storage_sugestoes_insert on storage.objects
for insert to authenticated
with check (
  bucket_id = 'sugestoes'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists storage_sugestoes_delete on storage.objects;
create policy storage_sugestoes_delete on storage.objects
for delete to authenticated
using (
  bucket_id = 'sugestoes'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

commit;
