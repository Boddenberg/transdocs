begin;

-- Divisao acordada do casal. A porcentagem e do CASAL, nao da compra: vale uma
-- por vez e so muda com o aceite da outra pessoa. Cada acordo guarda a partir
-- de qual competencia ele passa a valer, entao trocar a divisao nao reescreve o
-- passado - as compras e as parcelas dos meses anteriores seguem com o acordo
-- que estava valendo na epoca.
--
-- `percentual_criador` e a fatia de quem criou o vinculo; o parceiro fica com
-- o complemento (100 - percentual_criador). Guardar um so numero evita que os
-- dois lados fiquem inconsistentes.
create table if not exists public.divisoes_casal (
  id uuid primary key default gen_random_uuid(),
  vinculo_id uuid not null references public.vinculos_casal(id) on delete cascade,
  percentual_criador numeric(5, 2) not null
    check (percentual_criador >= 0 and percentual_criador <= 100),
  -- Preenchida no aceite: primeiro dia do mes em que o acordo passa a valer.
  vigencia_inicio date,
  status text not null default 'pendente'
    check (status in ('pendente', 'aceita', 'recusada')),
  proposta_por uuid not null references auth.users(id) on delete cascade,
  respondida_por uuid references auth.users(id) on delete set null,
  respondida_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  check (status <> 'aceita' or vigencia_inicio is not null),
  check (vigencia_inicio is null or extract(day from vigencia_inicio) = 1)
);

-- Uma proposta aberta por vez: sem isso, duas propostas simultaneas deixariam
-- o casal sem saber qual porcentagem esta em jogo.
create unique index if not exists divisoes_casal_pendente_idx
  on public.divisoes_casal (vinculo_id)
  where status = 'pendente';

create index if not exists divisoes_casal_vigencia_idx
  on public.divisoes_casal (vinculo_id, vigencia_inicio desc)
  where status = 'aceita';

drop trigger if exists divisoes_casal_atualizado_em on public.divisoes_casal;
create trigger divisoes_casal_atualizado_em
before update on public.divisoes_casal
for each row execute function public.definir_atualizado_em();

alter table public.divisoes_casal enable row level security;
alter table public.divisoes_casal force row level security;

drop policy if exists divisoes_casal_dos_membros on public.divisoes_casal;
create policy divisoes_casal_dos_membros on public.divisoes_casal
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

revoke all on public.divisoes_casal from anon;
grant select, insert, update, delete on public.divisoes_casal to authenticated;

-- A central de notificacoes passa a carregar tambem os avisos da divisao.
alter table public.notificacoes drop constraint if exists notificacoes_tipo_check;
alter table public.notificacoes add constraint notificacoes_tipo_check
  check (tipo in (
    'desejo_pendente', 'desejo_aceito', 'desejo_recusado',
    'divisao_pendente', 'divisao_aceita', 'divisao_recusada'
  ));

alter table public.notificacoes drop constraint if exists notificacoes_acao_check;
alter table public.notificacoes add constraint notificacoes_acao_check
  check (acao is null or acao in (
    'aprovar_desejo', 'reenviar_desejo', 'aprovar_divisao'
  ));

alter table public.notificacoes drop constraint if exists notificacoes_entidade_tipo_check;
alter table public.notificacoes add constraint notificacoes_entidade_tipo_check
  check (entidade_tipo is null or entidade_tipo in ('desejo_casal', 'divisao_casal'));

commit;
