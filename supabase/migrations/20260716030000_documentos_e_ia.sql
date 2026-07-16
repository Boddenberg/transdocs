begin;

create table if not exists public.documentos_financeiros (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  tipo text not null check (tipo in (
    'extrato', 'fatura', 'holerite', 'divida', 'comprovante', 'beneficio', 'outro'
  )),
  nome_original text not null check (char_length(nome_original) between 1 and 255),
  tipo_mime text not null check (tipo_mime in (
    'application/pdf', 'image/jpeg', 'image/png', 'image/webp',
    'audio/mpeg', 'audio/mp4', 'audio/wav', 'audio/webm', 'audio/x-m4a'
  )),
  tamanho_bytes bigint not null check (tamanho_bytes > 0 and tamanho_bytes <= 26214400),
  caminho_storage text not null unique,
  hash_sha256 text not null check (hash_sha256 ~ '^[a-f0-9]{64}$'),
  mes_competencia date,
  status text not null default 'enviado' check (status in (
    'enviado', 'processando', 'revisao', 'concluido', 'erro'
  )),
  metadados jsonb not null default '{}'::jsonb,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (usuario_id, hash_sha256)
);

create table if not exists public.capturas_ia (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  documento_id uuid references public.documentos_financeiros(id) on delete set null,
  tipo_entrada text not null check (tipo_entrada in ('texto', 'audio', 'imagem', 'documento')),
  texto_original text,
  texto_normalizado text,
  status text not null default 'recebida' check (status in (
    'recebida', 'processando', 'aguardando_revisao', 'confirmada', 'descartada', 'erro'
  )),
  modelo_ia text,
  versao_prompt integer not null default 1,
  resultado jsonb not null default '{}'::jsonb,
  codigo_erro text,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create table if not exists public.propostas_ia (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  captura_id uuid not null references public.capturas_ia(id) on delete cascade,
  tipo text not null check (tipo in (
    'movimentacao', 'divida', 'recorrencia', 'conta', 'insight'
  )),
  dados jsonb not null,
  confianca numeric(4, 3) check (confianca is null or confianca between 0 and 1),
  status text not null default 'pendente' check (status in (
    'pendente', 'aceita', 'editada', 'rejeitada'
  )),
  entidade_criada_id uuid,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create table if not exists public.insights_ia (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  tipo text not null check (tipo in (
    'recorrencia', 'economia', 'anomalia', 'alerta', 'previsao', 'progresso'
  )),
  titulo text not null check (char_length(titulo) between 1 and 120),
  resumo text not null check (char_length(resumo) between 1 and 1000),
  impacto_estimado numeric(14, 2),
  confianca numeric(4, 3) check (confianca is null or confianca between 0 and 1),
  periodo_inicio date,
  periodo_fim date,
  evidencias jsonb not null default '[]'::jsonb,
  status text not null default 'novo' check (status in ('novo', 'lido', 'arquivado')),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create table if not exists public.usos_ia (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  captura_id uuid references public.capturas_ia(id) on delete set null,
  operacao text not null check (operacao in (
    'transcricao', 'extracao', 'analise', 'classificacao', 'chat'
  )),
  modelo text not null,
  tokens_entrada integer check (tokens_entrada is null or tokens_entrada >= 0),
  tokens_saida integer check (tokens_saida is null or tokens_saida >= 0),
  duracao_ms integer check (duracao_ms is null or duracao_ms >= 0),
  sucesso boolean not null default true,
  criado_em timestamptz not null default now()
);

create index if not exists documentos_usuario_criado_idx
  on public.documentos_financeiros (usuario_id, criado_em desc);
create index if not exists documentos_usuario_status_idx
  on public.documentos_financeiros (usuario_id, status, tipo);
create index if not exists capturas_usuario_status_idx
  on public.capturas_ia (usuario_id, status, criado_em desc);
create index if not exists propostas_captura_status_idx
  on public.propostas_ia (captura_id, status);
create index if not exists insights_usuario_status_idx
  on public.insights_ia (usuario_id, status, criado_em desc);
create index if not exists usos_ia_usuario_criado_idx
  on public.usos_ia (usuario_id, criado_em desc);

drop trigger if exists documentos_financeiros_atualizado_em on public.documentos_financeiros;
create trigger documentos_financeiros_atualizado_em
before update on public.documentos_financeiros
for each row execute function public.definir_atualizado_em();

drop trigger if exists capturas_ia_atualizado_em on public.capturas_ia;
create trigger capturas_ia_atualizado_em
before update on public.capturas_ia
for each row execute function public.definir_atualizado_em();

drop trigger if exists propostas_ia_atualizado_em on public.propostas_ia;
create trigger propostas_ia_atualizado_em
before update on public.propostas_ia
for each row execute function public.definir_atualizado_em();

drop trigger if exists insights_ia_atualizado_em on public.insights_ia;
create trigger insights_ia_atualizado_em
before update on public.insights_ia
for each row execute function public.definir_atualizado_em();

alter table public.documentos_financeiros enable row level security;
alter table public.capturas_ia enable row level security;
alter table public.propostas_ia enable row level security;
alter table public.insights_ia enable row level security;
alter table public.usos_ia enable row level security;

alter table public.documentos_financeiros force row level security;
alter table public.capturas_ia force row level security;
alter table public.propostas_ia force row level security;
alter table public.insights_ia force row level security;
alter table public.usos_ia force row level security;

drop policy if exists documentos_financeiros_do_proprio_usuario on public.documentos_financeiros;
create policy documentos_financeiros_do_proprio_usuario on public.documentos_financeiros
for all to authenticated
using ((select auth.uid()) = usuario_id)
with check ((select auth.uid()) = usuario_id);

drop policy if exists capturas_ia_do_proprio_usuario on public.capturas_ia;
create policy capturas_ia_do_proprio_usuario on public.capturas_ia
for all to authenticated
using ((select auth.uid()) = usuario_id)
with check ((select auth.uid()) = usuario_id);

drop policy if exists propostas_ia_do_proprio_usuario on public.propostas_ia;
create policy propostas_ia_do_proprio_usuario on public.propostas_ia
for all to authenticated
using ((select auth.uid()) = usuario_id)
with check (
  (select auth.uid()) = usuario_id
  and exists (
    select 1 from public.capturas_ia c
    where c.id = captura_id and c.usuario_id = (select auth.uid())
  )
);

drop policy if exists insights_ia_do_proprio_usuario on public.insights_ia;
create policy insights_ia_do_proprio_usuario on public.insights_ia
for all to authenticated
using ((select auth.uid()) = usuario_id)
with check ((select auth.uid()) = usuario_id);

drop policy if exists usos_ia_do_proprio_usuario on public.usos_ia;
create policy usos_ia_do_proprio_usuario on public.usos_ia
for select to authenticated
using ((select auth.uid()) = usuario_id);

revoke all on public.documentos_financeiros from anon;
revoke all on public.capturas_ia from anon;
revoke all on public.propostas_ia from anon;
revoke all on public.insights_ia from anon;
revoke all on public.usos_ia from anon;

grant select, insert, update, delete on public.documentos_financeiros to authenticated;
grant select, insert, update, delete on public.capturas_ia to authenticated;
grant select, insert, update, delete on public.propostas_ia to authenticated;
grant select, insert, update, delete on public.insights_ia to authenticated;
grant select on public.usos_ia to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  (
    'documentos-financeiros',
    'documentos-financeiros',
    false,
    26214400,
    array['application/pdf', 'image/jpeg', 'image/png', 'image/webp']
  ),
  (
    'audios-financeiros',
    'audios-financeiros',
    false,
    26214400,
    array['audio/mpeg', 'audio/mp4', 'audio/wav', 'audio/webm', 'audio/x-m4a']
  )
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists storage_financas_select on storage.objects;
create policy storage_financas_select on storage.objects
for select to authenticated
using (
  bucket_id in ('documentos-financeiros', 'audios-financeiros')
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists storage_financas_insert on storage.objects;
create policy storage_financas_insert on storage.objects
for insert to authenticated
with check (
  bucket_id in ('documentos-financeiros', 'audios-financeiros')
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists storage_financas_update on storage.objects;
create policy storage_financas_update on storage.objects
for update to authenticated
using (
  bucket_id in ('documentos-financeiros', 'audios-financeiros')
  and (storage.foldername(name))[1] = (select auth.uid())::text
)
with check (
  bucket_id in ('documentos-financeiros', 'audios-financeiros')
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists storage_financas_delete on storage.objects;
create policy storage_financas_delete on storage.objects
for delete to authenticated
using (
  bucket_id in ('documentos-financeiros', 'audios-financeiros')
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

commit;

