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
    ('01', '2026-03-04'::date, 'despesa', 'Diego de Jesus Brito', 16.00, 'debito', 'compra_debito', 'Compra no debito - DiegoDeJesusBrito', 1, false),
    ('02', '2026-03-05'::date, 'despesa', 'Pix - Gustavo Kin Tanaka Uno', 9.00, 'pix', 'transferencia_pix_enviada', 'Transferencia enviada pelo Pix - Gustavo Kin Tanaka Uno', 1, false),
    ('03', '2026-03-06'::date, 'receita', 'Booking.com', 1114.02, 'transferencia', 'transferencia_recebida', 'Transferencia Recebida - BOOKING.COM BRASIL SERVICOS DE RESERVA DE HOTEIS', 1, true),
    ('04', '2026-03-24'::date, 'despesa', 'Spotify', 31.90, 'debito', 'compra_debito', 'Compra no debito - EBN*SPOTIFY', 1, false),
    ('05', '2026-03-26'::date, 'despesa', 'Pix - Jurene Boddenberg', 1080.00, 'pix', 'transferencia_pix_enviada', 'Transferencia enviada pelo Pix - Jurene Boddenberg', 1, false),
    ('06', '2026-03-31'::date, 'receita', 'Rendimento liquido', 0.01, null, 'rendimento_liquido_resumo', 'Rendimento liquido do periodo', 1, false)
)
insert into public.movimentacoes (
  id, usuario_id, conta_id, conta_destino_id, categoria_id, natureza,
  descricao, valor, data_movimentacao, mes_competencia, status,
  forma_pagamento, origem, observacoes, metadados, confirmado_por_usuario
)
select
  (md5('financas:mov:nubank:filipe:2026-03:' || dados.chave))::uuid,
  'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid,
  (md5('financas:conta:extrato-nubank:filipe'))::uuid,
  null::uuid,
  (md5('financas:categoria:extrato-nubank:filipe'))::uuid,
  dados.natureza, dados.descricao, dados.valor, dados.data_movimentacao,
  '2026-03-01'::date, 'confirmada', dados.forma_pagamento, 'extrato',
  dados.descricao_original || ' - valor no extrato R$ ' ||
    case when dados.natureza = 'receita' then '' else '-' end ||
    to_char(dados.valor, 'FM999999990.00') || '. Extrato Nubank de 2026-03.',
  jsonb_build_object(
    'instituicao', 'Nubank', 'tipo_documento', 'extrato_conta',
    'agencia', '0001', 'conta_extrato', '17483930-2',
    'tipo_lancamento', dados.tipo_lancamento,
    'descricao_original', dados.descricao_original,
    'valor_assinado', case when dados.natureza = 'receita'
      then to_char(dados.valor, 'FM999999990.00')
      else '-' || to_char(dados.valor, 'FM999999990.00') end,
    'incluido_total_entradas', dados.incluido_total_entradas,
    'saldo_inicial_periodo', '25.56', 'saldo_final_periodo', '2.69',
    'rendimento_liquido_periodo', '0.01', 'periodo_extrato', '2026-03',
    'arquivo_origem', 'NU_174839302_01MAR2026_31MAR2026.pdf',
    'arquivo_sha256', '104e40b10b7790067ab0468cfabbcdf7f854af4ff41dcd5862e0363c721cf90c',
    'pagina_pdf', dados.pagina_pdf, 'ordem_pdf', dados.chave::integer,
    'importacao_lote', 'nubank-filipe-2026-03', 'projetada_pela_ia', false
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
    and metadados ->> 'importacao_lote' = 'nubank-filipe-2026-03';

  if quantidade <> 6 then
    raise exception 'Extrato Nubank de marco incompleto: esperados 6 registros, encontrados %.', quantidade;
  end if;

  if entradas_movimentacoes <> 1114.02 or rendimento <> 0.01 or saidas <> 1136.90
     or 25.56 + entradas_movimentacoes + rendimento - saidas <> 2.69 then
    raise exception 'Totais, rendimento ou saldo do Nubank de marco nao conferem.';
  end if;

  if exists (
    select 1 from public.movimentacoes
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and metadados ->> 'importacao_lote' = 'nubank-filipe-2026-03'
      and mes_competencia <> '2026-03-01'::date
  ) then
    raise exception 'O extrato Nubank de marco alterou outro mes.';
  end if;
end;
$$;

commit;
