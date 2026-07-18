begin;

alter table public.ajustes_celulas_panorama
  drop constraint if exists ajustes_celulas_panorama_valor_check;

comment on column public.ajustes_celulas_panorama.valor is
  'Valor final da fonte na competencia; pode inverter o sentido financeiro da linha.';

commit;
