begin;

create table if not exists public.preenchimentos (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  tipo_documento text not null check (tipo_documento = 'escritura_publica_venda_compra'),
  nome_minuta text not null check (char_length(nome_minuta) between 1 and 255),
  caminho_minuta text not null unique,
  hash_minuta text not null check (hash_minuta ~ '^[a-f0-9]{64}$'),
  tamanho_minuta_bytes bigint not null check (
    tamanho_minuta_bytes > 0 and tamanho_minuta_bytes <= 52428800
  ),
  status text not null default 'pendente' check (status in (
    'pendente', 'processando', 'aguardando_dados', 'pronto_para_gerar',
    'concluido', 'erro_arquivo', 'erro_openai', 'erro_interno'
  )),
  resultado jsonb not null default '{}'::jsonb,
  caminho_resultado text unique,
  nome_resultado text check (
    nome_resultado is null or char_length(nome_resultado) between 1 and 255
  ),
  modelo_ia text,
  tokens_entrada integer check (tokens_entrada is null or tokens_entrada >= 0),
  tokens_saida integer check (tokens_saida is null or tokens_saida >= 0),
  codigo_erro text,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (id, usuario_id)
);

create table if not exists public.preenchimentos_fontes (
  id uuid primary key default gen_random_uuid(),
  preenchimento_id uuid not null,
  usuario_id uuid not null references auth.users(id) on delete cascade,
  categoria text not null check (categoria in (
    'documentos_partes', 'estado_civil', 'enderecos', 'matricula_imovel',
    'cadastro_municipal', 'cndt', 'itbi', 'indisponibilidade', 'arquivamentos'
  )),
  nome_original text not null check (char_length(nome_original) between 1 and 255),
  nome_seguro text not null check (char_length(nome_seguro) between 1 and 180),
  tipo_mime text not null check (tipo_mime in (
    'application/pdf', 'image/jpeg', 'image/png', 'image/webp'
  )),
  tipo_arquivo text not null check (tipo_arquivo in ('pdf', 'imagem')),
  tamanho_bytes bigint not null check (tamanho_bytes > 0 and tamanho_bytes <= 52428800),
  caminho_storage text not null unique,
  hash_sha256 text not null check (hash_sha256 ~ '^[a-f0-9]{64}$'),
  criado_em timestamptz not null default now(),
  foreign key (preenchimento_id, usuario_id)
    references public.preenchimentos(id, usuario_id) on delete cascade
);

create index if not exists preenchimentos_usuario_criado_idx
  on public.preenchimentos (usuario_id, criado_em desc);
create index if not exists preenchimentos_usuario_status_idx
  on public.preenchimentos (usuario_id, status);
create index if not exists preenchimentos_fontes_preenchimento_idx
  on public.preenchimentos_fontes (preenchimento_id, criado_em);

drop trigger if exists preenchimentos_atualizado_em on public.preenchimentos;
create trigger preenchimentos_atualizado_em
before update on public.preenchimentos
for each row execute function public.definir_atualizado_em();

alter table public.preenchimentos enable row level security;
alter table public.preenchimentos_fontes enable row level security;
alter table public.preenchimentos force row level security;
alter table public.preenchimentos_fontes force row level security;

drop policy if exists preenchimentos_do_proprio_usuario on public.preenchimentos;
create policy preenchimentos_do_proprio_usuario on public.preenchimentos
for all to authenticated
using ((select auth.uid()) = usuario_id)
with check ((select auth.uid()) = usuario_id);

drop policy if exists preenchimentos_fontes_do_proprio_usuario
  on public.preenchimentos_fontes;
create policy preenchimentos_fontes_do_proprio_usuario
on public.preenchimentos_fontes
for all to authenticated
using ((select auth.uid()) = usuario_id)
with check (
  (select auth.uid()) = usuario_id
  and exists (
    select 1 from public.preenchimentos p
    where p.id = preenchimento_id and p.usuario_id = (select auth.uid())
  )
);

revoke all on public.preenchimentos from anon;
revoke all on public.preenchimentos_fontes from anon;
grant select, insert, update, delete on public.preenchimentos to authenticated;
grant select, insert, delete on public.preenchimentos_fontes to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'preenchimentos',
  'preenchimentos',
  false,
  52428800,
  array[
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/pdf',
    'image/jpeg',
    'image/png',
    'image/webp'
  ]
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists storage_preenchimentos_select on storage.objects;
create policy storage_preenchimentos_select on storage.objects
for select to authenticated
using (
  bucket_id = 'preenchimentos'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists storage_preenchimentos_insert on storage.objects;
create policy storage_preenchimentos_insert on storage.objects
for insert to authenticated
with check (
  bucket_id = 'preenchimentos'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists storage_preenchimentos_delete on storage.objects;
create policy storage_preenchimentos_delete on storage.objects
for delete to authenticated
using (
  bucket_id = 'preenchimentos'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

commit;
