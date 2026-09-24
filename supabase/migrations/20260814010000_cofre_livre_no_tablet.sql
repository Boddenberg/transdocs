begin;

-- Copia deliberadamente em claro dos acessos compartilhados no tablet fixo.
-- O Cofre principal permanece E2EE. Esta tabela e uma projecao separada,
-- alimentada somente depois que uma sessao pessoal abriu os blobs no navegador.
-- A referencia ao item impede manter uma copia depois de excluir o original.
create table if not exists public.cofre_tablet_acessos (
  item_id uuid primary key
    references public.cofre_itens(id) on delete cascade,
  titulo text not null check (char_length(titulo) between 1 and 200),
  usuario text not null default '' check (char_length(usuario) <= 500),
  senha text not null default '' check (char_length(senha) <= 1000),
  url text not null default '' check (char_length(url) <= 2048),
  notas text not null default '' check (char_length(notas) <= 10000),
  sincronizado_em timestamptz not null default now()
);

comment on table public.cofre_tablet_acessos is
  'Projecao em claro, autorizada apenas para acessos do casal no painel fixo.';
comment on column public.cofre_tablet_acessos.senha is
  'Segredo em claro por decisao explicita de deixar o tablet da casa sem destravamento.';

alter table public.cofre_tablet_acessos enable row level security;
alter table public.cofre_tablet_acessos force row level security;

-- Nao ha politica direta: o navegador e o APK passam pela API. Somente a
-- service_role do backend toca na projecao, inclusive durante a sincronizacao.
revoke all on public.cofre_tablet_acessos from anon;
revoke all on public.cofre_tablet_acessos from authenticated;
grant select, insert, update, delete on public.cofre_tablet_acessos to service_role;

commit;
