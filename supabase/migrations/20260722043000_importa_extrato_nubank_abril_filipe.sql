begin;

do $$
begin
  if not exists (
    select 1 from public.perfis
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and lower(coalesce(nome, '')) like '%filipe%'
  ) then
    raise exception 'Perfil do Filipe nao encontrado; importacao Nubank cancelada.';
  end if;

  if not exists (
    select 1 from public.contas
    where id = (md5('financas:conta:extrato-nubank:filipe'))::uuid
      and usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and nome = 'Extrato Nubank'
  ) then
    raise exception 'Conta Extrato Nubank nao encontrada.';
  end if;
end;
$$;

with dados (
  chave, data_movimentacao, natureza, descricao, valor, forma_pagamento,
  tipo_lancamento, descricao_original, pagina_pdf, incluido_total_entradas
) as (
  values
    ('01', '2026-04-07'::date, 'receita', 'Booking.com', 2904.17, 'transferencia', 'transferencia_recebida', 'Transferencia Recebida - BOOKING.COM BRASIL SERVICOS DE RESERVA DE HOTEIS', 1, true),
    ('02', '2026-04-24'::date, 'despesa', 'Spotify', 31.90, 'debito', 'compra_debito', 'Compra no debito - EBN*SPOTIFY', 1, false),
    ('03', '2026-04-30'::date, 'receita', 'Rendimento liquido', 0.04, null, 'rendimento_liquido_resumo', 'Rendimento liquido do periodo', 1, false)
)
insert into public.movimentacoes (
  id, usuario_id, conta_id, conta_destino_id, categoria_id, natureza,
  descricao, valor, data_movimentacao, mes_competencia, status,
  forma_pagamento, origem, observacoes, metadados, confirmado_por_usuario
)
select
  (md5('financas:mov:nubank:filipe:2026-04:' || dados.chave))::uuid,
  'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid,
  (md5('financas:conta:extrato-nubank:filipe'))::uuid,
  null::uuid,
  (md5('financas:categoria:extrato-nubank:filipe'))::uuid,
  dados.natureza, dados.descricao, dados.valor, dados.data_movimentacao,
  '2026-04-01'::date, 'confirmada', dados.forma_pagamento, 'extrato',
  dados.descricao_original || ' - valor no extrato R$ ' ||
    case when dados.natureza = 'receita' then '' else '-' end ||
    to_char(dados.valor, 'FM999999990.00') || '. Extrato Nubank de 2026-04.',
  jsonb_build_object(
    'instituicao', 'Nubank', 'tipo_documento', 'extrato_conta',
    'agencia', '0001', 'conta_extrato', '17483930-2',
    'tipo_lancamento', dados.tipo_lancamento,
    'descricao_original', dados.descricao_original,
    'valor_assinado', case when dados.natureza = 'receita'
      then to_char(dados.valor, 'FM999999990.00')
      else '-' || to_char(dados.valor, 'FM999999990.00') end,
    'incluido_total_entradas', dados.incluido_total_entradas,
    'saldo_inicial_periodo', '2.69', 'saldo_final_periodo', '2875.00',
    'rendimento_liquido_periodo', '0.04', 'periodo_extrato', '2026-04',
    'arquivo_origem', 'NU_174839302_01ABR2026_30ABR2026.pdf',
    'arquivo_sha256', 'df83f080c4ade22898ecff7b04a5392aa3024376b5581bcc266f84d0e4a46d1b',
    'pagina_pdf', dados.pagina_pdf, 'ordem_pdf', dados.chave::integer,
    'importacao_lote', 'nubank-filipe-2026-04', 'projetada_pela_ia', false
  ),
  true
from dados
on conflict (id) do nothing;

do $$
declare
  quantidade integer;
  entradas_movimentacoes numeric;
  rendimento numeric;
  saidas numeric;
begin
  select count(*),
    sum(valor) filter (where natureza = 'receita' and coalesce((metadados ->> 'incluido_total_entradas')::boolean, false)),
    sum(valor) filter (where metadados ->> 'tipo_lancamento' = 'rendimento_liquido_resumo'),
    sum(valor) filter (where natureza = 'despesa')
  into quantidade, entradas_movimentacoes, rendimento, saidas
  from public.movimentacoes
  where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
    and metadados ->> 'importacao_lote' = 'nubank-filipe-2026-04';

  if quantidade <> 3 then
    raise exception 'Extrato Nubank de abril incompleto: esperados 3 registros, encontrados %.', quantidade;
  end if;

  if entradas_movimentacoes <> 2904.17 or rendimento <> 0.04 or saidas <> 31.90
     or 2.69 + entradas_movimentacoes + rendimento - saidas <> 2875.00 then
    raise exception 'Totais, rendimento ou saldo do Nubank de abril nao conferem.';
  end if;

  if exists (
    select 1 from public.movimentacoes
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and metadados ->> 'importacao_lote' = 'nubank-filipe-2026-04'
      and mes_competencia <> '2026-04-01'::date
  ) then
    raise exception 'O extrato Nubank de abril alterou outro mes.';
  end if;
end;
$$;

commit;
