-- A notinha do mercado passa a servir dois apps, e a gaveta precisa dizer isso.
--
-- Ate aqui a nota fiscal so tinha o selo do FiNancas: foi ele quem leu o
-- arquivo item a item. Mas quem usa o resultado agora sao dois — a Culinaria
-- monta a despensa e a lista de compras em cima dos mesmos itens. Sem esta
-- linha, apagar uma nota na gaveta pareceria custar so um lancamento, quando
-- na verdade tira comida da despensa e itens da lista do mercado.
--
-- A view continua sendo o contrato generico do acervo: `documento_id` e
-- `app_id` projetados sobre referencias REAIS, nunca sobre uma suposicao.
create or replace view public.usos_documentos_apps
with (security_invoker = true)
as
  select c.documento_id, c.usuario_id, 'financas'::text as app_id
    from public.capturas_ia c
   where c.documento_id is not null
  union
  select n.documento_id, n.usuario_id, 'financas'::text as app_id
    from public.notas_consumo n
   where n.documento_id is not null
  union
  -- A Culinaria le TODA nota, e nao so as de comida: a base da lista de
  -- compras e a recorrencia do carrinho inteiro (o sabao em po tambem se
  -- repete). A despensa, essa sim, filtra as categorias de comida depois.
  select n.documento_id, n.usuario_id, 'culinaria'::text as app_id
    from public.notas_consumo n
   where n.documento_id is not null
  union
  select r.documento_id, r.usuario_id, 'culinaria'::text as app_id
    from public.receitas_culinaria r
   where r.documento_id is not null;

revoke all on public.usos_documentos_apps from anon;
grant select on public.usos_documentos_apps to authenticated, service_role;
