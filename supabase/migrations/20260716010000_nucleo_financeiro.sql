begin;

create extension if not exists pgcrypto;

create or replace function public.definir_atualizado_em()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.atualizado_em = now();
  return new;
end;
$$;

create table if not exists public.perfis (
  usuario_id uuid primary key references auth.users(id) on delete cascade,
  nome text,
  moeda text not null default 'BRL' check (moeda ~ '^[A-Z]{3}$'),
  fuso_horario text not null default 'America/Sao_Paulo',
  dia_inicio_mes integer not null default 1 check (dia_inicio_mes between 1 and 28),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create table if not exists public.contas (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  nome text not null check (char_length(nome) between 1 and 80),
  tipo text not null check (tipo in (
    'conta_corrente', 'poupanca', 'dinheiro', 'cartao_credito',
    'vale_alimentacao', 'vale_refeicao', 'investimento', 'outro'
  )),
  instituicao text,
  cor text not null default '#8b7cff' check (cor ~ '^#[0-9A-Fa-f]{6}$'),
  saldo_inicial numeric(14, 2) not null default 0,
  data_saldo_inicial date not null default current_date,
  incluir_no_patrimonio boolean not null default true,
  ativa boolean not null default true,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (usuario_id, nome)
);

create table if not exists public.categorias (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  nome text not null check (char_length(nome) between 1 and 60),
  natureza text not null check (natureza in ('receita', 'despesa', 'ambos')),
  icone text not null default 'circle',
  cor text not null default '#8b7cff' check (cor ~ '^#[0-9A-Fa-f]{6}$'),
  categoria_pai_id uuid references public.categorias(id) on delete set null,
  padrao boolean not null default false,
  ativa boolean not null default true,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (usuario_id, nome)
);

create table if not exists public.cartoes_credito (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  conta_id uuid not null unique references public.contas(id) on delete cascade,
  limite numeric(14, 2) check (limite is null or limite >= 0),
  dia_fechamento integer not null check (dia_fechamento between 1 and 28),
  dia_vencimento integer not null check (dia_vencimento between 1 and 28),
  final_cartao text check (final_cartao is null or final_cartao ~ '^[0-9]{4}$'),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create table if not exists public.movimentacoes (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  conta_id uuid references public.contas(id) on delete set null,
  conta_destino_id uuid references public.contas(id) on delete set null,
  categoria_id uuid references public.categorias(id) on delete set null,
  natureza text not null check (natureza in ('receita', 'despesa', 'transferencia')),
  descricao text not null check (char_length(descricao) between 1 and 180),
  valor numeric(14, 2) not null check (valor > 0),
  data_movimentacao date not null,
  mes_competencia date not null,
  status text not null default 'confirmada' check (status in (
    'prevista', 'confirmada', 'atrasada', 'cancelada'
  )),
  forma_pagamento text check (forma_pagamento is null or forma_pagamento in (
    'pix', 'debito', 'credito', 'dinheiro', 'boleto', 'transferencia',
    'vale_alimentacao', 'vale_refeicao', 'outro'
  )),
  parcela_numero integer check (parcela_numero is null or parcela_numero > 0),
  parcelas_total integer check (parcelas_total is null or parcelas_total > 0),
  grupo_parcelas_id uuid,
  origem text not null default 'manual' check (origem in (
    'manual', 'ia', 'extrato', 'fatura', 'holerite', 'recorrencia', 'importacao'
  )),
  observacoes text,
  metadados jsonb not null default '{}'::jsonb,
  confirmado_por_usuario boolean not null default true,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  check (
    (natureza = 'transferencia' and conta_id is not null and conta_destino_id is not null
      and conta_id <> conta_destino_id)
    or (natureza <> 'transferencia' and conta_destino_id is null)
  ),
  check (
    (parcela_numero is null and parcelas_total is null and grupo_parcelas_id is null)
    or (parcela_numero between 1 and parcelas_total and grupo_parcelas_id is not null)
  )
);

create index if not exists contas_usuario_ativas_idx
  on public.contas (usuario_id, ativa, nome);
create index if not exists categorias_usuario_natureza_idx
  on public.categorias (usuario_id, natureza, ativa);
create index if not exists movimentacoes_usuario_data_idx
  on public.movimentacoes (usuario_id, data_movimentacao desc);
create index if not exists movimentacoes_usuario_competencia_idx
  on public.movimentacoes (usuario_id, mes_competencia desc, natureza);
create index if not exists movimentacoes_grupo_parcelas_idx
  on public.movimentacoes (grupo_parcelas_id, parcela_numero)
  where grupo_parcelas_id is not null;

drop trigger if exists perfis_atualizado_em on public.perfis;
create trigger perfis_atualizado_em
before update on public.perfis
for each row execute function public.definir_atualizado_em();

drop trigger if exists contas_atualizado_em on public.contas;
create trigger contas_atualizado_em
before update on public.contas
for each row execute function public.definir_atualizado_em();

drop trigger if exists categorias_atualizado_em on public.categorias;
create trigger categorias_atualizado_em
before update on public.categorias
for each row execute function public.definir_atualizado_em();

drop trigger if exists cartoes_credito_atualizado_em on public.cartoes_credito;
create trigger cartoes_credito_atualizado_em
before update on public.cartoes_credito
for each row execute function public.definir_atualizado_em();

drop trigger if exists movimentacoes_atualizado_em on public.movimentacoes;
create trigger movimentacoes_atualizado_em
before update on public.movimentacoes
for each row execute function public.definir_atualizado_em();

create or replace function public.preparar_novo_usuario()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.perfis (usuario_id, nome)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'nome', split_part(new.email, '@', 1)))
  on conflict (usuario_id) do nothing;

  insert into public.categorias (usuario_id, nome, natureza, icone, cor, padrao)
  values
    (new.id, 'Salario', 'receita', 'briefcase-business', '#67e8b5', true),
    (new.id, 'Freelance', 'receita', 'sparkles', '#72b7ff', true),
    (new.id, 'Beneficios', 'receita', 'badge-dollar-sign', '#ffd166', true),
    (new.id, 'Rendimentos', 'receita', 'chart-no-axes-combined', '#8b7cff', true),
    (new.id, 'Outros ganhos', 'receita', 'plus', '#9de2d0', true),
    (new.id, 'Moradia', 'despesa', 'house', '#ff8c73', true),
    (new.id, 'Alimentacao', 'despesa', 'utensils', '#ffbd66', true),
    (new.id, 'Transporte', 'despesa', 'car-front', '#72b7ff', true),
    (new.id, 'Saude', 'despesa', 'heart-pulse', '#ff7aa2', true),
    (new.id, 'Lazer', 'despesa', 'popcorn', '#b39cff', true),
    (new.id, 'Assinaturas', 'despesa', 'repeat-2', '#7cd4ca', true),
    (new.id, 'Educacao', 'despesa', 'graduation-cap', '#8bb8ff', true),
    (new.id, 'Impostos', 'despesa', 'landmark', '#d1a26f', true),
    (new.id, 'Compras', 'despesa', 'shopping-bag', '#e99cff', true),
    (new.id, 'Outros gastos', 'despesa', 'ellipsis', '#98a2b8', true)
  on conflict (usuario_id, nome) do nothing;

  return new;
end;
$$;

drop trigger if exists ao_criar_usuario_financas on auth.users;
create trigger ao_criar_usuario_financas
after insert on auth.users
for each row execute function public.preparar_novo_usuario();

alter table public.perfis enable row level security;
alter table public.contas enable row level security;
alter table public.categorias enable row level security;
alter table public.cartoes_credito enable row level security;
alter table public.movimentacoes enable row level security;

alter table public.perfis force row level security;
alter table public.contas force row level security;
alter table public.categorias force row level security;
alter table public.cartoes_credito force row level security;
alter table public.movimentacoes force row level security;

drop policy if exists perfis_do_proprio_usuario on public.perfis;
create policy perfis_do_proprio_usuario on public.perfis
for all to authenticated
using ((select auth.uid()) = usuario_id)
with check ((select auth.uid()) = usuario_id);

drop policy if exists contas_do_proprio_usuario on public.contas;
create policy contas_do_proprio_usuario on public.contas
for all to authenticated
using ((select auth.uid()) = usuario_id)
with check ((select auth.uid()) = usuario_id);

drop policy if exists categorias_do_proprio_usuario on public.categorias;
create policy categorias_do_proprio_usuario on public.categorias
for all to authenticated
using ((select auth.uid()) = usuario_id)
with check ((select auth.uid()) = usuario_id);

drop policy if exists cartoes_do_proprio_usuario on public.cartoes_credito;
create policy cartoes_do_proprio_usuario on public.cartoes_credito
for all to authenticated
using ((select auth.uid()) = usuario_id)
with check (
  (select auth.uid()) = usuario_id
  and exists (
    select 1 from public.contas c
    where c.id = conta_id and c.usuario_id = (select auth.uid())
  )
);

drop policy if exists movimentacoes_do_proprio_usuario on public.movimentacoes;
create policy movimentacoes_do_proprio_usuario on public.movimentacoes
for all to authenticated
using ((select auth.uid()) = usuario_id)
with check (
  (select auth.uid()) = usuario_id
  and (conta_id is null or exists (
    select 1 from public.contas c
    where c.id = conta_id and c.usuario_id = (select auth.uid())
  ))
  and (conta_destino_id is null or exists (
    select 1 from public.contas c
    where c.id = conta_destino_id and c.usuario_id = (select auth.uid())
  ))
  and (categoria_id is null or exists (
    select 1 from public.categorias c
    where c.id = categoria_id and c.usuario_id = (select auth.uid())
  ))
);

revoke all on public.perfis from anon;
revoke all on public.contas from anon;
revoke all on public.categorias from anon;
revoke all on public.cartoes_credito from anon;
revoke all on public.movimentacoes from anon;

grant select, insert, update, delete on public.perfis to authenticated;
grant select, insert, update, delete on public.contas to authenticated;
grant select, insert, update, delete on public.categorias to authenticated;
grant select, insert, update, delete on public.cartoes_credito to authenticated;
grant select, insert, update, delete on public.movimentacoes to authenticated;

commit;

