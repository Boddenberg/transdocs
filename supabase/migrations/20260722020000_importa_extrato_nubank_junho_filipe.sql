begin;

-- Importacao auditavel do extrato Nubank do Filipe de junho de 2026.
-- O usuario confirmou explicitamente o cadastro deste extrato.
do $$
begin
  if not exists (
    select 1
    from public.perfis
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and lower(coalesce(nome, '')) like '%filipe%'
  ) then
    raise exception 'Perfil do Filipe nao encontrado; importacao Nubank cancelada.';
  end if;

  if not exists (
    select 1
    from public.contas
    where id = (md5('financas:conta:extrato-nubank:filipe'))::uuid
      and usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and nome = 'Extrato Nubank'
      and instituicao = 'Nubank'
  ) then
    raise exception 'Conta Extrato Nubank nao encontrada; importacao de junho cancelada.';
  end if;

  if not exists (
    select 1
    from public.categorias
    where id = (md5('financas:categoria:extrato-nubank:filipe'))::uuid
      and usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and nome = 'Extrato Nubank'
  ) then
    raise exception 'Categoria Extrato Nubank nao encontrada; importacao de junho cancelada.';
  end if;

  if not exists (
    select 1
    from public.grupos_fontes_panorama
    where id = (md5('financas:grupo:extrato-nubank:filipe'))::uuid
      and usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and nome = 'Extrato Nubank'
  ) then
    raise exception 'Grupo Extrato Nubank nao encontrado; importacao de junho cancelada.';
  end if;

  if exists (
    select 1
    from public.movimentacoes
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and metadados ->> 'importacao_lote' = 'nubank-filipe-2026-06'
  ) then
    raise exception 'O extrato Nubank de junho ja possui lancamentos; importacao cancelada.';
  end if;

  if not exists (
    select 1
    from public.contas
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and id in (
        'd33d76b9-5f1b-436c-aec1-2f7270a863e6'::uuid,
        '992fdcff-3897-4bac-b006-848247f7f31c'::uuid
      )
    group by usuario_id
    having count(*) = 2
  ) then
    raise exception 'Cartoes de contrapartida nao foram encontrados; importacao cancelada.';
  end if;
end;
$$;

with dados (
  chave, data_movimentacao, natureza, descricao, valor, forma_pagamento,
  tipo_lancamento, descricao_original, pagina_pdf, conta_destino_id
) as (
  values
    ('01', '2026-06-01'::date, 'receita', 'Booking.com', 2336.62, 'pix', 'transferencia_recebida', 'Transferencia recebida pelo Pix - BOOKING COM BRASIL SERVICOS DE RESERVA DE HOTEIS', 1, null::uuid),
    ('02', '2026-06-01'::date, 'despesa', 'Spotify', 31.90, 'debito', 'compra_debito', 'Compra no debito - EBN *SPOTIFY', 1, null::uuid),
    ('03', '2026-06-03'::date, 'despesa', 'Rei dos Coins', 118.84, 'pix', 'transferencia_pix_enviada', 'Transferencia enviada pelo Pix - REI DOS COINS', 1, null::uuid),
    ('04', '2026-06-07'::date, 'despesa', 'Pix - Saulo Morais de Oliveira', 60.00, 'pix', 'transferencia_pix_enviada', 'Transferencia enviada pelo Pix - SAULO MORAIS DE OLIVEIRA', 1, null::uuid),
    ('05', '2026-06-08'::date, 'despesa', 'Rei dos Coins', 42.78, 'pix', 'transferencia_pix_enviada', 'Transferencia enviada pelo Pix - REI DOS COINS', 1, null::uuid),
    ('06', '2026-06-08'::date, 'despesa', 'Pix - Gisele Raile', 80.00, 'pix', 'transferencia_pix_enviada', 'Transferencia enviada pelo Pix - Gisele Raile de Miranda e Silva', 2, null::uuid),
    ('07', '2026-06-09'::date, 'receita', 'Transferencia recebida - Leandro Ferreira', 360.00, 'pix', 'transferencia_recebida', 'Transferencia recebida pelo Pix - LEANDRO FERREIRA DA ROSA', 2, null::uuid),
    ('08', '2026-06-09'::date, 'transferencia', 'Pagamento da fatura Cartao Mercado Pago', 370.66, 'transferencia', 'pagamento_fatura_cartao', 'Transferencia enviada pelo Pix - MERCADO PAGO INSTITUICAO DE PAGAMENTO', 2, 'd33d76b9-5f1b-436c-aec1-2f7270a863e6'::uuid),
    ('09', '2026-06-09'::date, 'transferencia', 'Pagamento da fatura Cartao Carrefour', 1230.76, 'transferencia', 'pagamento_fatura_cartao', 'Transferencia enviada pelo Pix - BANCO CSF', 2, '992fdcff-3897-4bac-b006-848247f7f31c'::uuid),
    ('10', '2026-06-09'::date, 'despesa', 'Ciganinho Intermediacoes', 451.50, 'pix', 'transferencia_pix_enviada', 'Transferencia enviada pelo Pix - CIGANINHO INTERMEDIACOES', 2, null::uuid),
    ('11', '2026-06-12'::date, 'despesa', 'Factory Games', 50.00, 'pix', 'transferencia_pix_enviada', 'Transferencia enviada pelo Pix - FACTORY GAMES LTDA', 2, null::uuid),
    ('12', '2026-06-13'::date, 'despesa', 'Pix - Jurene Boddenberg', 54.00, 'pix', 'transferencia_pix_enviada', 'Transferencia enviada pelo Pix - JURENE BODDENBERG', 2, null::uuid),
    ('13', '2026-06-14'::date, 'receita', 'Transferencia recebida - Bianca Bezerra', 15.00, 'transferencia', 'transferencia_recebida', 'Transferencia Recebida - Bianca Bezerra Machado', 3, null::uuid),
    ('14', '2026-06-15'::date, 'despesa', 'Aice Gaming', 104.00, 'pix', 'transferencia_pix_enviada', 'Transferencia enviada pelo Pix - aicegaming', 3, null::uuid),
    ('15', '2026-06-15'::date, 'despesa', 'Rei dos Coins', 81.39, 'pix', 'transferencia_pix_enviada', 'Transferencia enviada pelo Pix - REI DOS COINS', 3, null::uuid),
    ('16', '2026-06-15'::date, 'despesa', 'Rei dos Coins', 42.68, 'pix', 'transferencia_pix_enviada', 'Transferencia enviada pelo Pix - REI DOS COINS', 3, null::uuid)
)
insert into public.movimentacoes (
  id, usuario_id, conta_id, conta_destino_id, categoria_id, natureza,
  descricao, valor, data_movimentacao, mes_competencia, status,
  forma_pagamento, origem, observacoes, metadados, confirmado_por_usuario
)
select
  (md5('financas:mov:nubank:filipe:2026-06:' || dados.chave))::uuid,
  'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid,
  (md5('financas:conta:extrato-nubank:filipe'))::uuid,
  dados.conta_destino_id,
  case
    when dados.natureza = 'transferencia' then null::uuid
    else (md5('financas:categoria:extrato-nubank:filipe'))::uuid
  end,
  dados.natureza,
  dados.descricao,
  dados.valor,
  dados.data_movimentacao,
  '2026-06-01'::date,
  'confirmada',
  dados.forma_pagamento,
  'extrato',
  dados.descricao_original || ' - valor no extrato R$ ' ||
    case when dados.natureza = 'receita' then '' else '-' end ||
    to_char(dados.valor, 'FM999999990.00') || '. Extrato Nubank de 2026-06.',
  jsonb_build_object(
    'instituicao', 'Nubank',
    'tipo_documento', 'extrato_conta',
    'agencia', '0001',
    'conta_extrato', '17483930-2',
    'tipo_lancamento', dados.tipo_lancamento,
    'descricao_original', dados.descricao_original,
    'valor_assinado', case
      when dados.natureza = 'receita' then to_char(dados.valor, 'FM999999990.00')
      else '-' || to_char(dados.valor, 'FM999999990.00')
    end,
    'saldo_inicial_periodo', '13.20',
    'saldo_final_periodo', '6.31',
    'periodo_extrato', '2026-06',
    'arquivo_origem', 'NU_174839302_01JUN2026_30JUN2026.pdf',
    'arquivo_sha256', '317f8651acb84037a8814779423452e75d0fd0e9e1e32d380bf4370fa08f2f20',
    'pagina_pdf', dados.pagina_pdf,
    'ordem_pdf', dados.chave::integer,
    'importacao_lote', 'nubank-filipe-2026-06',
    'projetada_pela_ia', false
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
  select count(*)
  into quantidade
  from public.movimentacoes
  where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
    and metadados ->> 'importacao_lote' = 'nubank-filipe-2026-06';

  if quantidade <> 16 then
    raise exception 'Extrato Nubank de junho incompleto: esperados 16 lancamentos, encontrados %.', quantidade;
  end if;

  select
    coalesce(sum(case
      when natureza = 'receita' and conta_id = (md5('financas:conta:extrato-nubank:filipe'))::uuid then valor
      when natureza = 'transferencia' and conta_destino_id = (md5('financas:conta:extrato-nubank:filipe'))::uuid then valor
      else 0
    end), 0),
    coalesce(sum(case
      when natureza = 'despesa' and conta_id = (md5('financas:conta:extrato-nubank:filipe'))::uuid then valor
      when natureza = 'transferencia' and conta_id = (md5('financas:conta:extrato-nubank:filipe'))::uuid then valor
      else 0
    end), 0)
  into entradas, saidas
  from public.movimentacoes
  where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
    and metadados ->> 'importacao_lote' = 'nubank-filipe-2026-06';

  if entradas <> 2711.62 or saidas <> 2718.51 then
    raise exception 'Totais Nubank de junho divergentes: entradas %, saidas %.', entradas, saidas;
  end if;

  if 13.20 + entradas - saidas <> 6.31 then
    raise exception 'Saldo final Nubank de junho nao confere.';
  end if;

  if exists (
    select 1
    from public.movimentacoes
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and metadados ->> 'importacao_lote' = 'nubank-filipe-2026-06'
      and mes_competencia <> '2026-06-01'::date
  ) then
    raise exception 'O extrato Nubank de junho alterou outro mes.';
  end if;
end;
$$;

commit;
