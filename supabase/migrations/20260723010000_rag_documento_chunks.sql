-- RAG "pergunte aos seus contratos": indexa o texto integral dos documentos
-- ja ingeridos em chunks vetorizados, para responder pela clausula real.
--
-- O texto do PDF nao e persistido hoje (o analisador manda o arquivo direto ao
-- modelo multimodal e descarta o texto), entao esta tabela e populada por um
-- backfill que baixa cada documento do Storage, extrai o texto, quebra em chunks
-- e grava o embedding de cada um. Um chunk = uma passagem curta; a busca traz os
-- top-k mais proximos da pergunta, nunca o documento inteiro.

begin;

-- pgvector. No Supabase costuma vir provisionado no schema `extensions`; o
-- `if not exists` torna a linha um no-op quando ja esta habilitado.
create extension if not exists vector;

create table if not exists public.documento_chunks (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  documento_id uuid not null
    references public.documentos_financeiros(id) on delete cascade,
  ordem integer not null check (ordem >= 0),
  pagina integer check (pagina is null or pagina >= 1),
  conteudo text not null check (char_length(conteudo) between 1 and 8000),
  tokens_estimados integer check (tokens_estimados is null or tokens_estimados >= 0),
  embedding vector(1536) not null,
  modelo_embedding text not null,
  criado_em timestamptz not null default now(),
  unique (documento_id, ordem)
);

create index if not exists documento_chunks_documento_idx
  on public.documento_chunks (documento_id, ordem);
create index if not exists documento_chunks_usuario_idx
  on public.documento_chunks (usuario_id);

-- Indice de vizinhanca aproximada (HNSW, distancia de cosseno). Casa com o
-- operador <=> usado na funcao de busca abaixo.
create index if not exists documento_chunks_embedding_idx
  on public.documento_chunks
  using hnsw (embedding vector_cosine_ops);

alter table public.documento_chunks enable row level security;
alter table public.documento_chunks force row level security;

drop policy if exists documento_chunks_do_proprio_usuario on public.documento_chunks;
create policy documento_chunks_do_proprio_usuario on public.documento_chunks
for all to authenticated
using ((select auth.uid()) = usuario_id)
with check (
  (select auth.uid()) = usuario_id
  and exists (
    select 1 from public.documentos_financeiros d
    where d.id = documento_id and d.usuario_id = (select auth.uid())
  )
);

revoke all on public.documento_chunks from anon;
grant select, insert, update, delete on public.documento_chunks to authenticated;

-- Busca semantica. O backend usa a service role (RLS e ignorada), por isso a
-- funcao filtra por usuario explicitamente; `p_documento` restringe a um
-- documento so ("tem multa nesse contrato?"). Menor distancia = mais relevante.
create or replace function public.match_documento_chunks(
  consulta vector(1536),
  p_usuario uuid,
  limite integer default 6,
  p_documento uuid default null
)
returns table (
  id uuid,
  documento_id uuid,
  ordem integer,
  pagina integer,
  conteudo text,
  distancia double precision
)
language sql
stable
as $$
  select
    c.id,
    c.documento_id,
    c.ordem,
    c.pagina,
    c.conteudo,
    (c.embedding <=> consulta) as distancia
  from public.documento_chunks c
  where c.usuario_id = p_usuario
    and (p_documento is null or c.documento_id = p_documento)
  order by c.embedding <=> consulta
  limit greatest(limite, 1);
$$;

revoke all on function public.match_documento_chunks(vector, uuid, integer, uuid) from anon;
grant execute on function public.match_documento_chunks(vector, uuid, integer, uuid)
  to authenticated, service_role;

commit;
