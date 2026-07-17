begin;

-- Objetivos financeiros: planos e sonhos do usuario (quitar dividas, reserva,
-- viagem, carro, etc.). Um objetivo pode se ligar a uma divida para planejar a
-- quitacao usando a antecipacao de parcelas.
create table if not exists public.objetivos (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  titulo text not null check (char_length(titulo) between 1 and 120),
  descricao text,
  tipo text not null default 'sonho' check (tipo in (
    'quitar_divida', 'reserva_emergencia', 'viagem', 'veiculo', 'imovel',
    'compra', 'investimento', 'educacao', 'sonho', 'outro'
  )),
  horizonte text not null default 'medio' check (horizonte in ('curto', 'medio', 'longo')),
  prioridade text not null default 'media' check (prioridade in ('baixa', 'media', 'alta')),
  valor_estimado numeric(14, 2) check (valor_estimado is null or valor_estimado >= 0),
  valor_acumulado numeric(14, 2) not null default 0 check (valor_acumulado >= 0),
  data_desejada date,
  divida_id uuid references public.dividas(id) on delete set null,
  status text not null default 'sonhando' check (status in (
    'sonhando', 'planejado', 'em_andamento', 'concluido', 'pausado', 'cancelado'
  )),
  cor text not null default '#8b7cff' check (cor ~ '^#[0-9A-Fa-f]{6}$'),
  icone text not null default 'target',
  metadados jsonb not null default '{}'::jsonb,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create index if not exists objetivos_usuario_status_idx
  on public.objetivos (usuario_id, status, prioridade);
create index if not exists objetivos_usuario_horizonte_idx
  on public.objetivos (usuario_id, horizonte, data_desejada);

drop trigger if exists objetivos_atualizado_em on public.objetivos;
create trigger objetivos_atualizado_em
before update on public.objetivos
for each row execute function public.definir_atualizado_em();

alter table public.objetivos enable row level security;
alter table public.objetivos force row level security;

drop policy if exists objetivos_do_proprio_usuario on public.objetivos;
create policy objetivos_do_proprio_usuario on public.objetivos
for all to authenticated
using ((select auth.uid()) = usuario_id)
with check (
  (select auth.uid()) = usuario_id
  and (divida_id is null or exists (
    select 1 from public.dividas d
    where d.id = divida_id and d.usuario_id = (select auth.uid())
  ))
);

revoke all on public.objetivos from anon;
grant select, insert, update, delete on public.objetivos to authenticated;

commit;
