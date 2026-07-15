begin;

create extension if not exists pgcrypto;

create table if not exists public.documentos (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  nome_original text not null check (char_length(nome_original) between 1 and 255),
  nome_seguro text not null check (char_length(nome_seguro) between 1 and 180),
  tipo_mime text not null check (tipo_mime in (
    'application/pdf', 'image/jpeg', 'image/png', 'image/webp'
  )),
  tipo_arquivo text not null check (tipo_arquivo in ('pdf', 'imagem')),
  tamanho_bytes bigint not null check (tamanho_bytes > 0 and tamanho_bytes <= 26214400),
  caminho_storage text not null unique,
  hash_sha256 text not null check (hash_sha256 ~ '^[a-f0-9]{64}$'),
  status text not null default 'pendente' check (status in (
    'pendente', 'processando', 'concluido', 'erro_leitura',
    'erro_arquivo', 'erro_openai', 'erro_interno'
  )),
  revisado boolean not null default false,
  codigo_erro text,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  ultima_alteracao_em timestamptz not null default now(),
  unique (usuario_id, hash_sha256)
);

create table if not exists public.extracoes_documentos (
  id uuid primary key default gen_random_uuid(),
  documento_id uuid not null unique references public.documentos(id) on delete cascade,
  usuario_id uuid not null references auth.users(id) on delete cascade,
  resultado jsonb not null default '{}'::jsonb,
  modelo_ia text,
  versao_schema integer not null default 1,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create table if not exists public.correcoes_extracao (
  id uuid primary key default gen_random_uuid(),
  documento_id uuid not null references public.documentos(id) on delete cascade,
  extracao_id uuid not null references public.extracoes_documentos(id) on delete cascade,
  usuario_id uuid not null references auth.users(id) on delete cascade,
  caminho_campo text not null check (char_length(caminho_campo) between 1 and 300),
  valor_anterior jsonb,
  valor_novo jsonb,
  confirmado boolean not null default false,
  criado_em timestamptz not null default now()
);

create table if not exists public.processamentos (
  id uuid primary key default gen_random_uuid(),
  documento_id uuid not null references public.documentos(id) on delete cascade,
  usuario_id uuid not null references auth.users(id) on delete cascade,
  status text not null check (status in ('iniciado', 'concluido', 'erro')),
  estrategia text,
  modelo_ia text,
  tokens_entrada integer,
  tokens_saida integer,
  codigo_erro text,
  iniciado_em timestamptz not null default now(),
  concluido_em timestamptz
);

create index if not exists documentos_usuario_criado_idx
  on public.documentos (usuario_id, criado_em desc);
create index if not exists documentos_usuario_status_idx
  on public.documentos (usuario_id, status);
create index if not exists correcoes_documento_criado_idx
  on public.correcoes_extracao (documento_id, criado_em desc);
create index if not exists processamentos_documento_idx
  on public.processamentos (documento_id, iniciado_em desc);

create or replace function public.definir_atualizado_em()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.atualizado_em = now();
  return new;
end;
$$;

drop trigger if exists documentos_atualizado_em on public.documentos;
create trigger documentos_atualizado_em
before update on public.documentos
for each row execute function public.definir_atualizado_em();

drop trigger if exists extracoes_atualizado_em on public.extracoes_documentos;
create trigger extracoes_atualizado_em
before update on public.extracoes_documentos
for each row execute function public.definir_atualizado_em();

alter table public.documentos enable row level security;
alter table public.extracoes_documentos enable row level security;
alter table public.correcoes_extracao enable row level security;
alter table public.processamentos enable row level security;

alter table public.documentos force row level security;
alter table public.extracoes_documentos force row level security;
alter table public.correcoes_extracao force row level security;
alter table public.processamentos force row level security;

drop policy if exists documentos_do_proprio_usuario on public.documentos;
create policy documentos_do_proprio_usuario on public.documentos
for all to authenticated
using ((select auth.uid()) = usuario_id)
with check ((select auth.uid()) = usuario_id);

drop policy if exists extracoes_do_proprio_usuario on public.extracoes_documentos;
create policy extracoes_do_proprio_usuario on public.extracoes_documentos
for all to authenticated
using (
  (select auth.uid()) = usuario_id
  and exists (
    select 1 from public.documentos d
    where d.id = documento_id and d.usuario_id = (select auth.uid())
  )
)
with check (
  (select auth.uid()) = usuario_id
  and exists (
    select 1 from public.documentos d
    where d.id = documento_id and d.usuario_id = (select auth.uid())
  )
);

drop policy if exists correcoes_do_proprio_usuario on public.correcoes_extracao;
create policy correcoes_do_proprio_usuario on public.correcoes_extracao
for all to authenticated
using ((select auth.uid()) = usuario_id)
with check (
  (select auth.uid()) = usuario_id
  and exists (
    select 1 from public.documentos d
    where d.id = documento_id and d.usuario_id = (select auth.uid())
  )
);

drop policy if exists processamentos_do_proprio_usuario on public.processamentos;
create policy processamentos_do_proprio_usuario on public.processamentos
for select to authenticated
using ((select auth.uid()) = usuario_id);

revoke all on public.documentos from anon;
revoke all on public.extracoes_documentos from anon;
revoke all on public.correcoes_extracao from anon;
revoke all on public.processamentos from anon;

grant select, insert, update, delete on public.documentos to authenticated;
grant select, insert, update, delete on public.extracoes_documentos to authenticated;
grant select, insert on public.correcoes_extracao to authenticated;
grant select on public.processamentos to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'documentos',
  'documentos',
  false,
  26214400,
  array['application/pdf', 'image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists storage_documentos_select on storage.objects;
create policy storage_documentos_select on storage.objects
for select to authenticated
using (
  bucket_id = 'documentos'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists storage_documentos_insert on storage.objects;
create policy storage_documentos_insert on storage.objects
for insert to authenticated
with check (
  bucket_id = 'documentos'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists storage_documentos_update on storage.objects;
create policy storage_documentos_update on storage.objects
for update to authenticated
using (
  bucket_id = 'documentos'
  and (storage.foldername(name))[1] = (select auth.uid())::text
)
with check (
  bucket_id = 'documentos'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists storage_documentos_delete on storage.objects;
create policy storage_documentos_delete on storage.objects
for delete to authenticated
using (
  bucket_id = 'documentos'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

commit;
