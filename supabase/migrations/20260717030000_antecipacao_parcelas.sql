begin;

-- Antecipacao de parcelas: quanto custa quitar hoje cada parcela futura.
-- No consignado (Price) o proprio banco informa o valor presente de cada
-- parcela; antecipar as ultimas sai muito mais barato que o valor mensal.
-- No financiamento habitacional (SAC) a antecipacao corresponde a amortizacao
-- extraordinaria do principal daquela parcela.
alter table public.parcelas_divida
  add column if not exists valor_antecipacao numeric(14, 2)
    check (valor_antecipacao is null or valor_antecipacao >= 0),
  add column if not exists saldo_devedor_apos numeric(14, 2)
    check (saldo_devedor_apos is null or saldo_devedor_apos >= 0),
  add column if not exists metadados jsonb not null default '{}'::jsonb;

comment on column public.parcelas_divida.valor_antecipacao is
  'Custo para quitar hoje somente esta parcela. No Price e o valor presente '
  'informado pelo banco; no SAC e a amortizacao do principal. Menor que o valor '
  'da parcela pela economia de juros.';
comment on column public.parcelas_divida.saldo_devedor_apos is
  'Saldo devedor do contrato imediatamente apos esta parcela, quitando na ordem '
  'cronologica.';
comment on column public.parcelas_divida.metadados is
  'Detalhes da parcela no contrato original (numero real, seguros, situacao, '
  'sistema de amortizacao).';

commit;
