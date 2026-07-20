begin;

-- Correcao manual do saldo restante de uma quinzena do Panorama. Substitui o
-- valor calculado (entradas - compromissos) por um valor informado pelo
-- usuario. Nao propaga para as proximas colunas: o acumulado segue com o saldo
-- original; apenas a propria coluna reflete a correcao.
create table if not exists public.ajustes_saldo_quinzena_panorama (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  competencia date not null check (competencia = date_trunc('month', competencia)::date),
  quinzena smallint not null check (quinzena in (1, 2)),
  valor numeric(14, 2) not null,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (usuario_id, competencia, quinzena)
);

create index if not exists ajustes_saldo_quinzena_panorama_usuario_competencia_idx
  on public.ajustes_saldo_quinzena_panorama (usuario_id, competencia);

drop trigger if exists ajustes_saldo_quinzena_panorama_atualizado_em
  on public.ajustes_saldo_quinzena_panorama;
create trigger ajustes_saldo_quinzena_panorama_atualizado_em
before update on public.ajustes_saldo_quinzena_panorama
for each row execute function public.definir_atualizado_em();

alter table public.ajustes_saldo_quinzena_panorama enable row level security;
alter table public.ajustes_saldo_quinzena_panorama force row level security;

drop policy if exists ajustes_saldo_quinzena_panorama_do_proprio_usuario
  on public.ajustes_saldo_quinzena_panorama;
create policy ajustes_saldo_quinzena_panorama_do_proprio_usuario
on public.ajustes_saldo_quinzena_panorama
for all
using (auth.uid() = usuario_id)
with check (auth.uid() = usuario_id);

revoke all on public.ajustes_saldo_quinzena_panorama from anon;
grant select, insert, update, delete on public.ajustes_saldo_quinzena_panorama to authenticated;

commit;
