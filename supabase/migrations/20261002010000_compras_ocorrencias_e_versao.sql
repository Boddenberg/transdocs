-- O catalogo volta a aprender com as compras, e a versao da lista para de se
-- perder.
--
-- 1. `ocorrencias` conta em quantas compras o produto entrou. A migracao de
--    31/08 importou essa conta das notas fiscais, mas fechar uma lista no
--    aplicativo nunca somou nada: "O de sempre" (que pede duas) e a ordem por
--    mais comprados congelaram no dia da importacao. Agora fechar a lista
--    credita cada produto que esta nela, uma vez por lista, e as listas ja
--    fechadas desde a importacao entram de uma vez, no fim deste arquivo.
--
--    Credita o que entrou na lista, e nao so o que foi marcado: desde 04/09
--    fechar e o fim de montar, e o "pego" acontece depois, no mercado, sobre a
--    lista ja fechada. E a mesma conta que o ritmo faz com o historico.
--
-- 2. `versao` era lida e reescrita em duas chamadas. Dois aparelhos mexendo na
--    mesma lista liam o mesmo numero e gravavam o mesmo numero, e o cliente
--    que compara versoes para descartar resposta velha passava a comparar dois
--    numeros iguais. Um `set versao = versao + 1` dentro do banco nao tem esse
--    intervalo.
--
-- As duas funcoes sao chamadas somente pelo backend, com a chave de servico:
-- `anon` e `authenticated` ficam de fora.

begin;

-- Um passo de versao, sem o intervalo entre ler e escrever. Devolve a versao
-- nova, ou `null` quando a lista ja nao esta ativa.
create or replace function public.tocar_lista_compras(p_lista_id uuid)
returns integer
language sql
volatile
security definer
set search_path = ''
as $$
  update public.listas_compras_culinaria
     set versao = versao + 1
   where id = p_lista_id
     and status = 'ativa'
  returning versao;
$$;

-- Fecha a compra e credita o catalogo, numa transacao so. Idempotente: o
-- `status = 'ativa'` faz a segunda chamada (toque duplo, repeticao depois de
-- um tempo limite) nao contar de novo. Devolve quantos produtos foram
-- creditados, ou `null` quando a lista ja estava fechada.
create or replace function public.concluir_lista_compras(p_lista_id uuid, p_nome text default null)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_creditados integer;
begin
  update public.listas_compras_culinaria
     set status = 'concluida',
         concluida_em = now(),
         nome = coalesce(p_nome, nome)
   where id = p_lista_id
     and status = 'ativa';

  if not found then
    return null;
  end if;

  with entraram as (
    select distinct item.produto_id
      from public.itens_lista_compras_culinaria item
     where item.lista_id = p_lista_id
       and item.produto_id is not null
  )
  update public.produtos_lista_compras produto
     set ocorrencias = produto.ocorrencias + 1
    from entraram
   where produto.id = entraram.produto_id;

  get diagnostics v_creditados = row_count;
  return v_creditados;
end;
$$;

revoke all on function public.tocar_lista_compras(uuid) from public, anon, authenticated;
revoke all on function public.concluir_lista_compras(uuid, text) from public, anon, authenticated;

-- As compras fechadas no aplicativo desde a importacao, que nunca somaram.
with entradas as (
  select item.produto_id, count(distinct lista.id) as vezes
    from public.listas_compras_culinaria lista
    join public.itens_lista_compras_culinaria item on item.lista_id = lista.id
   where lista.status = 'concluida'
     and lista.concluida_em >= timestamptz '2026-08-31 00:00:00-03'
     and item.produto_id is not null
   group by item.produto_id
)
update public.produtos_lista_compras produto
   set ocorrencias = produto.ocorrencias + entradas.vezes
  from entradas
 where produto.id = entradas.produto_id;

commit;
