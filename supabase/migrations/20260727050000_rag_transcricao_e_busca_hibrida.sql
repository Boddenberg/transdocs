-- O arquivo deixa de ser achavel e passa a ser respondivel.
--
-- Ate aqui o RAG guardava chunks, mas o que entrava neles era pouco: o
-- extrator so lia PDF nativo, e todo o resto (foto, escaneado) caia no
-- `resumo_busca` — 1200 caracteres de RESUMO. Resumo responde "que papel e
-- este"; nao responde "quanto e a parcela 200". Tres mudancas consertam isso:
--
-- 1. `natureza` separa o papel da cena. A foto do cachorro continua achavel
--    pela ficha, mas nao entra no motor de resposta — ninguem quer que a IA
--    opine sobre a cor de uma cadeira citando "o documento".
-- 2. `documento_textos` guarda a transcricao integral, pagina a pagina. Ela
--    custa visao para nascer; guardada, reindexar nunca mais repaga o OCR.
-- 3. A busca deixa de ser so vetorial. Cosseno erra numero — "parcela 200" e
--    "parcela 20" moram no mesmo bairro do espaco vetorial. O full-text acha a
--    linha exata, e a fusao dos dois rankings (RRF) devolve o melhor dos dois.

begin;

-- 1. Que tipo de papel e este ------------------------------------------------
--
-- Nulo = ainda nao se sabe (a base antiga chega assim, e o backfill preenche).
-- Quem le trata nulo como `documento`, para nada regredir enquanto a fila anda.
alter table public.documentos_financeiros
  add column if not exists natureza text
    check (natureza is null or natureza in ('documento', 'cena'));

-- Em que pe esta a transcricao deste arquivo. Existe para o backfill saber o
-- que ja tentou: sem isto ele reabriria para sempre o escaneado ilegivel.
alter table public.documentos_financeiros
  add column if not exists transcricao_status text not null default 'pendente'
    check (
      transcricao_status in
        ('pendente', 'transcrito', 'sem_texto', 'cena', 'erro')
    );

alter table public.documentos_financeiros
  add column if not exists transcricao_em timestamptz;

comment on column public.documentos_financeiros.natureza is
  'documento = tem fatos para responder; cena = foto comum, so achavel.';
comment on column public.documentos_financeiros.transcricao_status is
  'pendente | transcrito | sem_texto | cena | erro — a fila do backfill do RAG.';

-- 2. A transcricao, guardada -------------------------------------------------
--
-- Separada de documento_chunks de proposito: o chunk e uma decisao de
-- recuperacao (tamanho da janela, sobreposicao) e pode mudar; o texto lido do
-- papel e um fato e nao deve ser relido por causa de um ajuste de chunking.
create table if not exists public.documento_textos (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  documento_id uuid not null
    references public.documentos_financeiros(id) on delete cascade,
  ordem integer not null check (ordem >= 0),
  pagina integer check (pagina is null or pagina >= 1),
  conteudo text not null check (char_length(conteudo) between 1 and 200000),
  -- pdf = pypdf leu o texto nativo (de graca); visao = o modelo transcreveu a
  -- imagem; resumo = nao deu para transcrever e o que ha e a ficha lida.
  origem text not null check (origem in ('pdf', 'visao', 'resumo')),
  modelo text,
  criado_em timestamptz not null default now(),
  unique (documento_id, ordem)
);

create index if not exists documento_textos_documento_idx
  on public.documento_textos (documento_id, ordem);
create index if not exists documento_textos_usuario_idx
  on public.documento_textos (usuario_id);

alter table public.documento_textos enable row level security;
alter table public.documento_textos force row level security;

drop policy if exists documento_textos_do_proprio_usuario on public.documento_textos;
create policy documento_textos_do_proprio_usuario on public.documento_textos
for all to authenticated
using ((select auth.uid()) = usuario_id)
with check (
  (select auth.uid()) = usuario_id
  and exists (
    select 1 from public.documentos_financeiros d
    where d.id = documento_id and d.usuario_id = (select auth.uid())
  )
);

revoke all on public.documento_textos from anon;
grant select, insert, update, delete on public.documento_textos to authenticated;

-- 3. O chunk diz de onde veio, e ganha indice lexical ------------------------
--
-- `origem` importa na hora de responder: um trecho transcrito e o papel
-- falando, um trecho de resumo e a IA resumindo. Quem responde precisa saber a
-- diferenca para nao apresentar parafrase como se fosse clausula.
alter table public.documento_chunks
  add column if not exists origem text not null default 'texto'
    check (origem in ('texto', 'resumo'));

-- Coluna gerada: nasce e se atualiza sozinha com o conteudo, entao nao ha como
-- o indice lexical ficar fora de sincronia com o texto do chunk.
alter table public.documento_chunks
  add column if not exists busca tsvector
    generated always as (to_tsvector('portuguese'::regconfig, conteudo)) stored;

create index if not exists documento_chunks_busca_idx
  on public.documento_chunks using gin (busca);

-- 4. Busca hibrida: vetor + palavra, fundidos por RRF ------------------------
--
-- Reciprocal Rank Fusion: cada lista contribui 1/(k + posicao). Um trecho que
-- aparece bem nas duas sobe acima de um que lidera so uma. `k` alto (60, o
-- valor classico) achata a diferenca entre as primeiras posicoes, o que evita
-- que o primeiro colocado de uma lista ruim domine o resultado.
--
-- `apenas_documentos` e o que impede a foto do cachorro de virar fonte de
-- resposta. A busca de ARQUIVO (achar o papel) passa false e enxerga tudo; a
-- de CONTEUDO (responder pelo papel) passa true.
create or replace function public.buscar_documento_chunks(
  consulta vector(1536),
  termos text,
  p_usuario uuid,
  limite integer default 8,
  p_documento uuid default null,
  p_parceiro uuid default null,
  apenas_documentos boolean default false
)
returns table (
  id uuid,
  documento_id uuid,
  ordem integer,
  pagina integer,
  conteudo text,
  origem text,
  distancia double precision,
  escore double precision,
  lexical boolean
)
language sql
stable
as $$
  with visiveis as (
    select c.id, c.documento_id, c.ordem, c.pagina, c.conteudo, c.origem,
           c.embedding, c.busca
      from public.documento_chunks c
      join public.documentos_financeiros d on d.id = c.documento_id
     where (
             c.usuario_id = p_usuario
             or (
               p_parceiro is not null
               and c.usuario_id = p_parceiro
               and d.compartilhado_casal
             )
           )
       and (p_documento is null or c.documento_id = p_documento)
       -- Nulo conta como documento: a base antiga ainda nao foi classificada e
       -- sumir com ela seria pior do que deixar passar uma foto.
       and (
             not apenas_documentos
             or coalesce(d.natureza, 'documento') = 'documento'
           )
  ),
  consulta_texto as (
    -- **OU, e nao E.** `plainto_tsquery` liga os termos com `&`, e uma pergunta
    -- inteira ("quanto pago na parcela 200") exigiria que o trecho contivesse
    -- TODAS as palavras. A linha que responde — "200 | 12/06/2043 |
    -- R$ 1.234,56" — nao tem "quanto" nem "pago", e ficaria de fora justamente
    -- por ser uma linha de tabela. Trocando `&` por `|`, ela entra; e o
    -- ts_rank_cd continua premiando quem casa mais termos, entao o ranking nao
    -- se perde. Empty tsquery vira NULL para o braco lexical simplesmente nao
    -- rodar quando a pergunta so tem palavra vazia.
    -- Monta-se a partir dos lexemas, e nao trocando '&' por '|' no texto de um
    -- `plainto_tsquery`: um termo que vire token de URL ou e-mail carrega '&'
    -- dentro de si, e o replace produziria uma tsquery invalida — erro duro,
    -- justo na busca. `quote_literal` fecha cada lexema, entao nao ha texto de
    -- pergunta capaz de quebrar a consulta.
    select nullif(
             (
               select string_agg(quote_literal(l.lexeme), ' | ')
                 from unnest(
                        to_tsvector('portuguese'::regconfig, coalesce(termos, ''))
                      ) as l
             ),
             ''
           )::tsquery as q
  ),
  por_vetor as (
    select v.id,
           (v.embedding <=> consulta) as distancia,
           row_number() over (order by v.embedding <=> consulta) as posicao
      from visiveis v
     order by v.embedding <=> consulta
     limit greatest(limite, 1) * 4
  ),
  por_texto as (
    select v.id,
           row_number() over (
             order by ts_rank_cd(v.busca, t.q) desc, v.id
           ) as posicao
      from visiveis v, consulta_texto t
     where t.q is not null
       and v.busca @@ t.q
     order by ts_rank_cd(v.busca, t.q) desc, v.id
     limit greatest(limite, 1) * 4
  ),
  fundidos as (
    select coalesce(pv.id, pt.id) as id,
           pv.distancia,
           -- Achado pela palavra, e **bem** achado: quem carrega este selo passa
           -- por cima do filtro de distancia, porque se a pergunta esta escrita
           -- ali a proximidade vetorial virou detalhe — e o trecho com "parcela
           -- 200" por extenso o vetor nunca traria na frente de "parcela 20".
           --
           -- So que a consulta e um OU: um trecho que casou apenas "quanto"
           -- tambem aparece nesta lista, e deixa-lo furar o filtro esvaziaria o
           -- filtro. Por isso o selo vai so para o topo do ranking lexical, que
           -- e onde o ts_rank_cd ja concentrou quem casou mais termos.
           (pt.posicao is not null and pt.posicao <= greatest(limite, 1)) as lexical,
           -- Casts explicitos: uma funcao SQL exige que o tipo da coluna
           -- devolvida bata com o declarado, e numeric -> double precision nao
           -- e conversao implicita. Sem isto a funcao nem chega a ser criada.
           (
             coalesce(1.0::double precision / (60 + pv.posicao), 0)
             + coalesce(1.0::double precision / (60 + pt.posicao), 0)
           )::double precision as escore
      from por_vetor pv
      full outer join por_texto pt on pt.id = pv.id
  )
  select v.id,
         v.documento_id,
         v.ordem,
         v.pagina,
         v.conteudo,
         v.origem,
         -- Sem posicao no vetor (so o full-text achou), a distancia e
         -- desconhecida. 1.0 e o "totalmente distante" do cosseno normalizado:
         -- quem filtra por distancia descarta, quem confia no escore mantem.
         coalesce(f.distancia, 1.0::double precision) as distancia,
         f.escore,
         f.lexical
    from fundidos f
    join visiveis v on v.id = f.id
   order by f.escore desc, coalesce(f.distancia, 1.0)
   limit greatest(limite, 1);
$$;

revoke all on function public.buscar_documento_chunks(
  vector, text, uuid, integer, uuid, uuid, boolean
) from anon;
grant execute on function public.buscar_documento_chunks(
  vector, text, uuid, integer, uuid, uuid, boolean
) to authenticated, service_role;

commit;
