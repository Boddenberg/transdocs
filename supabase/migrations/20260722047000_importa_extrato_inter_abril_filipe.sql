begin;

do $$
begin
  if not exists (
    select 1 from public.perfis
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and lower(coalesce(nome, '')) like '%filipe%'
  ) then
    raise exception 'Perfil do Filipe nao encontrado; importacao Inter cancelada.';
  end if;

  if not exists (
    select 1 from public.contas
    where id = (md5('financas:conta:extrato-inter:filipe'))::uuid
      and usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and nome = 'Extrato Inter'
  ) then
    raise exception 'Conta Extrato Inter nao encontrada.';
  end if;
end;
$$;

with dados (
  chave, data_movimentacao, natureza, descricao, valor, forma_pagamento,
  tipo_lancamento, descricao_original, pagina_pdf
) as (
  values
    ('A01', '2026-04-07'::date, 'receita', 'Booking.com', 1148.40, 'transferencia', 'transferencia_recebida', 'Transferencia recebida - BOOKING.COM BRASIL SERVICOS DE RESERVA', 4),
    ('A02', '2026-04-07'::date, 'receita', 'Booking.com', 2037.74, 'pix', 'pix_recebido', 'Pix recebido - BOOKING COM BRASIL SERVICOS DE RESERVA DE HOTEIS LTDA', 4),
    ('A03', '2026-04-19'::date, 'receita', 'Credito Banco Inter', 286.33, 'pix', 'pix_recebido', 'Pix recebido - 00019 260762547 BANCO INTER SA', 4),
    ('A04', '2026-04-20'::date, 'despesa', 'Smart Fit', 149.90, 'debito', 'compra_debito', 'Compra no debito - SMARTFIT ESCOLA DE GI', 4),
    ('A05', '2026-04-26'::date, 'receita', 'Credito Banco Inter', 295.89, 'pix', 'pix_recebido', 'Pix recebido - 00019 260761486 BANCO INTER SA', 4)
)
insert into public.movimentacoes (
  id, usuario_id, conta_id, conta_destino_id, categoria_id, natureza,
  descricao, valor, data_movimentacao, mes_competencia, status,
  forma_pagamento, origem, observacoes, metadados, confirmado_por_usuario
)
select
  (md5('financas:mov:inter:filipe:' || dados.chave))::uuid,
  'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid,
  (md5('financas:conta:extrato-inter:filipe'))::uuid,
  null::uuid,
  (md5('financas:categoria:extrato-inter:filipe'))::uuid,
  dados.natureza, dados.descricao, dados.valor, dados.data_movimentacao,
  '2026-04-01'::date, 'confirmada', dados.forma_pagamento, 'extrato',
  dados.descricao_original || ' - valor no extrato R$ ' ||
    case when dados.natureza = 'receita' then '' else '-' end ||
    to_char(dados.valor, 'FM999999990.00') || '. Extrato Banco Inter de 2026-04.',
  jsonb_build_object(
    'instituicao', 'Banco Inter', 'tipo_documento', 'extrato_conta',
    'agencia', '0001-9', 'conta_extrato', '15070262-0',
    'tipo_lancamento', dados.tipo_lancamento,
    'descricao_original', dados.descricao_original,
    'valor_assinado', case when dados.natureza = 'receita'
      then to_char(dados.valor, 'FM999999990.00')
      else '-' || to_char(dados.valor, 'FM999999990.00') end,
    'saldo_inicial_periodo', '107.34', 'saldo_final_periodo', '3725.80',
    'periodo_extrato', '2026-04',
    'arquivo_origem', 'Extrato-01-01-2026-a-22-07-2026-PDF.pdf',
    'arquivo_sha256', 'b8eafb6c75d52185c4de372391d492a0b4ad61963479278ab44633e373fa6818',
    'pagina_pdf', dados.pagina_pdf, 'ordem_pdf', dados.chave,
    'importacao_lote', 'inter-filipe-2026-04', 'projetada_pela_ia', false
  ),
  true
from dados
on conflict (id) do nothing;

do $$
declare
  quantidade integer;
  entradas numeric;
  saidas numeric;
begin
  select count(*),
    sum(valor) filter (where natureza = 'receita'),
    sum(valor) filter (where natureza = 'despesa')
  into quantidade, entradas, saidas
  from public.movimentacoes
  where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
    and metadados ->> 'importacao_lote' = 'inter-filipe-2026-04';

  if quantidade <> 5 then
    raise exception 'Extrato Inter de abril incompleto: esperados 5 registros, encontrados %.', quantidade;
  end if;

  if entradas <> 3768.36 or saidas <> 149.90 or 107.34 + entradas - saidas <> 3725.80 then
    raise exception 'Totais ou saldo do Inter de abril nao conferem.';
  end if;

  if exists (
    select 1 from public.movimentacoes
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and metadados ->> 'importacao_lote' = 'inter-filipe-2026-04'
      and mes_competencia <> '2026-04-01'::date
  ) then
    raise exception 'O extrato Inter de abril alterou outro mes.';
  end if;
end;
$$;

commit;
