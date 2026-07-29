begin;

-- A materialização de uma ação pode mudar; a decisão de não ver o mesmo item
-- novamente não. Documento + chave é a identidade estável do próximo passo.
create table if not exists public.dispensas_acoes_documentos (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  documento_id uuid not null
    references public.documentos_financeiros(id) on delete cascade,
  chave text not null,
  criado_em timestamptz not null default now(),
  unique (documento_id, chave)
);

create index if not exists dispensas_acoes_documentos_usuario_idx
  on public.dispensas_acoes_documentos (usuario_id, criado_em desc);

alter table public.dispensas_acoes_documentos enable row level security;
alter table public.dispensas_acoes_documentos force row level security;
drop policy if exists dispensas_acoes_documentos_do_proprio_usuario
  on public.dispensas_acoes_documentos;
create policy dispensas_acoes_documentos_do_proprio_usuario
  on public.dispensas_acoes_documentos
  using (usuario_id = auth.uid())
  with check (usuario_id = auth.uid());
revoke all on public.dispensas_acoes_documentos from anon;
grant select, insert, update, delete
  on public.dispensas_acoes_documentos to authenticated;

-- Preserva todas as escolhas feitas antes desta tabela existir.
insert into public.dispensas_acoes_documentos (
  usuario_id,
  documento_id,
  chave
)
select usuario_id, documento_id, chave
from public.acoes_documentos
where status = 'dispensada'
on conflict (documento_id, chave) do nothing;

-- Corrige o aviso órfão informado em produção, mesmo que o UUID efêmero da
-- ação já tenha sido removido. O lembrete continua ativo; só a comunicação
-- "Próximos passos" deixa de reaparecer.
insert into public.dispensas_acoes_documentos (
  usuario_id,
  documento_id,
  chave
)
select
  documento.usuario_id,
  documento.id,
  'evento:' || evento.id::text
from public.documentos_financeiros as documento
join public.eventos_documento as evento
  on evento.documento_id = documento.id
 and evento.usuario_id = documento.usuario_id
where lower(coalesce(documento.nome_exibicao, documento.nome_original, ''))
    = lower('Fatura cartão Itaú de junho de 2026')
  and evento.titulo = 'Validade do documento'
  and evento.data = date '2026-06-09'
on conflict (documento_id, chave) do nothing;

update public.acoes_documentos as acao
set status = 'dispensada',
    erro = null,
    atualizado_em = now()
where exists (
  select 1
  from public.dispensas_acoes_documentos as dispensa
  where dispensa.usuario_id = acao.usuario_id
    and dispensa.documento_id = acao.documento_id
    and dispensa.chave = acao.chave
);

commit;
