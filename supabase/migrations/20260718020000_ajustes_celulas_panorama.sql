begin;

create table if not exists public.ajustes_celulas_panorama (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  grupo text not null check (grupo in (
    'entradas', 'contas_fixas', 'faturas_cartoes',
    'dividas_financiamentos', 'despesas_variaveis', 'investimentos'
  )),
  fonte_chave text not null check (char_length(fonte_chave) between 3 and 300),
  fonte_nome text not null check (char_length(fonte_nome) between 1 and 180),
  competencia date not null check (competencia = date_trunc('month', competencia)::date),
  valor numeric(14, 2) not null check (valor >= 0),
  conta_id uuid references public.contas(id) on delete set null,
  divida_id uuid references public.dividas(id) on delete set null,
  categoria_id uuid references public.categorias(id) on delete set null,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (usuario_id, grupo, fonte_chave, competencia)
);

create index if not exists ajustes_celulas_panorama_usuario_competencia_idx
  on public.ajustes_celulas_panorama (usuario_id, competencia, grupo);

drop trigger if exists ajustes_celulas_panorama_atualizado_em
  on public.ajustes_celulas_panorama;
create trigger ajustes_celulas_panorama_atualizado_em
before update on public.ajustes_celulas_panorama
for each row execute function public.definir_atualizado_em();

alter table public.ajustes_celulas_panorama enable row level security;
alter table public.ajustes_celulas_panorama force row level security;

drop policy if exists ajustes_celulas_panorama_do_proprio_usuario
  on public.ajustes_celulas_panorama;
create policy ajustes_celulas_panorama_do_proprio_usuario
on public.ajustes_celulas_panorama
for all
using (auth.uid() = usuario_id)
with check (auth.uid() = usuario_id);

commit;
