begin;

-- Os dois potes de sabao da area de servico sao rapidos de repor, mas ficavam
-- fora do catalogo e por isso nunca entravam na rotina. A residencia alvo e
-- reconhecida pelo conjunto de atividades personalizado em 03/08, sem gravar
-- UUID de pessoa ou de casal na migration.
do $$
declare
  alvo uuid;
  executor uuid;
  ambiente uuid;
  categoria uuid;
  atividade_po uuid;
  atividade_liquido uuid;
  proxima_ordem integer;
  candidatos integer;
begin
  with catalogos_compativeis as (
    select atividade.vinculo_id
      from public.catalogo_atividades_casa as atividade
      join public.ambientes_catalogo_atividades_casa as ligacao
        on ligacao.atividade_id = atividade.id
      join public.ambientes_atividades_casa as ambiente_catalogo
        on ambiente_catalogo.id = ligacao.ambiente_id
     where atividade.status = 'ativa'
       and ambiente_catalogo.status = 'ativo'
       and ambiente_catalogo.slug = 'area-servico'
       and atividade.nome in (
         'Lavar lençol do quarto',
         'Estender nossos cobertores',
         'Trocar o tapetinho do cachorro',
         'Lavar a caminha do cachorro'
       )
     group by atividade.vinculo_id
    having count(distinct atividade.nome) = 4
  )
  select count(*), max(vinculo_id::text)::uuid
    into candidatos, alvo
    from catalogos_compativeis;

  if candidatos <> 1 then
    raise exception
      'Criação das reposições de sabão recusada: esperava uma residência compatível, encontrei %.',
      candidatos;
  end if;

  select vinculo.criador_id
    into strict executor
    from public.vinculos_casal as vinculo
   where vinculo.id = alvo
     and vinculo.status = 'ativo';

  select item.id
    into strict ambiente
    from public.ambientes_atividades_casa as item
   where item.vinculo_id = alvo
     and item.slug = 'area-servico'
     and item.status = 'ativo';

  select item.id
    into strict categoria
    from public.categorias_atividades_casa as item
   where item.vinculo_id = alvo
     and item.slug = 'limpeza'
     and item.status = 'ativa';

  select coalesce(max(item.ordem), -1) + 1
    into proxima_ordem
    from public.catalogo_atividades_casa as item
   where item.vinculo_id = alvo;

  insert into public.catalogo_atividades_casa (
    usuario_id,
    vinculo_id,
    categoria_id,
    nome,
    slug,
    peso_base,
    pontos_p,
    pontos_m,
    pontos_g,
    usa_ambiente,
    usa_dimensao,
    usa_quantidade,
    favorita,
    ordem,
    status,
    icone_caminho,
    icone_mime
  )
  values (
    executor,
    alvo,
    categoria,
    'Repor sabão em pó',
    'repor-sabao-em-po',
    5,
    5,
    10,
    15,
    true,
    false,
    false,
    false,
    proxima_ordem,
    'ativa',
    'icones/catalogo/repor-sabao-em-po.webp',
    'image/webp'
  )
  on conflict (vinculo_id, slug) do update set
    categoria_id = excluded.categoria_id,
    nome = excluded.nome,
    peso_base = excluded.peso_base,
    pontos_p = excluded.pontos_p,
    pontos_m = excluded.pontos_m,
    pontos_g = excluded.pontos_g,
    usa_ambiente = excluded.usa_ambiente,
    usa_dimensao = excluded.usa_dimensao,
    usa_quantidade = excluded.usa_quantidade,
    status = excluded.status,
    icone_caminho = excluded.icone_caminho,
    icone_mime = excluded.icone_mime,
    atualizado_em = now()
  returning id into atividade_po;

  insert into public.catalogo_atividades_casa (
    usuario_id,
    vinculo_id,
    categoria_id,
    nome,
    slug,
    peso_base,
    pontos_p,
    pontos_m,
    pontos_g,
    usa_ambiente,
    usa_dimensao,
    usa_quantidade,
    favorita,
    ordem,
    status,
    icone_caminho,
    icone_mime
  )
  values (
    executor,
    alvo,
    categoria,
    'Repor sabão líquido',
    'repor-sabao-liquido',
    5,
    5,
    10,
    15,
    true,
    false,
    false,
    false,
    proxima_ordem + 1,
    'ativa',
    'icones/catalogo/repor-sabao-liquido.webp',
    'image/webp'
  )
  on conflict (vinculo_id, slug) do update set
    categoria_id = excluded.categoria_id,
    nome = excluded.nome,
    peso_base = excluded.peso_base,
    pontos_p = excluded.pontos_p,
    pontos_m = excluded.pontos_m,
    pontos_g = excluded.pontos_g,
    usa_ambiente = excluded.usa_ambiente,
    usa_dimensao = excluded.usa_dimensao,
    usa_quantidade = excluded.usa_quantidade,
    status = excluded.status,
    icone_caminho = excluded.icone_caminho,
    icone_mime = excluded.icone_mime,
    atualizado_em = now()
  returning id into atividade_liquido;

  delete from public.ambientes_catalogo_atividades_casa
   where atividade_id in (atividade_po, atividade_liquido);

  insert into public.ambientes_catalogo_atividades_casa (
    usuario_id,
    atividade_id,
    ambiente_id
  )
  values
    (executor, atividade_po, ambiente),
    (executor, atividade_liquido, ambiente);
end;
$$;

commit;
