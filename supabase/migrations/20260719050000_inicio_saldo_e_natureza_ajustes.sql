begin;

alter table public.preferencias_usuario
  add column if not exists panorama_inicio_saldo_acumulado date;

alter table public.preferencias_usuario
  add constraint preferencias_inicio_saldo_primeiro_dia_check
  check (
    panorama_inicio_saldo_acumulado is null
    or panorama_inicio_saldo_acumulado = date_trunc(
      'month', panorama_inicio_saldo_acumulado
    )::date
  );

update public.ajustes_celulas_panorama
set valor = abs(valor)
where valor < 0;

alter table public.ajustes_celulas_panorama
  add constraint ajustes_celulas_panorama_valor_check check (valor >= 0);

comment on column public.preferencias_usuario.panorama_inicio_saldo_acumulado is
  'Primeira competencia confiavel do saldo acumulado; null usa o primeiro mes preenchido.';

comment on column public.ajustes_celulas_panorama.valor is
  'Magnitude final da fonte na competencia; o grupo preserva a natureza de entrada ou saida.';

commit;
