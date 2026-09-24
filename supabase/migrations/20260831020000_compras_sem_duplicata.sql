-- Funde os produtos que a migracao anterior criou em dobro.
--
-- `20260831010000` montou o catalogo a partir de quatro origens e deduplicou
-- por `(escopo_id, chave)`. So que as origens usam dois vocabularios de chave
-- diferentes para o mesmo produto:
--
--   * a descricao fiscal normalizada, truncada em 20 caracteres pela nota
--     ('qjo mus imp crfo kg', 'pao de forma tradici', 'leite italac integra');
--   * o slug do nome de exibicao ('queijo-mussarela', 'pao-de-forma-tradicional').
--
-- Como chave sao textos distintos, os dois entraram, e a tela mostrou duas
-- cebolas, duas laranjas, tres mussarelas. A familia do slug e a boa: e ela que
-- carrega o nome acentuado e o desenho.
--
-- Isto nao volta a acontecer: `chave_do_produto` (dominio/normalizacao.py) so
-- produz slug, e `unique (escopo_id, chave)` ja barra o repetido a partir dali.
-- A limpeza e retroativa e roda uma vez.

begin;

-- O nome comparavel: sem acento, sem pontuacao, caixa baixa. Sem depender da
-- extensao `unaccent`, que nao esta instalada neste projeto.
create or replace function pg_temp.nome_comparavel(nome text)
returns text language sql immutable as $$
  select btrim(
    regexp_replace(
      translate(
        lower(btrim(nome)),
        'áàâãäéèêëíìîïóòôõöúùûüçñ',
        'aaaaaeeeeiiiiooooouuuucn'
      ),
      '[^a-z0-9]+', ' ', 'g'
    )
  );
$$;

create temporary table fusao_compras on commit drop as
with ranqueados as (
  select
    produto.id,
    produto.escopo_id,
    produto.icone,
    produto.ocorrencias,
    pg_temp.nome_comparavel(produto.nome) as comparavel,
    row_number() over (
      partition by produto.escopo_id, pg_temp.nome_comparavel(produto.nome)
      order by
        -- Quem tem desenho vence; depois o slug (a familia fiscal tem espaco
        -- na chave); depois quem viu mais compras; e a data so desempata.
        (produto.icone is null),
        (produto.chave like '% %'),
        produto.ocorrencias desc,
        produto.criado_em,
        produto.id
    ) as posicao
  from public.produtos_lista_compras produto
  where not produto.arquivado
),
grupos as (
  select
    escopo_id,
    comparavel,
    -- Postgres nao tem min(uuid); a ordem por posicao ja poe o vencedor em 1o.
    (array_agg(id order by posicao))[1] as vencedor_id,
    max(ocorrencias) as ocorrencias,
    count(*) as membros
  from ranqueados
  group by escopo_id, comparavel
  having count(*) > 1
)
select
  ranqueado.id as perdedor_id,
  grupo.vencedor_id,
  grupo.ocorrencias,
  grupo.membros
from ranqueados ranqueado
join grupos grupo
  on grupo.escopo_id = ranqueado.escopo_id
 and grupo.comparavel = ranqueado.comparavel
where ranqueado.id <> grupo.vencedor_id;

-- 1. O vencedor herda a maior contagem de compras do grupo e, se lhe faltar
--    desenho, o primeiro desenho que algum irmao tiver.
update public.produtos_lista_compras vencedor
   set ocorrencias = greatest(vencedor.ocorrencias, fundido.ocorrencias),
       icone = coalesce(vencedor.icone, fundido.icone)
  from (
    select
      fusao.vencedor_id,
      max(fusao.ocorrencias) as ocorrencias,
      (array_remove(array_agg(perdedor.icone order by perdedor.id), null))[1] as icone
    from fusao_compras fusao
    join public.produtos_lista_compras perdedor on perdedor.id = fusao.perdedor_id
    group by fusao.vencedor_id
  ) fundido
 where vencedor.id = fundido.vencedor_id;

-- 2. Numa lista onde os dois produtos foram escolhidos sobram duas linhas para
--    o mesmo item. Guarda uma so: marcada se qualquer uma estava marcada, e com
--    a primeira quantidade escrita a mao. Precisa vir antes do passo 3 porque
--    `unique (lista_id, chave_canonica)` recusaria as duas com a mesma chave.
with itens_do_grupo as (
  select
    item.id,
    item.lista_id,
    coalesce(fusao.vencedor_id, item.produto_id) as destino_id,
    item.marcado,
    item.quantidade,
    item.criado_em
  from public.itens_lista_compras_culinaria item
  left join fusao_compras fusao on fusao.perdedor_id = item.produto_id
  where item.produto_id in (
    select perdedor_id from fusao_compras
    union
    select vencedor_id from fusao_compras
  )
),
consolidado as (
  select
    lista_id,
    destino_id,
    (array_agg(id order by criado_em, id))[1] as sobrevivente_id,
    bool_or(marcado) as marcado,
    (array_remove(array_agg(quantidade order by criado_em, id), null))[1] as quantidade
  from itens_do_grupo
  group by lista_id, destino_id
)
update public.itens_lista_compras_culinaria item
   set marcado = consolidado.marcado,
       quantidade = coalesce(item.quantidade, consolidado.quantidade)
  from consolidado
 where item.id = consolidado.sobrevivente_id;

delete from public.itens_lista_compras_culinaria item
 using (
   select
     item.id,
     row_number() over (
       partition by item.lista_id, coalesce(fusao.vencedor_id, item.produto_id)
       order by item.criado_em, item.id
     ) as posicao
   from public.itens_lista_compras_culinaria item
   left join fusao_compras fusao on fusao.perdedor_id = item.produto_id
   where item.produto_id in (
     select perdedor_id from fusao_compras
     union
     select vencedor_id from fusao_compras
   )
 ) ranqueado
 where ranqueado.id = item.id
   and ranqueado.posicao > 1;

-- 3. O que sobrou aponta para o vencedor e passa a falar o nome dele.
update public.itens_lista_compras_culinaria item
   set produto_id = vencedor.id,
       chave_canonica = vencedor.chave,
       nome = vencedor.nome,
       categoria = vencedor.categoria
  from fusao_compras fusao
  join public.produtos_lista_compras vencedor on vencedor.id = fusao.vencedor_id
 where item.produto_id = fusao.perdedor_id;

-- 4. Os perdedores saem do catalogo. Nada mais os referencia.
delete from public.produtos_lista_compras
 where id in (select perdedor_id from fusao_compras);

commit;
