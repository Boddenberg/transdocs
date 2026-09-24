-- A lista fechada vira uma entidade que se abre de novo.
--
-- O historico ja existia inteiro no banco: fechar uma lista sempre gravou
-- `status = 'concluida'` e `concluida_em`, e os itens continuam apontando para
-- ela por `lista_id`. O que faltava era um nome e um jeito de encontra-la.
--
-- `nome` e opcional porque nomear uma compra e trabalho, e quase toda compra
-- nao precisa de nome proprio: sem ele o cliente escreve "Compra de setembro"
-- a partir de `concluida_em`. Guardar o gerado no banco seria congelar uma
-- frase que a lingua da interface pode querer mudar depois.

begin;

alter table public.listas_compras_culinaria
  add column if not exists nome text
    check (nome is null or char_length(btrim(nome)) between 1 and 80);

-- O historico e sempre lido por escopo e da mais recente para a mais antiga.
-- O indice antigo (`usuario_id, criado_em desc`) nao serve para a lista do
-- casal, que e encontrada por `vinculo_id`, e nem para a ordem que a tela usa.
create index if not exists listas_compras_concluidas_idx
  on public.listas_compras_culinaria
  (coalesce(vinculo_id, usuario_id), concluida_em desc)
  where status = 'concluida';

commit;
