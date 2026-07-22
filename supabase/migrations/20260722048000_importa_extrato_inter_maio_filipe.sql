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

-- As duas transferencias Inter -> Nubank ja foram criadas ao importar o
-- extrato Nubank de maio; apenas adiciona aqui a contrapartida documental.
update public.movimentacoes
set observacoes = concat_ws(' ', observacoes, 'Contrapartida no Banco Inter em 01/05/2026.'),
    metadados = metadados || jsonb_build_object(
      'contrapartida_inter', jsonb_build_object(
        'arquivo', 'Extrato-01-01-2026-a-22-07-2026-PDF.pdf',
        'arquivo_sha256', 'b8eafb6c75d52185c4de372391d492a0b4ad61963479278ab44633e373fa6818',
        'pagina', 4, 'data_movimentacao', '2026-05-01', 'periodo_extrato', '2026-05',
        'descricao_original', 'Pix enviado - Filipe Boddenberg Ribeiro'
      )
    )
where id = (md5('financas:mov:nubank:filipe:2026-05:01'))::uuid
  and usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
  and conta_id = (md5('financas:conta:extrato-inter:filipe'))::uuid
  and conta_destino_id = (md5('financas:conta:extrato-nubank:filipe'))::uuid
  and valor = 660.00
  and not (metadados ? 'contrapartida_inter');

update public.movimentacoes
set observacoes = concat_ws(' ', observacoes, 'Contrapartida no Banco Inter em 10/05/2026.'),
    metadados = metadados || jsonb_build_object(
      'contrapartida_inter', jsonb_build_object(
        'arquivo', 'Extrato-01-01-2026-a-22-07-2026-PDF.pdf',
        'arquivo_sha256', 'b8eafb6c75d52185c4de372391d492a0b4ad61963479278ab44633e373fa6818',
        'pagina', 5, 'data_movimentacao', '2026-05-10', 'periodo_extrato', '2026-05',
        'descricao_original', 'Pix enviado - Filipe Boddenberg Ribeiro'
      )
    )
where id = (md5('financas:mov:nubank:filipe:2026-05:08'))::uuid
  and usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
  and conta_id = (md5('financas:conta:extrato-inter:filipe'))::uuid
  and conta_destino_id = (md5('financas:conta:extrato-nubank:filipe'))::uuid
  and valor = 500.00
  and not (metadados ? 'contrapartida_inter');

with dados (
  chave, data_movimentacao, natureza, descricao, valor, forma_pagamento,
  tipo_lancamento, descricao_original, pagina_pdf
) as (
  values
    ('Y01', '2026-05-01'::date, 'despesa', 'Pix - Celio Ribeiro Boucas', 660.00, 'pix', 'pix_enviado', 'Pix enviado - Celio Ribeiro Boucas', 4),
    ('Y02', '2026-05-01'::date, 'despesa', 'Pix - Jurene Boddenberg', 660.00, 'pix', 'pix_enviado', 'Pix enviado - Jurene Boddenberg', 4),
    ('Y03', '2026-05-01'::date, 'despesa', 'Pix - Jurene Boddenberg', 1743.00, 'pix', 'pix_enviado', 'Pix enviado - Jurene Boddenberg', 4),
    ('Y04', '2026-05-02'::date, 'receita', 'Credito Banco Inter', 897.20, 'pix', 'pix_recebido', 'Pix recebido - 00019 260761478 BANCO INTER SA', 4),
    ('Y05', '2026-05-03'::date, 'receita', 'Credito Banco Inter', 133.61, 'pix', 'pix_recebido', 'Pix recebido - 00019 260762520 BANCO INTER SA', 4),
    ('Y06', '2026-05-04'::date, 'receita', 'Booking.com', 1161.45, 'transferencia', 'transferencia_recebida', 'Transferencia recebida - BOOKING.COM BRASIL SERVICOS DE RESERVA', 4),
    ('Y07', '2026-05-04'::date, 'receita', 'Booking.com', 3033.85, 'transferencia', 'transferencia_recebida', 'Transferencia recebida - BOOKING.COM BRASIL SERVICOS DE RESERVA', 4),
    ('Y08', '2026-05-05'::date, 'receita', 'Credito Banco Inter', 1278.98, 'pix', 'pix_recebido', 'Pix recebido - 00019 260761818 BANCO INTER SA', 5),
    ('Y09', '2026-05-15'::date, 'despesa', 'Factory Games', 300.00, 'pix', 'pix_enviado', 'Pix enviado - FACTORY GAMES LTDA', 5),
    ('Y10', '2026-05-15'::date, 'despesa', 'Factory Games', 50.00, 'pix', 'pix_enviado', 'Pix enviado - FACTORY GAMES LTDA', 5),
    ('Y11', '2026-05-15'::date, 'despesa', 'Factory Games', 50.00, 'pix', 'pix_enviado', 'Pix enviado - FACTORY GAMES LTDA', 5),
    ('Y12', '2026-05-20'::date, 'despesa', 'Dracoins', 94.00, 'pix', 'pix_enviado', 'Pix enviado - DRACOINS', 5),
    ('Y13', '2026-05-20'::date, 'despesa', 'Dracoins', 94.00, 'pix', 'pix_enviado', 'Pix enviado - DRACOINS', 5),
    ('Y14', '2026-05-20'::date, 'despesa', 'Smart Fit', 149.90, 'debito', 'compra_debito', 'Compra no debito - SMARTFIT ESCOLA DE GI', 5),
    ('Y15', '2026-05-21'::date, 'receita', 'Credito Banco Inter', 295.89, 'pix', 'pix_recebido', 'Pix recebido - 00019 260762326 BANCO INTER SA', 5),
    ('Y16', '2026-05-22'::date, 'despesa', 'Pix - Amanda Cassiolato', 54.47, 'pix', 'pix_enviado', 'Pix enviado - AMANDA CASSIOLATO INTERMEDIACAO DE NEGOCIOS LTDA', 5),
    ('Y17', '2026-05-23'::date, 'receita', 'Credito Banco Inter', 362.70, 'pix', 'pix_recebido', 'Pix recebido - 00019 260761451 BANCO INTER SA', 5),
    ('Y18', '2026-05-24'::date, 'despesa', 'Pix - Amanda Cassiolato', 32.68, 'pix', 'pix_enviado', 'Pix enviado - AMANDA CASSIOLATO INTERMEDIACAO DE NEGOCIOS LTDA', 5),
    ('Y19', '2026-05-24'::date, 'receita', 'Credito Banco Inter', 362.70, 'pix', 'pix_recebido', 'Pix recebido - 00019 260762520 BANCO INTER SA', 5),
    ('Y20', '2026-05-29'::date, 'receita', 'Credito Banco Inter', 1202.63, 'pix', 'pix_recebido', 'Pix recebido - 00019 260762326 BANCO INTER SA', 5),
    ('Y21', '2026-05-31'::date, 'despesa', 'Pix - Celio Ribeiro Boucas', 1260.00, 'pix', 'pix_enviado', 'Pix enviado - Celio Ribeiro Boucas', 5),
    ('Y22', '2026-05-31'::date, 'despesa', 'Pix - Jurene Boddenberg', 2148.00, 'pix', 'pix_enviado', 'Pix enviado - Jurene Boddenberg', 5),
    ('Y23', '2026-05-31'::date, 'despesa', 'Pix - Jurene Boddenberg', 3502.00, 'pix', 'pix_enviado', 'Pix enviado - Jurene Boddenberg', 5),
    ('Y24', '2026-05-31'::date, 'despesa', 'Rei dos Coins', 487.51, 'pix', 'pix_enviado', 'Pix enviado - REI DOS COINS', 5)
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
  '2026-05-01'::date, 'confirmada', dados.forma_pagamento, 'extrato',
  dados.descricao_original || ' - valor no extrato R$ ' ||
    case when dados.natureza = 'receita' then '' else '-' end ||
    to_char(dados.valor, 'FM999999990.00') || '. Extrato Banco Inter de 2026-05.',
  jsonb_build_object(
    'instituicao', 'Banco Inter', 'tipo_documento', 'extrato_conta',
    'agencia', '0001-9', 'conta_extrato', '15070262-0',
    'tipo_lancamento', dados.tipo_lancamento,
    'descricao_original', dados.descricao_original,
    'valor_assinado', case when dados.natureza = 'receita'
      then to_char(dados.valor, 'FM999999990.00')
      else '-' || to_char(dados.valor, 'FM999999990.00') end,
    'saldo_inicial_periodo', '3725.80', 'saldo_final_periodo', '9.25',
    'periodo_extrato', '2026-05',
    'arquivo_origem', 'Extrato-01-01-2026-a-22-07-2026-PDF.pdf',
    'arquivo_sha256', 'b8eafb6c75d52185c4de372391d492a0b4ad61963479278ab44633e373fa6818',
    'pagina_pdf', dados.pagina_pdf, 'ordem_pdf', dados.chave,
    'importacao_lote', 'inter-filipe-2026-05', 'projetada_pela_ia', false
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
    and metadados ->> 'importacao_lote' = 'inter-filipe-2026-05';

  if quantidade_novos <> 24 then
    raise exception 'Extrato Inter de maio incompleto: esperados 24 novos registros, encontrados %.', quantidade_novos;
  end if;

  select count(*) into quantidade_contrapartidas
  from public.movimentacoes
  where id in (
      (md5('financas:mov:nubank:filipe:2026-05:01'))::uuid,
      (md5('financas:mov:nubank:filipe:2026-05:08'))::uuid
    )
    and metadados -> 'contrapartida_inter' ->> 'periodo_extrato' = '2026-05';

  if quantidade_contrapartidas <> 2 then
    raise exception 'Contrapartidas Inter de maio incorretas: esperadas 2, encontradas %.', quantidade_contrapartidas;
  end if;

  with movimentos as (
    select * from public.movimentacoes
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and (
        metadados ->> 'importacao_lote' = 'inter-filipe-2026-05'
        or id in (
          (md5('financas:mov:nubank:filipe:2026-05:01'))::uuid,
          (md5('financas:mov:nubank:filipe:2026-05:08'))::uuid
        )
      )
  )
  select
    sum(case when natureza = 'receita' and conta_id = (md5('financas:conta:extrato-inter:filipe'))::uuid then valor
             when natureza = 'transferencia' and conta_destino_id = (md5('financas:conta:extrato-inter:filipe'))::uuid then valor else 0 end),
    sum(case when natureza = 'despesa' and conta_id = (md5('financas:conta:extrato-inter:filipe'))::uuid then valor
             when natureza = 'transferencia' and conta_id = (md5('financas:conta:extrato-inter:filipe'))::uuid then valor else 0 end)
  into entradas, saidas from movimentos;

  if entradas <> 8729.01 or saidas <> 12445.56 or 3725.80 + entradas - saidas <> 9.25 then
    raise exception 'Totais ou saldo do Inter de maio nao conferem.';
  end if;

  if exists (
    select 1 from public.movimentacoes
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and metadados ->> 'importacao_lote' = 'inter-filipe-2026-05'
      and mes_competencia <> '2026-05-01'::date
  ) then
    raise exception 'O extrato Inter de maio alterou outro mes.';
  end if;
end;
$$;

commit;
