-- Extrai a lista de compras da Culinaria sem apagar o historico existente.
--
-- As tabelas antigas continuam sendo a origem das listas ja montadas. O novo
-- catalogo guarda os produtos reutilizaveis da casa; cada item legado passa a
-- poder apontar para ele, e `versao` permite sincronizacao otimista em lotes.

begin;

create table public.produtos_lista_compras (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  vinculo_id uuid references public.vinculos_casal(id) on delete cascade,
  escopo_id uuid not null,
  chave text not null check (char_length(btrim(chave)) between 1 and 180),
  nome text not null check (char_length(btrim(nome)) between 1 and 120),
  categoria text not null default 'outros'
    check (
      categoria in (
        'hortifruti', 'padaria', 'carnes', 'laticinios', 'congelados',
        'mercearia', 'bebidas', 'limpeza', 'higiene', 'bebe', 'pet',
        'medicamentos', 'outros'
      )
    ),
  -- O asset visual pode chegar depois do cadastro do produto.
  icone text check (
    icone is null or char_length(btrim(icone)) between 1 and 80
  ),
  origem text not null default 'manual'
    check (origem in ('recorrencia', 'manual', 'legado')),
  ocorrencias integer not null default 0 check (ocorrencias >= 0),
  arquivado boolean not null default false,
  ordem integer not null default 0 check (ordem >= 0),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (escopo_id, chave),
  check (escopo_id = coalesce(vinculo_id, usuario_id))
);

create index produtos_lista_compras_catalogo_idx
  on public.produtos_lista_compras
  (escopo_id, arquivado, ordem, nome, id);
create index produtos_lista_compras_usuario_idx
  on public.produtos_lista_compras (usuario_id);
create index produtos_lista_compras_vinculo_idx
  on public.produtos_lista_compras (vinculo_id)
  where vinculo_id is not null;

create trigger produtos_lista_compras_atualizado_em
before update on public.produtos_lista_compras
for each row execute function public.definir_atualizado_em();

alter table public.produtos_lista_compras enable row level security;
alter table public.produtos_lista_compras force row level security;

create policy produtos_lista_compras_dos_membros
on public.produtos_lista_compras
for all to authenticated
using (
  (
    vinculo_id is null
    and escopo_id = usuario_id
    and (select auth.uid()) = usuario_id
  )
  or (
    vinculo_id is not null
    and escopo_id = vinculo_id
    and exists (
      select 1
        from public.vinculos_casal v
       where v.id = vinculo_id
         and v.status = 'ativo'
         and usuario_id in (v.criador_id, v.parceiro_id)
         and (select auth.uid()) in (v.criador_id, v.parceiro_id)
    )
  )
)
with check (
  (
    vinculo_id is null
    and escopo_id = usuario_id
    and (select auth.uid()) = usuario_id
  )
  or (
    vinculo_id is not null
    and escopo_id = vinculo_id
    and exists (
      select 1
        from public.vinculos_casal v
       where v.id = vinculo_id
         and v.status = 'ativo'
         and usuario_id in (v.criador_id, v.parceiro_id)
         and (select auth.uid()) in (v.criador_id, v.parceiro_id)
    )
  )
);

revoke all on public.produtos_lista_compras from anon;
grant select, insert, update, delete
  on public.produtos_lista_compras to authenticated;

alter table public.listas_compras_culinaria
  add column versao bigint not null default 1
    constraint listas_compras_culinaria_versao_positiva check (versao > 0);

alter table public.itens_lista_compras_culinaria
  add column produto_id uuid
    references public.produtos_lista_compras(id) on delete set null;

-- Prioridade do retrato que vira produto:
--   1. item da lista ativa (ajuste mais recente feito na lista);
--   2. alias aprendido pela lista;
--   3. alias revisado no antigo fluxo do Consumo;
--   4. item de uma lista ja concluida, para nao perder historico.
-- A origem recorrente e agregada separadamente: uma fonte `rotina` vence mesmo
-- quando o nome/categoria mais novo veio de outro retrato da mesma chave.
with aliases_consumo_escopo as (
  select
    a.usuario_id,
    v.id as vinculo_id,
    coalesce(v.id, a.usuario_id) as escopo_id,
    a.chave,
    a.nome_exibicao,
    a.categoria,
    a.criado_em,
    a.atualizado_em
  from public.aliases_produtos_consumo a
  left join lateral (
    select vinculo.id
      from public.vinculos_casal vinculo
     where vinculo.status = 'ativo'
       and a.usuario_id in (vinculo.criador_id, vinculo.parceiro_id)
     order by vinculo.atualizado_em desc, vinculo.id
     limit 1
  ) v on true
),
itens_legados as (
  select
    i.usuario_id,
    l.vinculo_id,
    coalesce(l.vinculo_id, l.usuario_id) as escopo_id,
    i.chave_canonica as chave,
    i.nome,
    i.categoria,
    case
      when exists (
        select 1
          from public.fontes_itens_lista_culinaria f
         where f.item_id = i.id and f.tipo = 'rotina'
      ) then 'recorrencia'
      when exists (
        select 1
          from public.fontes_itens_lista_culinaria f
         where f.item_id = i.id and f.tipo = 'manual'
      ) then 'manual'
      else 'legado'
    end as origem,
    i.ordem,
    i.criado_em,
    i.atualizado_em,
    case when l.status = 'ativa' then 10 else 40 end as prioridade,
    i.id::text as desempate
  from public.itens_lista_compras_culinaria i
  join public.listas_compras_culinaria l on l.id = i.lista_id
),
aliases_lista as (
  select
    a.usuario_id,
    a.vinculo_id,
    coalesce(a.vinculo_id, a.usuario_id) as escopo_id,
    a.chave_canonica as chave,
    a.nome,
    a.categoria,
    case a.origem_tipo
      when 'rotina' then 'recorrencia'
      when 'manual' then 'manual'
      else 'legado'
    end as origem,
    0 as ordem,
    a.criado_em,
    a.atualizado_em,
    20 as prioridade,
    a.id::text as desempate
  from public.aliases_lista_compras_culinaria a
),
aliases_consumo as (
  select
    a.usuario_id,
    a.vinculo_id,
    a.escopo_id,
    a.chave,
    a.nome_exibicao as nome,
    a.categoria,
    'recorrencia'::text as origem,
    0 as ordem,
    a.criado_em,
    a.atualizado_em,
    30 as prioridade,
    concat(a.usuario_id::text, ':', a.chave) as desempate
  from aliases_consumo_escopo a
),
candidatos as (
  select * from itens_legados
  union all
  select * from aliases_lista
  union all
  select * from aliases_consumo
),
ranqueados as (
  select
    candidato.*,
    bool_or(candidato.origem = 'recorrencia') over (
      partition by candidato.escopo_id, candidato.chave
    ) as tem_recorrencia,
    row_number() over (
      partition by candidato.escopo_id, candidato.chave
      order by
        candidato.prioridade,
        candidato.atualizado_em desc,
        candidato.criado_em desc,
        candidato.desempate
    ) as posicao
  from candidatos candidato
),
escolhidos as (
  select *
    from ranqueados
   where posicao = 1
),
referencias_consumo as (
  select distinct
    coalesce(l.vinculo_id, l.usuario_id) as escopo_id,
    i.chave_canonica as chave,
    i.usuario_id,
    l.vinculo_id,
    f.referencia_id as chave_consumo
  from public.itens_lista_compras_culinaria i
  join public.listas_compras_culinaria l on l.id = i.lista_id
  join public.fontes_itens_lista_culinaria f
    on f.item_id = i.id and f.tipo = 'rotina'

  union

  select distinct
    coalesce(a.vinculo_id, a.usuario_id) as escopo_id,
    a.chave_canonica as chave,
    a.usuario_id,
    a.vinculo_id,
    a.origem_chave as chave_consumo
  from public.aliases_lista_compras_culinaria a
  where a.origem_tipo = 'rotina'

  union

  select distinct
    a.escopo_id,
    a.chave,
    a.usuario_id,
    a.vinculo_id,
    a.chave as chave_consumo
  from aliases_consumo_escopo a
),
ocorrencias as (
  select
    referencia.escopo_id,
    referencia.chave,
    count(distinct item.nota_id) as total
  from referencias_consumo referencia
  join public.itens_consumo item
    on item.descricao_normalizada = referencia.chave_consumo
  left join public.vinculos_casal vinculo on vinculo.id = referencia.vinculo_id
  where
    (
      referencia.vinculo_id is null
      and item.usuario_id = referencia.usuario_id
    )
    or (
      referencia.vinculo_id is not null
      and item.usuario_id in (vinculo.criador_id, vinculo.parceiro_id)
    )
  group by referencia.escopo_id, referencia.chave
)
insert into public.produtos_lista_compras (
  usuario_id,
  vinculo_id,
  escopo_id,
  chave,
  nome,
  categoria,
  icone,
  origem,
  ocorrencias,
  arquivado,
  ordem,
  criado_em,
  atualizado_em
)
select
  escolhido.usuario_id,
  escolhido.vinculo_id,
  escolhido.escopo_id,
  escolhido.chave,
  escolhido.nome,
  escolhido.categoria,
  case
    when escolhido.chave = 'cebola'
      or lower(btrim(escolhido.nome)) = 'cebola'
      then 'cebola'
    when escolhido.chave = 'cheiro-verde'
      or lower(btrim(escolhido.nome)) = 'cheiro-verde'
      then 'cheiro-verde'
    when escolhido.chave = 'laranja'
      or lower(btrim(escolhido.nome)) = 'laranja'
      then 'laranja'
    when escolhido.chave = 'limao-tahiti'
      or lower(btrim(escolhido.nome)) = 'limão tahiti'
      then 'limao-tahiti'
    when escolhido.chave = 'mexerica-ponkan'
      or lower(btrim(escolhido.nome)) = 'mexerica ponkan'
      then 'mexerica-ponkan'
    when escolhido.chave = 'pao-de-forma-tradicional'
      or lower(btrim(escolhido.nome)) = 'pão de forma tradicional'
      then 'pao-de-forma-tradicional'
    when escolhido.chave = 'file-de-coxa'
      or lower(btrim(escolhido.nome)) = 'filé de coxa'
      then 'file-de-coxa'
    when escolhido.chave = 'iogurte-natural-desnatado'
      or lower(btrim(escolhido.nome)) = 'iogurte natural desnatado'
      then 'iogurte-natural-desnatado'
    when escolhido.chave = 'leite-integral'
      or lower(btrim(escolhido.nome)) = 'leite integral'
      then 'leite-integral'
    when escolhido.chave = 'queijo-mussarela'
      or lower(btrim(escolhido.nome)) = 'queijo mussarela'
      then 'queijo-mussarela'
    when escolhido.chave = 'queijo-parmesao'
      or lower(btrim(escolhido.nome)) = 'queijo parmesão'
      then 'queijo-parmesao'
    when escolhido.chave = 'energetico'
      or lower(btrim(escolhido.nome)) = 'energético'
      then 'energetico'
    when escolhido.chave = 'alcool-liquido'
      or lower(btrim(escolhido.nome)) = 'álcool líquido'
      then 'alcool-liquido'
    when escolhido.chave = 'saco-de-lixo'
      or lower(btrim(escolhido.nome)) = 'saco de lixo'
      then 'saco-de-lixo'
    when escolhido.chave = 'sabonete-em-barra'
      or lower(btrim(escolhido.nome)) = 'sabonete em barra'
      then 'sabonete-em-barra'
    when escolhido.chave = 'azeite'
      or lower(btrim(escolhido.nome)) = 'azeite'
      then 'azeite'
    -- Estes produtos não têm asset aprovado nesta versão. O cliente renderiza
    -- o cartão normalmente, sem tentar carregar uma imagem ausente.
    when escolhido.chave in (
      'acucar-refinado',
      'refrigerante-zero',
      'sacola-plastica',
      'papel-higienico'
    ) then null
    else null
  end as icone,
  case when escolhido.tem_recorrencia then 'recorrencia' else escolhido.origem end,
  least(coalesce(ocorrencia.total, 0), 2147483647)::integer,
  false,
  escolhido.ordem,
  escolhido.criado_em,
  escolhido.atualizado_em
from escolhidos escolhido
left join ocorrencias ocorrencia
  on ocorrencia.escopo_id = escolhido.escopo_id
 and ocorrencia.chave = escolhido.chave
on conflict (escopo_id, chave) do nothing;

-- Todo item legado tem uma candidatura acima, logo recebe o produto do mesmo
-- escopo e chave. A FK e anulavel para permitir apagar um produto do catalogo
-- sem apagar nem reescrever a lista historica.
update public.itens_lista_compras_culinaria item
   set produto_id = produto.id
  from public.listas_compras_culinaria lista
  join public.produtos_lista_compras produto
    on produto.escopo_id = coalesce(lista.vinculo_id, lista.usuario_id)
 where lista.id = item.lista_id
   and produto.chave = item.chave_canonica
   and item.produto_id is null;

create index itens_lista_compras_produto_idx
  on public.itens_lista_compras_culinaria (produto_id)
  where produto_id is not null;

commit;
