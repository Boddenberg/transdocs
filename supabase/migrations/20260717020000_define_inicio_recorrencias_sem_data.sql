begin;

update public.recorrencias
set proxima_data = criado_em::date
where ativa = true
  and proxima_data is null;

commit;
