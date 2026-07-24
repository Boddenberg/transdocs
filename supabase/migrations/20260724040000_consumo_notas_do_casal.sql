begin;

-- Notas de consumo do casal ---------------------------------------------------
--
-- Espelha os documentos do casal (20260723040000): uma nota continua pertencendo
-- a quem a enviou, mas pode ser levada ao espaco do casal — o mercado que e "meu
-- e do Victor". O dono propoe, o parceiro recebe uma notificacao e aceita; so
-- depois do aceite a nota aparece para os dois e as IAs (assistente do panorama
-- e a analise de consumo) podem considera-la.
--
-- `compartilhado_casal` marca a nota ja aceita. O default false preserva todas
-- as notas existentes como privadas.
alter table public.notas_consumo
  add column if not exists compartilhado_casal boolean not null default false;

create index if not exists notas_consumo_casal_idx
  on public.notas_consumo (usuario_id)
  where compartilhado_casal;

-- Solicitacoes de compartilhamento de nota: uma pessoa pede para levar a nota ao
-- casal e o parceiro aceita ou recusa. Enquanto pendente a nota NAO e do casal.
-- O retrato (estabelecimento/valor/data) deixa a notificacao e o hub mostrarem o
-- pedido sem depender do RLS da conta de quem enviou.
create table if not exists public.compartilhamentos_notas_casal (
  id uuid primary key default gen_random_uuid(),
  vinculo_id uuid not null references public.vinculos_casal(id) on delete cascade,
  nota_id uuid not null references public.notas_consumo(id) on delete cascade,
  usuario_id uuid not null references auth.users(id) on delete cascade, -- dono da nota
  estabelecimento_nome text not null check (char_length(estabelecimento_nome) between 1 and 200),
  valor_total numeric(14, 2),
  data_emissao date,
  status text not null default 'pendente'
    check (status in ('pendente', 'aceito', 'recusado')),
  proposto_por uuid not null references auth.users(id) on delete cascade,
  respondida_por uuid references auth.users(id) on delete set null,
  respondida_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

-- Um pedido aberto por nota: dois cliques nao criam duas pendencias.
create unique index if not exists compartilhamentos_notas_pendente_idx
  on public.compartilhamentos_notas_casal (vinculo_id, nota_id)
  where status = 'pendente';
create index if not exists compartilhamentos_notas_vinculo_status_idx
  on public.compartilhamentos_notas_casal (vinculo_id, status, criado_em desc);

drop trigger if exists compartilhamentos_notas_casal_atualizado_em
  on public.compartilhamentos_notas_casal;
create trigger compartilhamentos_notas_casal_atualizado_em
before update on public.compartilhamentos_notas_casal
for each row execute function public.definir_atualizado_em();

alter table public.compartilhamentos_notas_casal enable row level security;
alter table public.compartilhamentos_notas_casal force row level security;

drop policy if exists compartilhamentos_notas_casal_dos_membros
  on public.compartilhamentos_notas_casal;
create policy compartilhamentos_notas_casal_dos_membros
  on public.compartilhamentos_notas_casal
for all to authenticated
using (
  exists (
    select 1 from public.vinculos_casal v
    where v.id = vinculo_id
      and v.status = 'ativo'
      and (select auth.uid()) in (v.criador_id, v.parceiro_id)
  )
)
with check (
  exists (
    select 1 from public.vinculos_casal v
    where v.id = vinculo_id
      and v.status = 'ativo'
      and (select auth.uid()) in (v.criador_id, v.parceiro_id)
  )
);

revoke all on public.compartilhamentos_notas_casal from anon;
grant select, insert, update, delete
  on public.compartilhamentos_notas_casal to authenticated;

-- A central de notificacoes passa a carregar tambem o aceite de nota de consumo.
alter table public.notificacoes drop constraint if exists notificacoes_tipo_check;
alter table public.notificacoes add constraint notificacoes_tipo_check
  check (tipo in (
    'desejo_pendente', 'desejo_aceito', 'desejo_recusado',
    'divisao_pendente', 'divisao_aceita', 'divisao_recusada',
    'compartilhamento_pendente', 'compartilhamento_aceito', 'compartilhamento_recusado',
    'documento_pendente', 'documento_aceito', 'documento_recusado',
    'nota_consumo_pendente', 'nota_consumo_aceito', 'nota_consumo_recusado'
  ));

alter table public.notificacoes drop constraint if exists notificacoes_acao_check;
alter table public.notificacoes add constraint notificacoes_acao_check
  check (acao is null or acao in (
    'aprovar_desejo', 'reenviar_desejo', 'aprovar_divisao',
    'aprovar_compartilhamento', 'aprovar_documento', 'aprovar_nota_consumo'
  ));

alter table public.notificacoes drop constraint if exists notificacoes_entidade_tipo_check;
alter table public.notificacoes add constraint notificacoes_entidade_tipo_check
  check (entidade_tipo is null or entidade_tipo in (
    'desejo_casal', 'divisao_casal', 'compartilhamento_casal', 'documento_casal',
    'nota_consumo_casal'
  ));

commit;
