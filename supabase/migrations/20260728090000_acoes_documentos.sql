begin;

-- O documento sugere o proximo passo, mas dados de outros apps continuam
-- rascunhos ate a revisao explicita no app que e dono deles.
create table if not exists public.acoes_documentos (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  documento_id uuid not null
    references public.documentos_financeiros(id) on delete cascade,
  chave text not null,
  tipo text not null
    check (tipo in ('lembrete', 'garantia', 'financeiro', 'receita')),
  titulo text not null,
  resumo text not null,
  confianca numeric(5,4) not null default 1
    check (confianca between 0 and 1),
  status text not null default 'pendente'
    check (status in ('pendente', 'processando', 'aplicada', 'dispensada', 'falhou')),
  resultado_id text,
  resultado_caminho text,
  erro text,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (documento_id, chave)
);

create index if not exists acoes_documentos_usuario_status_idx
  on public.acoes_documentos (usuario_id, status, criado_em desc);

alter table public.acoes_documentos enable row level security;
alter table public.acoes_documentos force row level security;
drop policy if exists acoes_documentos_do_proprio_usuario
  on public.acoes_documentos;
create policy acoes_documentos_do_proprio_usuario
  on public.acoes_documentos
  using (usuario_id = auth.uid())
  with check (usuario_id = auth.uid());
revoke all on public.acoes_documentos from anon;
grant select, insert, update, delete
  on public.acoes_documentos to authenticated;

commit;
