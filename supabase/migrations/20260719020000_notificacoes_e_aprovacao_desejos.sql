begin;

-- Central de notificacoes do FiNancas. Nasce servindo a aprovacao dos desejos
-- do casal, mas o contrato e generico: destinatario, tipo, texto, a entidade
-- que originou o aviso e, quando existir, uma acao que a pessoa pode tomar
-- direto da notificacao.
create table if not exists public.notificacoes (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  tipo text not null check (tipo in (
    'desejo_pendente', 'desejo_aceito', 'desejo_recusado'
  )),
  titulo text not null check (char_length(titulo) between 1 and 120),
  mensagem text not null check (char_length(mensagem) between 1 and 500),
  entidade_tipo text check (entidade_tipo is null or entidade_tipo in ('desejo_casal')),
  entidade_id uuid,
  -- Botao que a notificacao oferece. Null quando ela e so um aviso.
  acao text check (acao is null or acao in ('aprovar_desejo', 'reenviar_desejo')),
  status text not null default 'nova' check (status in ('nova', 'lida', 'arquivada')),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  check ((entidade_tipo is null) = (entidade_id is null))
);

create index if not exists notificacoes_usuario_status_idx
  on public.notificacoes (usuario_id, status, criado_em desc);
create index if not exists notificacoes_entidade_idx
  on public.notificacoes (entidade_tipo, entidade_id);

drop trigger if exists notificacoes_atualizado_em on public.notificacoes;
create trigger notificacoes_atualizado_em
before update on public.notificacoes
for each row execute function public.definir_atualizado_em();

alter table public.notificacoes enable row level security;
alter table public.notificacoes force row level security;

-- Cada pessoa le e marca como lida somente as proprias notificacoes.
-- A criacao e da API (service role): ninguem escreve notificacao para outro.
drop policy if exists notificacoes_do_proprio_usuario on public.notificacoes;
create policy notificacoes_do_proprio_usuario on public.notificacoes
for select to authenticated
using ((select auth.uid()) = usuario_id);

drop policy if exists notificacoes_marcadas_pelo_usuario on public.notificacoes;
create policy notificacoes_marcadas_pelo_usuario on public.notificacoes
for update to authenticated
using ((select auth.uid()) = usuario_id)
with check ((select auth.uid()) = usuario_id);

revoke all on public.notificacoes from anon;
grant select, update on public.notificacoes to authenticated;

-- Aprovacao do parceiro para entrar na lista de desejos ----------------------
--
-- Fica em coluna propria, separada de `status`: `status` cuida do ciclo de vida
-- do item (rascunho sem preco, ativo, comprado, arquivado) e misturar as duas
-- coisas quebraria a regra de que e o preco que ativa o desejo.
alter table public.desejos_casal
  add column if not exists aprovacao text not null default 'pendente'
    check (aprovacao in ('pendente', 'aceito', 'recusado')),
  add column if not exists aprovado_por uuid references auth.users(id) on delete set null,
  add column if not exists aprovado_em timestamptz,
  add column if not exists vezes_recusado integer not null default 0
    check (vezes_recusado >= 0);

-- Os itens que ja estavam na lista compartilhada continuam valendo: eles
-- entraram quando ainda nao existia aprovacao.
update public.desejos_casal set aprovacao = 'aceito' where aprovacao = 'pendente';

create index if not exists desejos_casal_aprovacao_idx
  on public.desejos_casal (vinculo_id, aprovacao, criado_em desc);

commit;
