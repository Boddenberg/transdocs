begin;

alter table public.preenchimentos
  add column if not exists modo_criacao text not null default 'completar_minuta';

alter table public.preenchimentos
  drop constraint if exists preenchimentos_modo_criacao_check;

alter table public.preenchimentos
  add constraint preenchimentos_modo_criacao_check
  check (modo_criacao in ('completar_minuta', 'documento_completo'));

alter table public.preenchimentos
  add column if not exists modelo_referencia text;

alter table public.preenchimentos
  add column if not exists modelo_nome text;

alter table public.preenchimentos
  drop constraint if exists preenchimentos_modelo_nome_check;

alter table public.preenchimentos
  add constraint preenchimentos_modelo_nome_check
  check (modelo_nome is null or char_length(modelo_nome) between 1 and 120);

create table if not exists public.modelos_preenchimento (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  tipo_documento text not null check (
    tipo_documento = 'escritura_publica_venda_compra'
  ),
  nome text not null check (char_length(nome) between 1 and 120),
  descricao text not null default '' check (char_length(descricao) <= 400),
  nome_arquivo text not null check (char_length(nome_arquivo) between 1 and 255),
  caminho_storage text not null unique,
  hash_sha256 text not null check (hash_sha256 ~ '^[a-f0-9]{64}$'),
  tamanho_bytes bigint not null check (
    tamanho_bytes > 0 and tamanho_bytes <= 52428800
  ),
  total_campos integer not null check (total_campos >= 1),
  total_blocos integer not null check (total_blocos >= 1),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create index if not exists modelos_preenchimento_usuario_criado_idx
  on public.modelos_preenchimento (usuario_id, criado_em desc);

drop trigger if exists modelos_preenchimento_atualizado_em
  on public.modelos_preenchimento;
create trigger modelos_preenchimento_atualizado_em
before update on public.modelos_preenchimento
for each row execute function public.definir_atualizado_em();

alter table public.modelos_preenchimento enable row level security;
alter table public.modelos_preenchimento force row level security;

drop policy if exists modelos_preenchimento_do_proprio_usuario
  on public.modelos_preenchimento;
create policy modelos_preenchimento_do_proprio_usuario
on public.modelos_preenchimento
for all to authenticated
using ((select auth.uid()) = usuario_id)
with check ((select auth.uid()) = usuario_id);

revoke all on public.modelos_preenchimento from anon;
grant select, insert, update, delete on public.modelos_preenchimento to authenticated;

commit;
