begin;

-- O catálogo da residência é personalizado e, por isso, não deve ser alterado
-- em outras casas. As atividades abaixo também formam a especificação da
-- mudança: as duas etapas do pano de chão continuam separadas e as três tarefas
-- de refeição entram no cômodo em que acontecem.
create temporary table atividades_solicitadas_casa (
  ordem_relativa integer primary key,
  ambiente_slug text not null,
  categoria_slug text not null,
  nome text not null,
  slug text not null unique,
  pontos_p numeric(8, 2) not null check (pontos_p > 0),
  icone_caminho text not null
) on commit drop;

insert into atividades_solicitadas_casa (
  ordem_relativa,
  ambiente_slug,
  categoria_slug,
  nome,
  slug,
  pontos_p,
  icone_caminho
)
values
  (0, 'cozinha', 'cozinha', 'Fazer almoço', 'fazer-almoco', 45,
   'icones/catalogo/fazer-almoco.webp'),
  (1, 'cozinha', 'cozinha', 'Esquentar a marmita do casal',
   'esquentar-a-marmita-do-casal', 10,
   'icones/catalogo/esquentar-a-marmita-do-casal.webp'),
  (2, 'sala', 'limpeza', 'Retirar a janta da mesa',
   'retirar-a-janta-da-mesa', 10,
   'icones/catalogo/retirar-a-janta-da-mesa.webp'),
  (3, 'area-servico', 'limpeza', 'Lavar pano de chão',
   'lavar-pano-de-chao', 10,
   'icones/catalogo/lavar-pano-de-chao.webp'),
  (4, 'area-servico', 'limpeza', 'Estender pano de chão',
   'estender-pano-de-chao', 10,
   'icones/catalogo/estender-pano-de-chao.webp');

do $$
declare
  alvo uuid;
  executor uuid;
  proxima_ordem integer;
  candidatos integer;
  atividades_catalogadas integer;
begin
  -- A residência alvo é reconhecida por atividades específicas do catálogo
  -- personalizado e pelas duas reposições adicionadas em 09/08. Nenhum UUID
  -- de pessoa ou casal fica gravado no histórico de migrations.
  with catalogos_compativeis as (
    select atividade.vinculo_id
      from public.catalogo_atividades_casa as atividade
      join public.ambientes_catalogo_atividades_casa as ligacao
        on ligacao.atividade_id = atividade.id
      join public.ambientes_atividades_casa as ambiente
        on ambiente.id = ligacao.ambiente_id
     where atividade.status = 'ativa'
       and ambiente.status = 'ativo'
       and (ambiente.slug, atividade.nome) in (
         ('cozinha', 'Fazer janta'),
         ('cozinha', 'Fazer marmita'),
         ('sala', 'Limpar a mesa'),
         ('sala', 'Limpar o canto alemão'),
         ('area-servico', 'Lavar a caminha do cachorro'),
         ('area-servico', 'Repor sabão em pó'),
         ('area-servico', 'Repor sabão líquido')
       )
     group by atividade.vinculo_id
    having count(distinct (ambiente.slug, atividade.nome)) = 7
  )
  select count(*), max(vinculo_id::text)::uuid
    into candidatos, alvo
    from catalogos_compativeis;

  if candidatos <> 1 then
    raise exception
      'Criação das atividades de refeição recusada: esperava uma residência compatível, encontrei %.',
      candidatos;
  end if;

  select vinculo.criador_id
    into strict executor
    from public.vinculos_casal as vinculo
   where vinculo.id = alvo
     and vinculo.status = 'ativo';

  select coalesce(max(atividade.ordem), -1) + 1
    into proxima_ordem
    from public.catalogo_atividades_casa as atividade
   where atividade.vinculo_id = alvo;

  insert into public.catalogo_atividades_casa as existente (
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
  select
    executor,
    alvo,
    categoria.id,
    solicitada.nome,
    solicitada.slug,
    solicitada.pontos_p,
    solicitada.pontos_p,
    solicitada.pontos_p * 2,
    solicitada.pontos_p * 3,
    true,
    false,
    false,
    false,
    proxima_ordem + solicitada.ordem_relativa,
    'ativa',
    solicitada.icone_caminho,
    'image/webp'
  from atividades_solicitadas_casa as solicitada
  join public.categorias_atividades_casa as categoria
    on categoria.vinculo_id = alvo
   and categoria.slug = solicitada.categoria_slug
   and categoria.status = 'ativa'
  on conflict (vinculo_id, slug) do update set
    categoria_id = excluded.categoria_id,
    nome = excluded.nome,
    usa_ambiente = excluded.usa_ambiente,
    usa_dimensao = excluded.usa_dimensao,
    usa_quantidade = excluded.usa_quantidade,
    status = excluded.status,
    icone_caminho = excluded.icone_caminho,
    icone_mime = excluded.icone_mime,
    atualizado_em = now();

  -- Regravar a ligação também corrige uma atividade antiga que tenha ficado
  -- sem cômodo. A restrição de atividade única por cômodo impede duplicidade.
  delete from public.ambientes_catalogo_atividades_casa as ligacao
   using public.catalogo_atividades_casa as atividade,
         atividades_solicitadas_casa as solicitada
   where ligacao.atividade_id = atividade.id
     and atividade.vinculo_id = alvo
     and atividade.slug = solicitada.slug;

  insert into public.ambientes_catalogo_atividades_casa (
    usuario_id,
    atividade_id,
    ambiente_id
  )
  select
    executor,
    atividade.id,
    ambiente.id
  from atividades_solicitadas_casa as solicitada
  join public.catalogo_atividades_casa as atividade
    on atividade.vinculo_id = alvo
   and atividade.slug = solicitada.slug
  join public.ambientes_atividades_casa as ambiente
    on ambiente.vinculo_id = alvo
   and ambiente.slug = solicitada.ambiente_slug
   and ambiente.status = 'ativo';

  select count(*)
    into atividades_catalogadas
    from atividades_solicitadas_casa as solicitada
    join public.catalogo_atividades_casa as atividade
      on atividade.vinculo_id = alvo
     and atividade.slug = solicitada.slug
     and atividade.status = 'ativa'
    join public.ambientes_catalogo_atividades_casa as ligacao
      on ligacao.atividade_id = atividade.id
    join public.ambientes_atividades_casa as ambiente
      on ambiente.id = ligacao.ambiente_id
     and ambiente.slug = solicitada.ambiente_slug
     and ambiente.status = 'ativo';

  if atividades_catalogadas <> 5 then
    raise exception
      'Criação das atividades de refeição recusada: esperava mapear 5 atividades, mapeei %.',
      atividades_catalogadas;
  end if;
end;
$$;

commit;
