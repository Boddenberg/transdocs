begin;

do $$
declare
  recorrencias_removidas integer;
begin
  with recorrencias_duplicadas as (
    select recorrencia.id
    from public.recorrencias as recorrencia
    where recorrencia.ativa = true
      and recorrencia.detectada_por_ia = true
      and recorrencia.natureza = 'despesa'
      and lower(trim(recorrencia.descricao)) in (
        'financiamento apartamento',
        'pagamento de financiamento'
      )
      and recorrencia.valor_estimado = 4687.18
      and exists (
        select 1
        from public.dividas as divida
        join public.parcelas_divida as parcela on parcela.divida_id = divida.id
        where divida.usuario_id = recorrencia.usuario_id
          and divida.status <> 'cancelada'
          and lower(divida.descricao) like '%financiamento%'
          and lower(divida.descricao) like '%apartamento%'
          and parcela.status <> 'cancelada'
          and abs(parcela.valor_total - recorrencia.valor_estimado) <= 0.01
          and (
            recorrencia.proxima_data is null
            or abs(
              extract(year from parcela.data_vencimento) * 12
              + extract(month from parcela.data_vencimento)
              - extract(year from recorrencia.proxima_data) * 12
              - extract(month from recorrencia.proxima_data)
            ) <= 1
          )
          and (
            select count(*)
            from public.parcelas_divida as cronograma
            where cronograma.divida_id = divida.id
              and cronograma.status <> 'cancelada'
          ) >= 12
      )
  )
  delete from public.recorrencias as recorrencia
  using recorrencias_duplicadas as duplicada
  where recorrencia.id = duplicada.id;

  get diagnostics recorrencias_removidas = row_count;
  if recorrencias_removidas = 0 then
    raise exception 'A recorrencia duplicada do financiamento do apartamento nao foi encontrada.';
  end if;
end;
$$;

commit;
