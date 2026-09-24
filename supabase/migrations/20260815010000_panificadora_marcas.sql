begin;

-- A Panificadora guarda pouco, e de proposito.
--
-- O catalogo das 17 receitas da Mondial NPF-53 e conteudo oficial e imutavel:
-- ele viaja dentro do binario do app e do bundle do site, nao no banco. Trazer
-- receita de fabricante para ca so criaria uma copia para sair de sincronia.
--
-- O que muda e o que e nosso: se a receita virou favorita, se ja foi feita
-- alguma vez, quantas, que nota levou e o bilhete que ficou na margem. Uma
-- linha por pessoa e por receita, com o id da receita vindo do catalogo — e
-- por isso `text`, e nao uma FK: nao ha tabela de receitas para apontar.
create table if not exists public.panificadora_marcas (
  usuario_id uuid not null references auth.users(id) on delete cascade,
  receita_id text not null check (char_length(receita_id) between 1 and 60),
  favorita boolean not null default false,
  -- Nulo significa "nunca fiz". A data e a da ultima vez; `vezes` conta todas.
  preparada_em timestamptz,
  vezes integer not null default 0 check (vezes >= 0),
  -- A avaliacao e opcional mesmo depois de preparada: quem fez pode nao querer
  -- dar nota. Nulo e ausencia de opiniao, nao nota zero.
  avaliacao smallint check (avaliacao between 1 and 5),
  anotacao text not null default '' check (char_length(anotacao) <= 2000),
  criada_em timestamptz not null default now(),
  atualizada_em timestamptz not null default now(),
  primary key (usuario_id, receita_id),
  -- Nota so existe para receita ja preparada, e contagem e data andam juntas.
  check (avaliacao is null or preparada_em is not null),
  check ((preparada_em is null) = (vezes = 0))
);

comment on table public.panificadora_marcas is
  'O que e nosso sobre as receitas oficiais da NPF-53: favorito, ja fiz, nota e anotacao.';
comment on column public.panificadora_marcas.receita_id is
  'Id do catalogo embutido no app (src/apps/panificadora/catalogo.ts). Nao ha tabela de receitas.';

create index if not exists panificadora_marcas_favoritas_idx
  on public.panificadora_marcas (usuario_id)
  where favorita;

create index if not exists panificadora_marcas_historico_idx
  on public.panificadora_marcas (usuario_id, preparada_em desc)
  where preparada_em is not null;

alter table public.panificadora_marcas enable row level security;

create policy panificadora_marcas_dono on public.panificadora_marcas
  for all to authenticated
  using ((select auth.uid()) = usuario_id)
  with check ((select auth.uid()) = usuario_id);

revoke all on public.panificadora_marcas from anon;

commit;
