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

-- Reutiliza a entrada ja registrada no extrato Itau. O Inter registra a
-- saida em 01/03 e o Itau registra a entrada no proximo dia util, 02/03.
update public.movimentacoes
set conta_id = (md5('financas:conta:extrato-inter:filipe'))::uuid,
    observacoes = concat_ws(' ', observacoes, 'Contrapartida no Banco Inter em 01/03/2026.'),
    metadados = metadados || jsonb_build_object(
      'contrapartida_inter', jsonb_build_object(
        'arquivo', 'Extrato-01-01-2026-a-22-07-2026-PDF.pdf',
        'arquivo_sha256', 'b8eafb6c75d52185c4de372391d492a0b4ad61963479278ab44633e373fa6818',
        'pagina', 3, 'data_movimentacao', '2026-03-01', 'periodo_extrato', '2026-03',
        'descricao_original', 'Pix enviado - Filipe Boddenberg Ribeiro'
      )
    )
where id = 'f5fc1e09-d588-58d2-a18c-4f2693e6cc61'::uuid
  and usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
  and conta_id = 'bbe5ac59-d57f-5149-842e-e4163f9bd0e2'::uuid
  and conta_destino_id = 'd64bb1b6-1140-5470-8695-7aadce45262c'::uuid
  and valor = 1346.76;

with dados (
  chave, data_movimentacao, natureza, descricao, valor, forma_pagamento,
  tipo_lancamento, descricao_original, pagina_pdf
) as (
  values
    ('M01', '2026-03-01'::date, 'despesa', 'Auto Posto Carlu', 54.87, 'debito', 'compra_debito', 'Compra no debito - AUTO POSTO CARLU', 3),
    ('M02', '2026-03-06'::date, 'receita', 'Booking.com', 2056.68, 'transferencia', 'transferencia_recebida', 'Transferencia recebida - BOOKING.COM BRASIL SERVICOS DE RESERVA', 3),
    ('M03', '2026-03-06'::date, 'receita', 'Booking.com', 1555.56, 'transferencia', 'transferencia_recebida', 'Transferencia recebida - BOOKING.COM BRASIL SERVICOS DE RESERVA', 3),
    ('M04', '2026-03-14'::date, 'receita', 'Credito Banco Inter', 181.30, 'pix', 'pix_recebido', 'Pix recebido - 00019 260761478 BANCO INTER SA', 3),
    ('M05', '2026-03-20'::date, 'despesa', 'Smart Fit', 149.90, 'debito', 'compra_debito', 'Compra no debito - SMARTFIT ESCOLA DE GI', 4),
    ('M06', '2026-03-25'::date, 'receita', 'Credito Banco Inter', 381.79, 'pix', 'pix_recebido', 'Pix recebido - 00019 260762768 BANCO INTER SA', 4),
    ('M07', '2026-03-26'::date, 'despesa', 'Pix - Jurene Boddenberg', 4025.00, 'pix', 'pix_enviado', 'Pix enviado - Jurene Boddenberg', 4),
    ('M08', '2026-03-31'::date, 'receita', 'Credito Banco Inter', 106.91, 'pix', 'pix_recebido', 'Pix recebido - 00019 260762326 BANCO INTER SA', 4)
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
  '2026-03-01'::date, 'confirmada', dados.forma_pagamento, 'extrato',
  dados.descricao_original || ' - valor no extrato R$ ' ||
    case when dados.natureza = 'receita' then '' else '-' end ||
    to_char(dados.valor, 'FM999999990.00') || '. Extrato Banco Inter de 2026-03.',
  jsonb_build_object(
    'instituicao', 'Banco Inter', 'tipo_documento', 'extrato_conta',
    'agencia', '0001-9', 'conta_extrato', '15070262-0',
    'tipo_lancamento', dados.tipo_lancamento,
    'descricao_original', dados.descricao_original,
    'valor_assinado', case when dados.natureza = 'receita'
      then to_char(dados.valor, 'FM999999990.00')
      else '-' || to_char(dados.valor, 'FM999999990.00') end,
    'saldo_inicial_periodo', '1401.63', 'saldo_final_periodo', '107.34',
    'periodo_extrato', '2026-03',
    'arquivo_origem', 'Extrato-01-01-2026-a-22-07-2026-PDF.pdf',
    'arquivo_sha256', 'b8eafb6c75d52185c4de372391d492a0b4ad61963479278ab44633e373fa6818',
    'pagina_pdf', dados.pagina_pdf, 'ordem_pdf', dados.chave,
    'importacao_lote', 'inter-filipe-2026-03', 'projetada_pela_ia', false
  ),
  true
from dados
on conflict (id) do nothing;

do $$
declare
  quantidade_novos integer;
  entradas numeric;
  saidas numeric;
begin
  select count(*) into quantidade_novos
  from public.movimentacoes
  where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
    and metadados ->> 'importacao_lote' = 'inter-filipe-2026-03';

  if quantidade_novos <> 8 then
    raise exception 'Extrato Inter de marco incompleto: esperados 8 novos registros, encontrados %.', quantidade_novos;
  end if;

  if not exists (
    select 1 from public.movimentacoes
    where id = 'f5fc1e09-d588-58d2-a18c-4f2693e6cc61'::uuid
      and conta_id = (md5('financas:conta:extrato-inter:filipe'))::uuid
      and conta_destino_id = 'd64bb1b6-1140-5470-8695-7aadce45262c'::uuid
      and metadados -> 'contrapartida_inter' ->> 'periodo_extrato' = '2026-03'
  ) then
    raise exception 'Contrapartida Inter de marco nao foi conciliada.';
  end if;

  with movimentos as (
    select * from public.movimentacoes
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and (
        metadados ->> 'importacao_lote' = 'inter-filipe-2026-03'
        or id = 'f5fc1e09-d588-58d2-a18c-4f2693e6cc61'::uuid
      )
  )
  select
    sum(case when natureza = 'receita' and conta_id = (md5('financas:conta:extrato-inter:filipe'))::uuid then valor
             when natureza = 'transferencia' and conta_destino_id = (md5('financas:conta:extrato-inter:filipe'))::uuid then valor else 0 end),
    sum(case when natureza = 'despesa' and conta_id = (md5('financas:conta:extrato-inter:filipe'))::uuid then valor
             when natureza = 'transferencia' and conta_id = (md5('financas:conta:extrato-inter:filipe'))::uuid then valor else 0 end)
  into entradas, saidas from movimentos;

  if entradas <> 4282.24 or saidas <> 5576.53 or 1401.63 + entradas - saidas <> 107.34 then
    raise exception 'Totais ou saldo do Inter de marco nao conferem.';
  end if;

  if exists (
    select 1 from public.movimentacoes
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and metadados ->> 'importacao_lote' = 'inter-filipe-2026-03'
      and mes_competencia <> '2026-03-01'::date
  ) then
    raise exception 'O extrato Inter de marco alterou outro mes.';
  end if;
end;
$$;

commit;
