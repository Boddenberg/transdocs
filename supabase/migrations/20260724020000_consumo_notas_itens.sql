-- Modulo de Consumo (F1): transforma nota fiscal / cupom / Nota Fiscal Paulista
-- num historico ESTRUTURADO de consumo, item a item — nao so guarda o arquivo.
--
-- Tres tabelas: o estabelecimento (canonizado por CNPJ quando ha), a nota (uma
-- por documento, deduplicada pela chave de acesso de 44 digitos) e o item da
-- nota (produto, quantidade, valor unitario, GTIN/EAN e NCM quando a fonte traz).
-- A canonizacao de produto ("mesmo item escrito diferente") e a analitica de
-- reposicao vem em fases seguintes; aqui ja gravamos a descricao normalizada e o
-- GTIN para essas fases terem sobre o que trabalhar.

begin;

-- ------------------------------------------------------------ estabelecimentos
create table if not exists public.estabelecimentos_consumo (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  cnpj text check (cnpj is null or cnpj ~ '^[0-9]{14}$'),
  nome text not null check (char_length(nome) between 1 and 200),
  nome_normalizado text not null,
  cidade text,
  uf text check (uf is null or char_length(uf) = 2),
  criado_em timestamptz not null default now()
);

-- Um CNPJ e uma identidade unica por usuario; nome_normalizado desempata quando
-- a fonte nao traz CNPJ (foto de cupom sem QR legivel).
create unique index if not exists estabelecimentos_consumo_cnpj_idx
  on public.estabelecimentos_consumo (usuario_id, cnpj)
  where cnpj is not null;
create unique index if not exists estabelecimentos_consumo_nome_idx
  on public.estabelecimentos_consumo (usuario_id, nome_normalizado)
  where cnpj is null;

-- ---------------------------------------------------------------------- notas
create table if not exists public.notas_consumo (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  documento_id uuid references public.documentos_financeiros(id) on delete set null,
  estabelecimento_id uuid not null
    references public.estabelecimentos_consumo(id) on delete cascade,
  chave_acesso text check (chave_acesso is null or chave_acesso ~ '^[0-9]{44}$'),
  data_emissao date,
  valor_total numeric(14, 2) check (valor_total is null or valor_total >= 0),
  quantidade_itens integer not null default 0 check (quantidade_itens >= 0),
  fonte text not null default 'outro',
  modelo_ia text,
  confianca real check (confianca is null or (confianca >= 0 and confianca <= 1)),
  criado_em timestamptz not null default now()
);

-- Idempotencia: a mesma nota (mesma chave de acesso) nunca entra duas vezes.
create unique index if not exists notas_consumo_chave_idx
  on public.notas_consumo (usuario_id, chave_acesso)
  where chave_acesso is not null;
create index if not exists notas_consumo_usuario_data_idx
  on public.notas_consumo (usuario_id, data_emissao desc);
create index if not exists notas_consumo_estabelecimento_idx
  on public.notas_consumo (estabelecimento_id);

-- ---------------------------------------------------------------------- itens
create table if not exists public.itens_consumo (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  nota_id uuid not null references public.notas_consumo(id) on delete cascade,
  descricao_original text not null check (char_length(descricao_original) between 1 and 300),
  descricao_normalizada text not null,
  gtin text check (gtin is null or gtin ~ '^[0-9]{8,14}$'),
  ncm text check (ncm is null or ncm ~ '^[0-9]{6,8}$'),
  categoria text,
  quantidade numeric(14, 3) check (quantidade is null or quantidade >= 0),
  unidade text,
  valor_unitario numeric(14, 4) check (valor_unitario is null or valor_unitario >= 0),
  valor_total numeric(14, 2) check (valor_total is null or valor_total >= 0),
  ordem integer not null default 0 check (ordem >= 0),
  criado_em timestamptz not null default now()
);

create index if not exists itens_consumo_nota_idx
  on public.itens_consumo (nota_id, ordem);
create index if not exists itens_consumo_usuario_idx
  on public.itens_consumo (usuario_id);
-- Base da canonizacao das fases seguintes: casar o mesmo item por codigo de
-- barras (exato) ou pela descricao normalizada (deterministico).
create index if not exists itens_consumo_gtin_idx
  on public.itens_consumo (usuario_id, gtin) where gtin is not null;
create index if not exists itens_consumo_descricao_idx
  on public.itens_consumo (usuario_id, descricao_normalizada);

-- ------------------------------------------------------------------------- RLS
alter table public.estabelecimentos_consumo enable row level security;
alter table public.estabelecimentos_consumo force row level security;
alter table public.notas_consumo enable row level security;
alter table public.notas_consumo force row level security;
alter table public.itens_consumo enable row level security;
alter table public.itens_consumo force row level security;

drop policy if exists estabelecimentos_consumo_do_usuario on public.estabelecimentos_consumo;
create policy estabelecimentos_consumo_do_usuario on public.estabelecimentos_consumo
for all to authenticated
using ((select auth.uid()) = usuario_id)
with check ((select auth.uid()) = usuario_id);

drop policy if exists notas_consumo_do_usuario on public.notas_consumo;
create policy notas_consumo_do_usuario on public.notas_consumo
for all to authenticated
using ((select auth.uid()) = usuario_id)
with check ((select auth.uid()) = usuario_id);

drop policy if exists itens_consumo_do_usuario on public.itens_consumo;
create policy itens_consumo_do_usuario on public.itens_consumo
for all to authenticated
using ((select auth.uid()) = usuario_id)
with check ((select auth.uid()) = usuario_id);

revoke all on public.estabelecimentos_consumo from anon;
revoke all on public.notas_consumo from anon;
revoke all on public.itens_consumo from anon;
grant select, insert, update, delete on public.estabelecimentos_consumo to authenticated;
grant select, insert, update, delete on public.notas_consumo to authenticated;
grant select, insert, update, delete on public.itens_consumo to authenticated;

commit;
