-- Desconto e acrescimo (taxa/servico/frete) no nivel da nota de consumo. A IA
-- nem sempre isola esses valores; aqui o usuario pode registra-los a mao. O
-- valor_total ja embute o ajuste (delta aplicado ao total ao editar), estes
-- campos guardam quanto foi de desconto e quanto foi de taxa para o detalhamento.

begin;

alter table public.notas_consumo
  add column if not exists desconto numeric(14, 2)
    check (desconto is null or desconto >= 0),
  add column if not exists acrescimo numeric(14, 2)
    check (acrescimo is null or acrescimo >= 0);

commit;
