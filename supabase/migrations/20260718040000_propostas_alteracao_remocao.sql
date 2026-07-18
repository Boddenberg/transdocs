-- O Financas AI passa a proper edicoes e remocoes de registros existentes
-- (movimentacoes, recorrencias e parcelas de divida) alem de criacoes.
alter table public.propostas_ia
  drop constraint if exists propostas_ia_tipo_check;

alter table public.propostas_ia
  add constraint propostas_ia_tipo_check check (tipo in (
    'movimentacao', 'divida', 'recorrencia', 'conta', 'insight', 'alteracao', 'remocao'
  ));
