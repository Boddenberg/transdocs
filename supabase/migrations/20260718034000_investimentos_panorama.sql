begin;

create table if not exists public.investimentos (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  nome text not null check (char_length(nome) between 1 and 100),
  instituicao text check (instituicao is null or char_length(instituicao) between 1 and 100),
  valor_atual numeric(16, 2) not null default 0 check (valor_atual >= 0),
  data_posicao date not null default current_date,
  rendimento_mensal_percentual numeric(12, 8) not null default 0
    check (rendimento_mensal_percentual >= 0 and rendimento_mensal_percentual <= 1000),
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (id, usuario_id)
);

create table if not exists public.movimentacoes_investimentos (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  investimento_id uuid not null,
  tipo text not null check (tipo in ('aporte', 'resgate')),
  valor numeric(16, 2) not null check (valor > 0),
  data_movimentacao date not null,
  origem text not null default 'manual' check (origem in ('manual', 'saldo_panorama')),
  criado_em timestamptz not null default now(),
  constraint movimentacoes_investimentos_investimento_usuario_fk
    foreign key (investimento_id, usuario_id)
    references public.investimentos(id, usuario_id) on delete cascade
);

create index if not exists investimentos_usuario_ativo_idx
  on public.investimentos (usuario_id, ativo, data_posicao);
create index if not exists movimentacoes_investimentos_usuario_data_idx
  on public.movimentacoes_investimentos (usuario_id, data_movimentacao, investimento_id);

drop trigger if exists investimentos_atualizado_em on public.investimentos;
create trigger investimentos_atualizado_em
before update on public.investimentos
for each row execute function public.definir_atualizado_em();

alter table public.investimentos enable row level security;
alter table public.investimentos force row level security;
alter table public.movimentacoes_investimentos enable row level security;
alter table public.movimentacoes_investimentos force row level security;

drop policy if exists investimentos_do_proprio_usuario on public.investimentos;
create policy investimentos_do_proprio_usuario
on public.investimentos
for all
using (auth.uid() = usuario_id)
with check (auth.uid() = usuario_id);

drop policy if exists movimentacoes_investimentos_do_proprio_usuario
  on public.movimentacoes_investimentos;
create policy movimentacoes_investimentos_do_proprio_usuario
on public.movimentacoes_investimentos
for all
using (auth.uid() = usuario_id)
with check (auth.uid() = usuario_id);

commit;
