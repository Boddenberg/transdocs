begin;

-- Planos financeiros gerados pela IA especialista em planejamento. Guardam o
-- resumo executivo, as premissas usadas e a linha do tempo estruturada (quando
-- antecipar parcelas, quitar dividas, formar reserva, realizar cada objetivo).
create table if not exists public.planos_financeiros_ia (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  titulo text not null check (char_length(titulo) between 1 and 160),
  horizonte_meses integer not null default 36 check (horizonte_meses between 1 and 480),
  resumo text not null check (char_length(resumo) between 1 and 6000),
  premissas jsonb not null default '{}'::jsonb,
  conteudo jsonb not null default '{}'::jsonb,
  modelo_ia text,
  tokens_entrada integer check (tokens_entrada is null or tokens_entrada >= 0),
  tokens_saida integer check (tokens_saida is null or tokens_saida >= 0),
  status text not null default 'gerado' check (status in ('gerado', 'arquivado')),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create index if not exists planos_financeiros_ia_usuario_idx
  on public.planos_financeiros_ia (usuario_id, status, criado_em desc);

drop trigger if exists planos_financeiros_ia_atualizado_em on public.planos_financeiros_ia;
create trigger planos_financeiros_ia_atualizado_em
before update on public.planos_financeiros_ia
for each row execute function public.definir_atualizado_em();

alter table public.planos_financeiros_ia enable row level security;
alter table public.planos_financeiros_ia force row level security;

drop policy if exists planos_financeiros_ia_do_proprio_usuario on public.planos_financeiros_ia;
create policy planos_financeiros_ia_do_proprio_usuario on public.planos_financeiros_ia
for all to authenticated
using ((select auth.uid()) = usuario_id)
with check ((select auth.uid()) = usuario_id);

revoke all on public.planos_financeiros_ia from anon;
grant select, insert, update, delete on public.planos_financeiros_ia to authenticated;

commit;
