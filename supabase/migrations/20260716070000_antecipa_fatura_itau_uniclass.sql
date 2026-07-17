begin;

do $$
declare
  movimentacoes_alteradas integer;
begin
  with cartoes_alvo as (
    select movimentacao.usuario_id, movimentacao.conta_id
    from public.movimentacoes as movimentacao
    join public.contas as conta on conta.id = movimentacao.conta_id
    where lower(trim(conta.nome)) in (
      'cartão itaú uniclass', 'cartao itau uniclass', 'itaú uniclass', 'itau uniclass'
    )
      and movimentacao.status <> 'cancelada'
      and movimentacao.mes_competencia >= date '2026-08-01'
      and movimentacao.mes_competencia < date '2027-03-01'
    group by movimentacao.usuario_id, movimentacao.conta_id
    having
      sum(case when movimentacao.natureza = 'receita' then -movimentacao.valor else movimentacao.valor end)
        filter (where movimentacao.mes_competencia = date '2026-08-01') = 1877.27
      and sum(case when movimentacao.natureza = 'receita' then -movimentacao.valor else movimentacao.valor end)
        filter (where movimentacao.mes_competencia = date '2026-09-01') = 784.08
      and sum(case when movimentacao.natureza = 'receita' then -movimentacao.valor else movimentacao.valor end)
        filter (where movimentacao.mes_competencia = date '2026-10-01') = 711.64
      and sum(case when movimentacao.natureza = 'receita' then -movimentacao.valor else movimentacao.valor end)
        filter (where movimentacao.mes_competencia = date '2026-11-01') = 511.36
      and sum(case when movimentacao.natureza = 'receita' then -movimentacao.valor else movimentacao.valor end)
        filter (where movimentacao.mes_competencia = date '2026-12-01') = 421.33
      and sum(case when movimentacao.natureza = 'receita' then -movimentacao.valor else movimentacao.valor end)
        filter (where movimentacao.mes_competencia = date '2027-01-01') = 335.08
      and sum(case when movimentacao.natureza = 'receita' then -movimentacao.valor else movimentacao.valor end)
        filter (where movimentacao.mes_competencia = date '2027-02-01') = 220.08
  ), movimentacoes_atualizadas as (
    update public.movimentacoes as movimentacao
    set mes_competencia = (movimentacao.mes_competencia - interval '1 month')::date
    from cartoes_alvo as cartao
    where movimentacao.usuario_id = cartao.usuario_id
      and movimentacao.conta_id = cartao.conta_id
      and movimentacao.status <> 'cancelada'
      and movimentacao.mes_competencia >= date '2026-08-01'
      and movimentacao.mes_competencia < date '2027-03-01'
    returning movimentacao.id
  )
  select count(*) into movimentacoes_alteradas from movimentacoes_atualizadas;

  if movimentacoes_alteradas = 0 then
    raise exception 'A fatura informada do Cartao Itau Uniclass nao foi encontrada; nenhuma parcela foi movida.';
  end if;
end;
$$;

alter table public.cartoes_credito
  drop column if exists usar_mes_anterior_no_panorama;

commit;
