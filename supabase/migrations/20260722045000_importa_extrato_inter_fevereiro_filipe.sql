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

-- Reutiliza as duas transferencias ja registradas no extrato Itau.
update public.movimentacoes
set conta_destino_id = (md5('financas:conta:extrato-inter:filipe'))::uuid,
    observacoes = concat_ws(' ', observacoes, 'Contrapartida no Banco Inter em 02/02/2026.'),
    metadados = metadados || jsonb_build_object(
      'contrapartida_inter', jsonb_build_object(
        'arquivo', 'Extrato-01-01-2026-a-22-07-2026-PDF.pdf',
        'arquivo_sha256', 'b8eafb6c75d52185c4de372391d492a0b4ad61963479278ab44633e373fa6818',
        'pagina', 2, 'data_movimentacao', '2026-02-02', 'periodo_extrato', '2026-02',
        'descricao_original', 'Pix recebido - FILIPE BODDENBERG RIBEIRO'
      )
    )
where id = '43ffb28a-7f82-5611-8991-701492f4ac68'::uuid
  and usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
  and conta_id = 'd64bb1b6-1140-5470-8695-7aadce45262c'::uuid
  and conta_destino_id = 'bbe5ac59-d57f-5149-842e-e4163f9bd0e2'::uuid
  and valor = 5560.00;

update public.movimentacoes
set conta_id = (md5('financas:conta:extrato-inter:filipe'))::uuid,
    observacoes = concat_ws(' ', observacoes, 'Contrapartida no Banco Inter em 06/02/2026.'),
    metadados = metadados || jsonb_build_object(
      'contrapartida_inter', jsonb_build_object(
        'arquivo', 'Extrato-01-01-2026-a-22-07-2026-PDF.pdf',
        'arquivo_sha256', 'b8eafb6c75d52185c4de372391d492a0b4ad61963479278ab44633e373fa6818',
        'pagina', 2, 'data_movimentacao', '2026-02-06', 'periodo_extrato', '2026-02',
        'descricao_original', 'Pix enviado - Filipe Boddenberg Ribeiro'
      )
    )
where id = '049db490-9137-5a11-9f3a-34f74642e553'::uuid
  and usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
  and conta_id = 'bbe5ac59-d57f-5149-842e-e4163f9bd0e2'::uuid
  and conta_destino_id = 'd64bb1b6-1140-5470-8695-7aadce45262c'::uuid
  and valor = 3000.00;

with dados (
  chave, data_movimentacao, natureza, descricao, valor, forma_pagamento,
  tipo_lancamento, descricao_original, pagina_pdf
) as (
  values
    ('F01', '2026-02-02'::date, 'despesa', 'Pix - Celio Ribeiro Boucas', 1100.00, 'pix', 'pix_enviado', 'Pix enviado - Celio Ribeiro Boucas', 2),
    ('F02', '2026-02-02'::date, 'despesa', 'Pix - Thiago Boddenberg Ribeiro', 1100.00, 'pix', 'pix_enviado', 'Pix enviado - Thiago Boddenberg Ribeiro', 2),
    ('F03', '2026-02-02'::date, 'despesa', 'Pix - Jurene Boddenberg', 1100.00, 'pix', 'pix_enviado', 'Pix enviado - Jurene Boddenberg', 2),
    ('F04', '2026-02-02'::date, 'despesa', 'Pix - Jurene Boddenberg', 2149.00, 'pix', 'pix_enviado', 'Pix enviado - Jurene Boddenberg', 2),
    ('F05', '2026-02-06'::date, 'receita', 'Booking.com', 2349.51, 'transferencia', 'transferencia_recebida', 'Transferencia recebida - BOOKING.COM BRASIL SERVICOS DE RESERVA', 2),
    ('F06', '2026-02-06'::date, 'receita', 'Booking.com', 548.10, 'transferencia', 'transferencia_recebida', 'Transferencia recebida - BOOKING.COM BRASIL SERVICOS DE RESERVA', 2),
    ('F07', '2026-02-18'::date, 'receita', 'Credito Banco Inter', 629.96, 'pix', 'pix_recebido', 'Pix recebido - 00019 260761478 BANCO INTER SA', 3),
    ('F08', '2026-02-19'::date, 'despesa', 'A Pizza da Mooca', 120.00, 'debito', 'compra_debito', 'Compra no debito - A PIZZA DA MOOCA', 3),
    ('F09', '2026-02-19'::date, 'despesa', 'Hirota', 16.98, 'debito', 'compra_debito', 'Compra no debito - HIROTA OFFICE CEIC ITA', 3),
    ('F10', '2026-02-19'::date, 'despesa', 'Hirota', 16.98, 'debito', 'compra_debito', 'Compra no debito - HIROTA OFFICE CEIC ITA', 3),
    ('F11', '2026-02-20'::date, 'despesa', 'MBT Comercio de Alimentos', 74.39, 'debito', 'compra_debito', 'Compra no debito - IFD*MBT COMERCIO DE AL', 3),
    ('F12', '2026-02-20'::date, 'despesa', 'Hirota', 10.78, 'debito', 'compra_debito', 'Compra no debito - HIROTA OFFICE CEIC ITA', 3),
    ('F13', '2026-02-21'::date, 'despesa', 'Smart Fit', 149.90, 'debito', 'compra_debito', 'Compra no debito - SMARTFIT ESCOLA DE GI', 3),
    ('F14', '2026-02-21'::date, 'despesa', 'JF Comercio de Frutas', 110.00, 'debito', 'compra_debito', 'Compra no debito - JF COMERCIO DE FRUTAS', 3),
    ('F15', '2026-02-23'::date, 'despesa', 'Paulo Henrique', 110.00, 'debito', 'compra_debito', 'Compra no debito - PauloHenrique', 3),
    ('F16', '2026-02-23'::date, 'receita', 'Credito Banco Inter', 1450.79, 'pix', 'pix_recebido', 'Pix recebido - 00019 260762547 BANCO INTER SA', 3),
    ('F17', '2026-02-26'::date, 'despesa', 'Verum Gastronomia', 62.00, 'debito', 'compra_debito', 'Compra no debito - VERUM GASTRONOMIA', 3),
    ('F18', '2026-02-26'::date, 'despesa', 'Hirota', 34.74, 'debito', 'compra_debito', 'Compra no debito - HIROTA OFFICE CEIC ITA', 3),
    ('F19', '2026-02-28'::date, 'despesa', 'Diego de Jesus Brito', 24.00, 'debito', 'compra_debito', 'Compra no debito - DiegoDeJesusBrito', 3)
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
  '2026-02-01'::date, 'confirmada', dados.forma_pagamento, 'extrato',
  dados.descricao_original || ' - valor no extrato R$ ' ||
    case when dados.natureza = 'receita' then '' else '-' end ||
    to_char(dados.valor, 'FM999999990.00') || '. Extrato Banco Inter de 2026-02.',
  jsonb_build_object(
    'instituicao', 'Banco Inter', 'tipo_documento', 'extrato_conta',
    'agencia', '0001-9', 'conta_extrato', '15070262-0',
    'tipo_lancamento', dados.tipo_lancamento,
    'descricao_original', dados.descricao_original,
    'valor_assinado', case when dados.natureza = 'receita'
      then to_char(dados.valor, 'FM999999990.00')
      else '-' || to_char(dados.valor, 'FM999999990.00') end,
    'saldo_inicial_periodo', '42.04', 'saldo_final_periodo', '1401.63',
    'periodo_extrato', '2026-02',
    'arquivo_origem', 'Extrato-01-01-2026-a-22-07-2026-PDF.pdf',
    'arquivo_sha256', 'b8eafb6c75d52185c4de372391d492a0b4ad61963479278ab44633e373fa6818',
    'pagina_pdf', dados.pagina_pdf, 'ordem_pdf', dados.chave,
    'importacao_lote', 'inter-filipe-2026-02', 'projetada_pela_ia', false
  ),
  true
from dados
on conflict (id) do nothing;

do $$
declare
  quantidade_novos integer;
  quantidade_contrapartidas integer;
  entradas numeric;
  saidas numeric;
begin
  select count(*) into quantidade_novos
  from public.movimentacoes
  where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
    and metadados ->> 'importacao_lote' = 'inter-filipe-2026-02';

  if quantidade_novos <> 19 then
    raise exception 'Extrato Inter de fevereiro incompleto: esperados 19 novos registros, encontrados %.', quantidade_novos;
  end if;

  select count(*) into quantidade_contrapartidas
  from public.movimentacoes
  where id in (
      '43ffb28a-7f82-5611-8991-701492f4ac68'::uuid,
      '049db490-9137-5a11-9f3a-34f74642e553'::uuid
    )
    and metadados -> 'contrapartida_inter' ->> 'periodo_extrato' = '2026-02';

  if quantidade_contrapartidas <> 2 then
    raise exception 'Contrapartidas Inter de fevereiro incorretas: esperadas 2, encontradas %.', quantidade_contrapartidas;
  end if;

  with movimentos as (
    select * from public.movimentacoes
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and (
        metadados ->> 'importacao_lote' = 'inter-filipe-2026-02'
        or id in (
          '43ffb28a-7f82-5611-8991-701492f4ac68'::uuid,
          '049db490-9137-5a11-9f3a-34f74642e553'::uuid
        )
      )
  )
  select
    sum(case when natureza = 'receita' and conta_id = (md5('financas:conta:extrato-inter:filipe'))::uuid then valor
             when natureza = 'transferencia' and conta_destino_id = (md5('financas:conta:extrato-inter:filipe'))::uuid then valor else 0 end),
    sum(case when natureza = 'despesa' and conta_id = (md5('financas:conta:extrato-inter:filipe'))::uuid then valor
             when natureza = 'transferencia' and conta_id = (md5('financas:conta:extrato-inter:filipe'))::uuid then valor else 0 end)
  into entradas, saidas from movimentos;

  if entradas <> 10538.36 or saidas <> 9178.77 or 42.04 + entradas - saidas <> 1401.63 then
    raise exception 'Totais ou saldo do Inter de fevereiro nao conferem.';
  end if;

  if exists (
    select 1 from public.movimentacoes
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and metadados ->> 'importacao_lote' = 'inter-filipe-2026-02'
      and mes_competencia <> '2026-02-01'::date
  ) then
    raise exception 'O extrato Inter de fevereiro alterou outro mes.';
  end if;
end;
$$;

commit;
