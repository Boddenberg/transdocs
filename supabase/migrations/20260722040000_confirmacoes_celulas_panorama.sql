begin;

-- Confirmacao de valor real por celula (conciliacao leve do mes) ----------------
--
-- O panorama projeta valor fixo para o futuro (salario, mensalidade de aulas,
-- assinatura). A realidade varia — hora extra, desconto, reajuste — e sem um
-- "confirmei" a previsao vira uma verdade silenciosa. Esta tabela guarda, por
-- linha (`fonte_chave`) e competencia, que o usuario confirmou o valor real
-- daquele mes. Quando o valor real difere, a magnitude vai para
-- `ajustes_celulas_panorama` (que ja congela a celula); aqui fica so a marca de
-- que a linha foi conferida, com um retrato do valor confirmado para o futuro
-- "Fechar mes" calcular a diferenca.
create table if not exists public.confirmacoes_celulas_panorama (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  grupo text not null check (grupo in (
    'entradas', 'contas_fixas', 'faturas_cartoes',
    'dividas_financiamentos', 'despesas_variaveis', 'investimentos'
  )),
  fonte_chave text not null check (char_length(fonte_chave) between 3 and 300),
  competencia date not null check (competencia = date_trunc('month', competencia)::date),
  valor_confirmado numeric(14, 2) not null,
  data_referencia date not null,
  confirmado_em timestamptz not null default now(),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  -- Uma confirmacao por linha por mes: confirmar de novo apenas atualiza.
  unique (usuario_id, fonte_chave, competencia)
);

create index if not exists confirmacoes_celulas_panorama_usuario_competencia_idx
  on public.confirmacoes_celulas_panorama (usuario_id, competencia);

drop trigger if exists confirmacoes_celulas_panorama_atualizado_em
  on public.confirmacoes_celulas_panorama;
create trigger confirmacoes_celulas_panorama_atualizado_em
before update on public.confirmacoes_celulas_panorama
for each row execute function public.definir_atualizado_em();

alter table public.confirmacoes_celulas_panorama enable row level security;
alter table public.confirmacoes_celulas_panorama force row level security;

drop policy if exists confirmacoes_celulas_panorama_do_proprio_usuario
  on public.confirmacoes_celulas_panorama;
create policy confirmacoes_celulas_panorama_do_proprio_usuario
on public.confirmacoes_celulas_panorama
for all
using (auth.uid() = usuario_id)
with check (auth.uid() = usuario_id);

revoke all on public.confirmacoes_celulas_panorama from anon;
grant select, insert, update, delete on public.confirmacoes_celulas_panorama to authenticated;

commit;
