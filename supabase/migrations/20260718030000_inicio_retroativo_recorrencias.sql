begin;

alter table public.recorrencias
  add column if not exists data_inicio date;

comment on column public.recorrencias.data_inicio is
  'Quando definida, o panorama projeta a recorrencia retroativamente a partir deste mes.';

commit;
