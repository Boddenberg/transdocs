begin;

-- Divisao POR COMPRA e aprovacao pelo parceiro -------------------------------
--
-- Ate aqui, marcar uma compra como do casal era instantaneo e a divisao vinha
-- de um unico acordo do casal (`divisoes_casal`), valendo por competencia para
-- tudo. Agora cada compra carrega a propria divisao e so entra no espaco do
-- casal depois que o parceiro aceita. A regra padrao passa a ser meio a meio; a
-- divisao acordada (ex.: 40/60) vira uma regra opcional escolhida por compra.

-- `percentual_casal_criador` e a fatia do CRIADOR do vinculo nesta compra
-- especifica (o parceiro fica com o complemento). NULL preserva o passado: as
-- compras marcadas antes desta mudanca continuam caindo no acordo por
-- competencia, como sempre funcionaram.
alter table public.movimentacoes
  add column if not exists percentual_casal_criador numeric(5, 2)
    check (percentual_casal_criador is null
           or (percentual_casal_criador >= 0 and percentual_casal_criador <= 100));

-- Solicitacoes de compartilhamento: uma pessoa pede para levar uma compra ao
-- espaco do casal e o parceiro aceita ou recusa. Enquanto pendente a compra NAO
-- entra na divisao (`movimentacoes.compartilhada_casal` segue false); o aceite e
-- que marca a compra e grava a divisao escolhida.
--
-- `grupo_chave` identifica a compra: o `grupo_parcelas_id` quando ha parcelas
-- (a compra inteira vai junto) ou o proprio id da movimentacao avulsa. As
-- colunas `descricao` e `valor_referencia` sao um retrato para a notificacao e o
-- hub mostrarem a compra sem depender do RLS da conta de quem pagou.
create table if not exists public.compartilhamentos_casal (
  id uuid primary key default gen_random_uuid(),
  vinculo_id uuid not null references public.vinculos_casal(id) on delete cascade,
  usuario_id uuid not null references auth.users(id) on delete cascade,
  grupo_chave text not null check (char_length(grupo_chave) between 1 and 100),
  descricao text not null check (char_length(descricao) between 1 and 240),
  valor_referencia numeric(14, 2),
  percentual_criador numeric(5, 2) not null
    check (percentual_criador >= 0 and percentual_criador <= 100),
  status text not null default 'pendente'
    check (status in ('pendente', 'aceito', 'recusado')),
  proposto_por uuid not null references auth.users(id) on delete cascade,
  respondida_por uuid references auth.users(id) on delete set null,
  respondida_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

-- Uma solicitacao aberta por compra: sem isso, dois cliques no coracao criariam
-- duas pendencias para a mesma compra.
create unique index if not exists compartilhamentos_casal_pendente_idx
  on public.compartilhamentos_casal (vinculo_id, grupo_chave)
  where status = 'pendente';

create index if not exists compartilhamentos_casal_vinculo_status_idx
  on public.compartilhamentos_casal (vinculo_id, status, criado_em desc);

drop trigger if exists compartilhamentos_casal_atualizado_em on public.compartilhamentos_casal;
create trigger compartilhamentos_casal_atualizado_em
before update on public.compartilhamentos_casal
for each row execute function public.definir_atualizado_em();

alter table public.compartilhamentos_casal enable row level security;
alter table public.compartilhamentos_casal force row level security;

drop policy if exists compartilhamentos_casal_dos_membros on public.compartilhamentos_casal;
create policy compartilhamentos_casal_dos_membros on public.compartilhamentos_casal
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

revoke all on public.compartilhamentos_casal from anon;
grant select, insert, update, delete on public.compartilhamentos_casal to authenticated;

-- A central de notificacoes passa a carregar tambem o aceite de cada compra.
alter table public.notificacoes drop constraint if exists notificacoes_tipo_check;
alter table public.notificacoes add constraint notificacoes_tipo_check
  check (tipo in (
    'desejo_pendente', 'desejo_aceito', 'desejo_recusado',
    'divisao_pendente', 'divisao_aceita', 'divisao_recusada',
    'compartilhamento_pendente', 'compartilhamento_aceito', 'compartilhamento_recusado'
  ));

alter table public.notificacoes drop constraint if exists notificacoes_acao_check;
alter table public.notificacoes add constraint notificacoes_acao_check
  check (acao is null or acao in (
    'aprovar_desejo', 'reenviar_desejo', 'aprovar_divisao', 'aprovar_compartilhamento'
  ));

alter table public.notificacoes drop constraint if exists notificacoes_entidade_tipo_check;
alter table public.notificacoes add constraint notificacoes_entidade_tipo_check
  check (entidade_tipo is null or entidade_tipo in (
    'desejo_casal', 'divisao_casal', 'compartilhamento_casal'
  ));

commit;
