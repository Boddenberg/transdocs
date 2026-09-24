-- O jeito de olhar o catalogo, por pessoa.
--
-- A lista e do casal; o tamanho dos cartoes nao e. Cada aparelho tem uma tela
-- diferente e cada pessoa enxerga de um jeito, entao isto mora numa tabela
-- por `usuario_id` e nao no escopo do vinculo.
--
-- Nao entra em `preferencias_usuario`: aquela tabela e do panorama do FiNancas,
-- e misturar dois apps numa linha e o tipo de atalho que faz um deles nao poder
-- mudar sem mexer no outro.

begin;

create table public.preferencias_compras (
  usuario_id uuid primary key references auth.users(id) on delete cascade,
  -- 0 e "deixa a tela decidir pela largura", que e como nasce.
  colunas smallint not null default 0 check (colunas between 0 and 5),
  ordem text not null default 'corredor'
    check (ordem in ('corredor', 'mais-comprados', 'alfabetica')),
  esconder_escolhidos boolean not null default false,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

drop trigger if exists preferencias_compras_atualizado_em on public.preferencias_compras;
create trigger preferencias_compras_atualizado_em
before update on public.preferencias_compras
for each row execute function public.definir_atualizado_em();

alter table public.preferencias_compras enable row level security;
alter table public.preferencias_compras force row level security;

create policy preferencias_compras_do_proprio_usuario
on public.preferencias_compras
for all to authenticated
using ((select auth.uid()) = usuario_id)
with check ((select auth.uid()) = usuario_id);

revoke all on public.preferencias_compras from anon;
grant select, insert, update, delete on public.preferencias_compras to authenticated;

commit;
