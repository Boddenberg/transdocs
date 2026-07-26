begin;

-- Historico do documento -----------------------------------------------------
--
-- A IA renomeia por cima. Sem trilha, uma renomeacao ruim e irreversivel — e e
-- justamente isso que torna renomear automatico assustador. Com a trilha, o
-- gesto vira barato: ela chuta, e voltar ao nome antigo e um clique.
--
-- Guarda tambem a mudanca de pasta e de prateleira, que e a mesma pergunta
-- feita de outro jeito ("onde isso estava antes?").
create table if not exists public.documentos_historico (
  id uuid primary key default gen_random_uuid(),
  documento_id uuid not null
    references public.documentos_financeiros(id) on delete cascade,
  usuario_id uuid not null references auth.users(id) on delete cascade,
  campo text not null check (campo in ('nome', 'pasta', 'categoria')),
  -- Texto legivel dos dois lados: para `pasta` e o caminho inteiro
  -- ("Moradia / Apartamento Rua X"), para a linha do tempo se ler sozinha sem
  -- precisar de join com uma pasta que talvez ja nem exista mais.
  valor_anterior text,
  valor_novo text,
  origem text not null check (origem in ('ia', 'pessoa')),
  criado_em timestamptz not null default now()
);

create index if not exists documentos_historico_idx
  on public.documentos_historico (documento_id, criado_em desc);

alter table public.documentos_historico enable row level security;
alter table public.documentos_historico force row level security;

drop policy if exists historico_do_proprio_usuario on public.documentos_historico;
create policy historico_do_proprio_usuario on public.documentos_historico
for all to authenticated
using ((select auth.uid()) = usuario_id)
with check (
  (select auth.uid()) = usuario_id
  and exists (
    select 1 from public.documentos_financeiros d
    where d.id = documento_id and d.usuario_id = (select auth.uid())
  )
);

revoke all on public.documentos_historico from anon;
grant select, insert, update, delete on public.documentos_historico to authenticated;

-- O que a IA leu do arquivo, em texto denso -----------------------------------
--
-- A ficha (nome, prateleira, descricao, validade) e o que aparece na tela. Este
-- resumo e o que a busca precisa: estabelecimento, valores, datas, itens, numeros
-- que ninguem poe no nome do arquivo.
--
-- E o que torna uma FOTO buscavel por conteudo. O extrator de texto so alcanca
-- PDF nativo (`app/aplicacao/rag/extracao.py`); a imagem devolvia vazio e ficava
-- fora do RAG. Agora o resumo lido pelo modelo multimodal vira o chunk dela.
alter table public.documentos_financeiros
  add column if not exists resumo_busca text
    check (resumo_busca is null or char_length(resumo_busca) between 1 and 4000);

commit;
