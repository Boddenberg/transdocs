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
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and id in (
        'd64bb1b6-1140-5470-8695-7aadce45262c'::uuid,
        (md5('financas:conta:extrato-nubank:filipe'))::uuid,
        (md5('financas:conta:extrato-inter:filipe'))::uuid
      )
    group by usuario_id
    having count(*) = 3
  ) then
    raise exception 'Contas de contrapartida do Nubank nao foram encontradas.';
  end if;
end;
$$;

-- Reutiliza as entradas ja registradas no extrato Itau para que cada
-- transferencia entre contas proprias exista apenas uma vez.
update public.movimentacoes
set conta_id = (md5('financas:conta:extrato-nubank:filipe'))::uuid,
    observacoes = concat_ws(' ', observacoes, 'Contrapartida no Nubank em 04/05/2026.'),
    metadados = metadados || jsonb_build_object(
      'contrapartida_nubank', jsonb_build_object(
        'arquivo', 'NU_174839302_01MAI2026_31MAI2026.pdf',
        'arquivo_sha256', 'b8d1caa441b077e5d7500a9788d19139b10af286f898c6f2c7100819b4fcbc80',
        'pagina', 1, 'data_movimentacao', '2026-05-04',
        'descricao_original', 'Transferencia enviada pelo Pix - Filipe Boddenberg Ribeiro - Itau'
      )
    )
where id = '88da2ddf-6fd2-5963-a017-fbec97acb1e2'::uuid
  and usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
  and conta_id = 'bbe5ac59-d57f-5149-842e-e4163f9bd0e2'::uuid
  and conta_destino_id = 'd64bb1b6-1140-5470-8695-7aadce45262c'::uuid
  and valor = 660.00;

update public.movimentacoes
set conta_id = (md5('financas:conta:extrato-nubank:filipe'))::uuid,
    observacoes = concat_ws(' ', observacoes, 'Contrapartida no Nubank em 06/05/2026.'),
    metadados = metadados || jsonb_build_object(
      'contrapartida_nubank', jsonb_build_object(
        'arquivo', 'NU_174839302_01MAI2026_31MAI2026.pdf',
        'arquivo_sha256', 'b8d1caa441b077e5d7500a9788d19139b10af286f898c6f2c7100819b4fcbc80',
        'pagina', 2, 'data_movimentacao', '2026-05-06',
        'descricao_original', 'Transferencia enviada pelo Pix - Filipe Boddenberg Ribeiro - Itau'
      )
    )
where id = 'bc7ba2dd-14ae-5834-bde4-e0dc205a1c9f'::uuid
  and usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
  and conta_id = 'bbe5ac59-d57f-5149-842e-e4163f9bd0e2'::uuid
  and conta_destino_id = 'd64bb1b6-1140-5470-8695-7aadce45262c'::uuid
  and valor = 1000.00;

with dados (
  chave, data_movimentacao, conta_id, conta_destino_id, categoria_id,
  natureza, descricao, valor, forma_pagamento, tipo_lancamento,
  descricao_original, pagina_pdf, valor_assinado
) as (
  values
    ('01', '2026-05-01'::date, (md5('financas:conta:extrato-inter:filipe'))::uuid, (md5('financas:conta:extrato-nubank:filipe'))::uuid, null::uuid, 'transferencia', 'Transferencia entre contas do Inter para o Nubank', 660.00, 'pix', 'transferencia_entre_contas', 'Transferencia recebida pelo Pix - FILIPE BODDENBERG RIBEIRO - BANCO INTER', 1, '660.00'),
    ('02', '2026-05-01'::date, (md5('financas:conta:extrato-nubank:filipe'))::uuid, null::uuid, (md5('financas:categoria:extrato-nubank:filipe'))::uuid, 'despesa', 'Pix - Thiago Boddenberg Ribeiro', 1060.00, 'pix', 'transferencia_pix_enviada', 'Transferencia enviada pelo Pix - Thiago Boddenberg Ribeiro', 1, '-1060.00'),
    ('03', '2026-05-01'::date, (md5('financas:conta:extrato-nubank:filipe'))::uuid, null::uuid, (md5('financas:categoria:extrato-nubank:filipe'))::uuid, 'despesa', 'Pix - Jurene Boddenberg', 1815.00, 'pix', 'transferencia_pix_enviada', 'Transferencia enviada pelo Pix - Jurene Boddenberg', 1, '-1815.00'),
    ('04', '2026-05-04'::date, (md5('financas:conta:extrato-nubank:filipe'))::uuid, null::uuid, (md5('financas:categoria:extrato-nubank:filipe'))::uuid, 'receita', 'Booking.com', 2534.46, 'transferencia', 'transferencia_recebida', 'Transferencia Recebida - BOOKING.COM BRASIL SERVICOS DE RESERVA DE HOTEIS', 1, '2534.46'),
    ('07', '2026-05-06'::date, (md5('financas:conta:extrato-nubank:filipe'))::uuid, null::uuid, (md5('financas:categoria:extrato-nubank:filipe'))::uuid, 'despesa', 'Clinica Biosphere', 1250.00, 'pix', 'transferencia_pix_enviada', 'Transferencia enviada pelo Pix - CLINICA BIOSPHERE SERVICOS MEDICOS E ENSINO', 2, '-1250.00'),
    ('08', '2026-05-10'::date, (md5('financas:conta:extrato-inter:filipe'))::uuid, (md5('financas:conta:extrato-nubank:filipe'))::uuid, null::uuid, 'transferencia', 'Transferencia entre contas do Inter para o Nubank', 500.00, 'pix', 'transferencia_entre_contas', 'Transferencia recebida pelo Pix - FILIPE BODDENBERG RIBEIRO - BANCO INTER', 2, '500.00'),
    ('09', '2026-05-10'::date, (md5('financas:conta:extrato-nubank:filipe'))::uuid, null::uuid, (md5('financas:categoria:extrato-nubank:filipe'))::uuid, 'despesa', 'Pix - Amanda Cassiolato', 493.49, 'pix', 'transferencia_pix_enviada', 'Transferencia enviada pelo Pix - AMANDA CASSIOLATO INTERMEDIACAO DE NEGOCIOS LTDA', 2, '-493.49'),
    ('10', '2026-05-11'::date, (md5('financas:conta:extrato-nubank:filipe'))::uuid, null::uuid, (md5('financas:categoria:extrato-nubank:filipe'))::uuid, 'despesa', 'Pix - Amanda Cassiolato', 227.77, 'pix', 'transferencia_pix_enviada', 'Transferencia enviada pelo Pix - AMANDA CASSIOLATO INTERMEDIACAO DE NEGOCIOS LTDA', 2, '-227.77'),
    ('11', '2026-05-11'::date, (md5('financas:conta:extrato-nubank:filipe'))::uuid, null::uuid, (md5('financas:categoria:extrato-nubank:filipe'))::uuid, 'despesa', 'Factory Games', 50.00, 'pix', 'transferencia_pix_enviada', 'Transferencia enviada pelo Pix - FACTORY GAMES LTDA', 2, '-50.00')
)
insert into public.movimentacoes (
  id, usuario_id, conta_id, conta_destino_id, categoria_id, natureza,
  descricao, valor, data_movimentacao, mes_competencia, status,
  forma_pagamento, origem, observacoes, metadados, confirmado_por_usuario
)
select
  (md5('financas:mov:nubank:filipe:2026-05:' || dados.chave))::uuid,
  'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid,
  dados.conta_id, dados.conta_destino_id, dados.categoria_id, dados.natureza,
  dados.descricao, dados.valor, dados.data_movimentacao, '2026-05-01'::date,
  'confirmada', dados.forma_pagamento, 'extrato',
  dados.descricao_original || ' - valor no extrato R$ ' || dados.valor_assinado ||
    '. Extrato Nubank de 2026-05.',
  jsonb_build_object(
    'instituicao', 'Nubank', 'tipo_documento', 'extrato_conta',
    'agencia', '0001', 'conta_extrato', '17483930-2',
    'tipo_lancamento', dados.tipo_lancamento,
    'descricao_original', dados.descricao_original,
    'valor_assinado', dados.valor_assinado,
    'saldo_inicial_periodo', '2875.00', 'saldo_final_periodo', '13.20',
    'rendimento_liquido_periodo', '0.00', 'periodo_extrato', '2026-05',
    'arquivo_origem', 'NU_174839302_01MAI2026_31MAI2026.pdf',
    'arquivo_sha256', 'b8d1caa441b077e5d7500a9788d19139b10af286f898c6f2c7100819b4fcbc80',
    'pagina_pdf', dados.pagina_pdf, 'ordem_pdf', dados.chave::integer,
    'importacao_lote', 'nubank-filipe-2026-05', 'projetada_pela_ia', false
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
    and metadados ->> 'importacao_lote' = 'nubank-filipe-2026-05';

  if quantidade_novos <> 9 then
    raise exception 'Extrato Nubank de maio incompleto: esperados 9 novos registros, encontrados %.', quantidade_novos;
  end if;

  select count(*) into quantidade_contrapartidas
  from public.movimentacoes
  where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
    and metadados -> 'contrapartida_nubank' ->> 'arquivo_sha256' = 'b8d1caa441b077e5d7500a9788d19139b10af286f898c6f2c7100819b4fcbc80';

  if quantidade_contrapartidas <> 2 then
    raise exception 'Contrapartidas Nubank de maio incorretas: esperadas 2, encontradas %.', quantidade_contrapartidas;
  end if;

  with movimentos as (
    select * from public.movimentacoes
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and (
        metadados ->> 'importacao_lote' = 'nubank-filipe-2026-05'
        or metadados -> 'contrapartida_nubank' ->> 'arquivo_sha256' = 'b8d1caa441b077e5d7500a9788d19139b10af286f898c6f2c7100819b4fcbc80'
      )
  )
  select
    sum(case when natureza = 'receita' and conta_id = (md5('financas:conta:extrato-nubank:filipe'))::uuid then valor
             when natureza = 'transferencia' and conta_destino_id = (md5('financas:conta:extrato-nubank:filipe'))::uuid then valor else 0 end),
    sum(case when natureza = 'despesa' and conta_id = (md5('financas:conta:extrato-nubank:filipe'))::uuid then valor
             when natureza = 'transferencia' and conta_id = (md5('financas:conta:extrato-nubank:filipe'))::uuid then valor else 0 end)
  into entradas, saidas from movimentos;

  if entradas <> 3694.46 or saidas <> 6556.26 or 2875.00 + entradas - saidas <> 13.20 then
    raise exception 'Totais ou saldo do Nubank de maio nao conferem.';
  end if;

  if exists (
    select 1 from public.movimentacoes
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and metadados ->> 'importacao_lote' = 'nubank-filipe-2026-05'
      and mes_competencia <> '2026-05-01'::date
  ) then
    raise exception 'O extrato Nubank de maio alterou outro mes.';
  end if;
end;
$$;

commit;
