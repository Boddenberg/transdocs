begin;

-- A caixa e opt-in. O token torna o endereco impraticavel de adivinhar e a
-- lista de remetentes e obrigatoria antes de ativar o recebimento.
create table if not exists public.entrada_email_documentos (
  usuario_id uuid primary key references auth.users(id) on delete cascade,
  token uuid not null default gen_random_uuid() unique,
  ativo boolean not null default false,
  remetentes_permitidos text[] not null default '{}'::text[],
  ultimo_recebimento_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  check (not ativo or cardinality(remetentes_permitidos) > 0)
);

create table if not exists public.entradas_email_processadas_documentos (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  mensagem_id text not null,
  remetente text not null,
  quantidade_arquivos integer not null check (quantidade_arquivos > 0),
  criado_em timestamptz not null default now(),
  unique (usuario_id, mensagem_id)
);

alter table public.entrada_email_documentos enable row level security;
alter table public.entrada_email_documentos force row level security;
drop policy if exists entrada_email_do_proprio_usuario
  on public.entrada_email_documentos;
create policy entrada_email_do_proprio_usuario
  on public.entrada_email_documentos
  using (usuario_id = auth.uid())
  with check (usuario_id = auth.uid());

alter table public.entradas_email_processadas_documentos enable row level security;
alter table public.entradas_email_processadas_documentos force row level security;
drop policy if exists entradas_processadas_do_proprio_usuario
  on public.entradas_email_processadas_documentos;
create policy entradas_processadas_do_proprio_usuario
  on public.entradas_email_processadas_documentos
  using (usuario_id = auth.uid())
  with check (usuario_id = auth.uid());

revoke all on public.entrada_email_documentos from anon;
revoke all on public.entradas_email_processadas_documentos from anon;
grant select, insert, update, delete
  on public.entrada_email_documentos to authenticated;
grant select, insert, update, delete
  on public.entradas_email_processadas_documentos to authenticated;

commit;
