begin;

create table if not exists public.recorrencias (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  conta_id uuid references public.contas(id) on delete set null,
  categoria_id uuid references public.categorias(id) on delete set null,
  natureza text not null check (natureza in ('receita', 'despesa')),
  descricao text not null check (char_length(descricao) between 1 and 180),
  valor_estimado numeric(14, 2) check (valor_estimado is null or valor_estimado > 0),
  periodicidade text not null check (periodicidade in (
    'semanal', 'quinzenal', 'mensal', 'bimestral', 'trimestral', 'semestral', 'anual'
  )),
  proxima_data date,
  confianca numeric(4, 3) check (confianca is null or confianca between 0 and 1),
  detectada_por_ia boolean not null default false,
  ativa boolean not null default true,
  metadados jsonb not null default '{}'::jsonb,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create table if not exists public.dividas (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  credor text not null check (char_length(credor) between 1 and 120),
  descricao text not null check (char_length(descricao) between 1 and 180),
  tipo text not null default 'outro' check (tipo in (
    'cartao', 'emprestimo', 'financiamento', 'imposto', 'acordo', 'pessoal', 'outro'
  )),
  valor_original numeric(14, 2) not null check (valor_original > 0),
  saldo_devedor numeric(14, 2) not null check (saldo_devedor >= 0),
  taxa_juros_mensal numeric(8, 5) check (taxa_juros_mensal is null or taxa_juros_mensal >= 0),
  data_contratacao date,
  data_final_prevista date,
  prioridade text not null default 'media' check (prioridade in ('baixa', 'media', 'alta')),
  status text not null default 'ativa' check (status in ('ativa', 'negociacao', 'quitada', 'cancelada')),
  origem text not null default 'manual' check (origem in ('manual', 'ia', 'documento')),
  observacoes text,
  metadados jsonb not null default '{}'::jsonb,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create table if not exists public.parcelas_divida (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  divida_id uuid not null references public.dividas(id) on delete cascade,
  movimentacao_id uuid references public.movimentacoes(id) on delete set null,
  numero integer not null check (numero > 0),
  valor_principal numeric(14, 2) not null default 0 check (valor_principal >= 0),
  valor_juros numeric(14, 2) not null default 0 check (valor_juros >= 0),
  valor_total numeric(14, 2) generated always as (valor_principal + valor_juros) stored,
  data_vencimento date not null,
  data_pagamento date,
  status text not null default 'prevista' check (status in (
    'prevista', 'paga', 'atrasada', 'renegociada', 'cancelada'
  )),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (divida_id, numero)
);

create table if not exists public.orcamentos (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  categoria_id uuid not null references public.categorias(id) on delete cascade,
  mes date not null,
  valor_limite numeric(14, 2) not null check (valor_limite > 0),
  alerta_percentual integer not null default 80 check (alerta_percentual between 1 and 100),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  check (mes = date_trunc('month', mes)::date),
  unique (usuario_id, categoria_id, mes)
);

create table if not exists public.metas (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  nome text not null check (char_length(nome) between 1 and 100),
  tipo text not null default 'reserva' check (tipo in (
    'reserva', 'compra', 'viagem', 'investimento', 'quitar_divida', 'outro'
  )),
  valor_alvo numeric(14, 2) not null check (valor_alvo > 0),
  valor_atual numeric(14, 2) not null default 0 check (valor_atual >= 0),
  data_alvo date,
  cor text not null default '#8b7cff' check (cor ~ '^#[0-9A-Fa-f]{6}$'),
  status text not null default 'ativa' check (status in ('ativa', 'concluida', 'pausada', 'cancelada')),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create index if not exists recorrencias_usuario_proxima_idx
  on public.recorrencias (usuario_id, ativa, proxima_data);
create index if not exists dividas_usuario_status_idx
  on public.dividas (usuario_id, status, prioridade);
create index if not exists parcelas_divida_vencimento_idx
  on public.parcelas_divida (divida_id, data_vencimento);
create index if not exists parcelas_usuario_status_idx
  on public.parcelas_divida (usuario_id, status, data_vencimento);
create index if not exists orcamentos_usuario_mes_idx
  on public.orcamentos (usuario_id, mes desc);
create index if not exists metas_usuario_status_idx
  on public.metas (usuario_id, status);

drop trigger if exists recorrencias_atualizado_em on public.recorrencias;
create trigger recorrencias_atualizado_em
before update on public.recorrencias
for each row execute function public.definir_atualizado_em();

drop trigger if exists dividas_atualizado_em on public.dividas;
create trigger dividas_atualizado_em
before update on public.dividas
for each row execute function public.definir_atualizado_em();

drop trigger if exists parcelas_divida_atualizado_em on public.parcelas_divida;
create trigger parcelas_divida_atualizado_em
before update on public.parcelas_divida
for each row execute function public.definir_atualizado_em();

drop trigger if exists orcamentos_atualizado_em on public.orcamentos;
create trigger orcamentos_atualizado_em
before update on public.orcamentos
for each row execute function public.definir_atualizado_em();

drop trigger if exists metas_atualizado_em on public.metas;
create trigger metas_atualizado_em
before update on public.metas
for each row execute function public.definir_atualizado_em();

alter table public.recorrencias enable row level security;
alter table public.dividas enable row level security;
alter table public.parcelas_divida enable row level security;
alter table public.orcamentos enable row level security;
alter table public.metas enable row level security;

alter table public.recorrencias force row level security;
alter table public.dividas force row level security;
alter table public.parcelas_divida force row level security;
alter table public.orcamentos force row level security;
alter table public.metas force row level security;

drop policy if exists recorrencias_do_proprio_usuario on public.recorrencias;
create policy recorrencias_do_proprio_usuario on public.recorrencias
for all to authenticated
using ((select auth.uid()) = usuario_id)
with check ((select auth.uid()) = usuario_id);

drop policy if exists dividas_do_proprio_usuario on public.dividas;
create policy dividas_do_proprio_usuario on public.dividas
for all to authenticated
using ((select auth.uid()) = usuario_id)
with check ((select auth.uid()) = usuario_id);

drop policy if exists parcelas_do_proprio_usuario on public.parcelas_divida;
create policy parcelas_do_proprio_usuario on public.parcelas_divida
for all to authenticated
using ((select auth.uid()) = usuario_id)
with check (
  (select auth.uid()) = usuario_id
  and exists (
    select 1 from public.dividas d
    where d.id = divida_id and d.usuario_id = (select auth.uid())
  )
);

drop policy if exists orcamentos_do_proprio_usuario on public.orcamentos;
create policy orcamentos_do_proprio_usuario on public.orcamentos
for all to authenticated
using ((select auth.uid()) = usuario_id)
with check (
  (select auth.uid()) = usuario_id
  and exists (
    select 1 from public.categorias c
    where c.id = categoria_id and c.usuario_id = (select auth.uid())
  )
);

drop policy if exists metas_do_proprio_usuario on public.metas;
create policy metas_do_proprio_usuario on public.metas
for all to authenticated
using ((select auth.uid()) = usuario_id)
with check ((select auth.uid()) = usuario_id);

revoke all on public.recorrencias from anon;
revoke all on public.dividas from anon;
revoke all on public.parcelas_divida from anon;
revoke all on public.orcamentos from anon;
revoke all on public.metas from anon;

grant select, insert, update, delete on public.recorrencias to authenticated;
grant select, insert, update, delete on public.dividas to authenticated;
grant select, insert, update, delete on public.parcelas_divida to authenticated;
grant select, insert, update, delete on public.orcamentos to authenticated;
grant select, insert, update, delete on public.metas to authenticated;

commit;

