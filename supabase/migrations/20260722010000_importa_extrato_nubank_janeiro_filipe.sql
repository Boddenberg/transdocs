begin;

-- Importacao auditavel do extrato Nubank do Filipe de janeiro de 2026.
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

  if exists (
    select 1
    from public.contas
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and lower(nome) = lower('Extrato Nubank')
      and id <> (md5('financas:conta:extrato-nubank:filipe'))::uuid
  ) then
    raise exception 'Ja existe outra conta chamada Extrato Nubank; importacao cancelada.';
  end if;

  if exists (
    select 1
    from public.categorias
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and lower(nome) = lower('Extrato Nubank')
      and id <> (md5('financas:categoria:extrato-nubank:filipe'))::uuid
  ) then
    raise exception 'Ja existe outra categoria chamada Extrato Nubank; importacao cancelada.';
  end if;

  if exists (
    select 1
    from public.grupos_fontes_panorama
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and lower(nome) = lower('Extrato Nubank')
      and id <> (md5('financas:grupo:extrato-nubank:filipe'))::uuid
  ) then
    raise exception 'Ja existe outro grupo chamado Extrato Nubank; importacao cancelada.';
  end if;

  if exists (
    select 1
    from public.movimentacoes
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and metadados ->> 'importacao_lote' = 'nubank-filipe-2026-01'
  ) then
    raise exception 'O extrato Nubank de janeiro ja possui lancamentos; importacao cancelada.';
  end if;

  if not exists (
    select 1 from public.contas
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and id in (
        'd64bb1b6-1140-5470-8695-7aadce45262c'::uuid,
        '70c10a6f-1882-5411-858a-c465dacecf29'::uuid,
        '992fdcff-3897-4bac-b006-848247f7f31c'::uuid
      )
    group by usuario_id
    having count(*) = 3
  ) then
    raise exception 'Contas de contrapartida do Filipe nao foram encontradas; importacao cancelada.';
  end if;
end;
$$;

insert into public.contas (
  id, usuario_id, nome, tipo, instituicao, cor, saldo_inicial,
  data_saldo_inicial, incluir_no_patrimonio, ativa
)
values (
  (md5('financas:conta:extrato-nubank:filipe'))::uuid,
  'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid,
  'Extrato Nubank', 'conta_corrente', 'Nubank', '#820AD1', 10.37,
  '2026-01-01'::date, false, true
)
on conflict (id) do update
set nome = excluded.nome,
    tipo = excluded.tipo,
    instituicao = excluded.instituicao,
    cor = excluded.cor,
    saldo_inicial = excluded.saldo_inicial,
    data_saldo_inicial = excluded.data_saldo_inicial,
    incluir_no_patrimonio = excluded.incluir_no_patrimonio,
    ativa = true;

insert into public.categorias (
  id, usuario_id, nome, natureza, icone, cor, padrao, ativa
)
values (
  (md5('financas:categoria:extrato-nubank:filipe'))::uuid,
  'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid,
  'Extrato Nubank', 'ambos', 'landmark', '#820AD1', false, true
)
on conflict (id) do update
set nome = excluded.nome,
    natureza = excluded.natureza,
    icone = excluded.icone,
    cor = excluded.cor,
    ativa = true;

insert into public.grupos_fontes_panorama (
  id, usuario_id, nome, ordem, recolhido
)
values (
  (md5('financas:grupo:extrato-nubank:filipe'))::uuid,
  'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid,
  'Extrato Nubank', 4, false
)
on conflict (id) do update
set nome = excluded.nome,
    ordem = excluded.ordem,
    recolhido = excluded.recolhido;

insert into public.fontes_grupos_panorama (
  id, usuario_id, grupo_id, fonte_tipo, fonte_id, ordem
)
values (
  (md5('financas:fonte-grupo:extrato-nubank:filipe'))::uuid,
  'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid,
  (md5('financas:grupo:extrato-nubank:filipe'))::uuid,
  'conta', (md5('financas:conta:extrato-nubank:filipe'))::uuid, 0
)
on conflict (usuario_id, fonte_tipo, fonte_id) do update
set grupo_id = excluded.grupo_id,
    ordem = excluded.ordem;

insert into public.linhas_grupos_panorama (
  id, usuario_id, grupo_id, fonte_chave, ordem
)
values
  (
    (md5('financas:linha-grupo:extrato-nubank:entradas:filipe'))::uuid,
    'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid,
    (md5('financas:grupo:extrato-nubank:filipe'))::uuid,
    'entradas:categoria:' || (md5('financas:categoria:extrato-nubank:filipe'))::uuid::text, 0
  ),
  (
    (md5('financas:linha-grupo:extrato-nubank:despesas:filipe'))::uuid,
    'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid,
    (md5('financas:grupo:extrato-nubank:filipe'))::uuid,
    'despesas_variaveis:categoria:' || (md5('financas:categoria:extrato-nubank:filipe'))::uuid::text, 1
  )
on conflict (usuario_id, fonte_chave) do update
set grupo_id = excluded.grupo_id,
    ordem = excluded.ordem;

-- Contrapartidas ja confirmadas em extratos anteriormente cadastrados.
update public.movimentacoes
set conta_id = (md5('financas:conta:extrato-nubank:filipe'))::uuid,
    observacoes = concat_ws(' ', observacoes, 'Contrapartida no Nubank em 03/01/2026.'),
    metadados = metadados || jsonb_build_object(
      'contrapartida_nubank', jsonb_build_object(
        'arquivo', 'NU_174839302_01JAN2026_31JAN2026.pdf',
        'arquivo_sha256', 'a2cf01bbc6c3d37a0eb0dfec2491c971657c1965ef2e225961b4ea9dcbc04205',
        'pagina', 1, 'data_movimentacao', '2026-01-03',
        'descricao_original', 'Transferencia enviada pelo Pix - Filipe Boddenberg Ribeiro - Itau'
      )
    )
where id = 'cc77479a-2f88-5a63-8fc6-321ed5ebb9ca'::uuid
  and usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
  and conta_id = 'bbe5ac59-d57f-5149-842e-e4163f9bd0e2'::uuid
  and conta_destino_id = 'd64bb1b6-1140-5470-8695-7aadce45262c'::uuid
  and valor = 1000.00;

update public.movimentacoes
set conta_destino_id = (md5('financas:conta:extrato-nubank:filipe'))::uuid,
    observacoes = concat_ws(' ', observacoes, 'Contrapartida no Nubank em 07/01/2026.'),
    metadados = metadados || jsonb_build_object(
      'contrapartida_nubank', jsonb_build_object(
        'arquivo', 'NU_174839302_01JAN2026_31JAN2026.pdf',
        'arquivo_sha256', 'a2cf01bbc6c3d37a0eb0dfec2491c971657c1965ef2e225961b4ea9dcbc04205',
        'pagina', 2, 'data_movimentacao', '2026-01-07',
        'descricao_original', 'Transferencia recebida pelo Pix - Filipe Boddenberg Ribeiro - Itau'
      )
    )
where id = '309b7594-e5b3-549a-b27e-c6cf1dc129c2'::uuid
  and usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
  and conta_id = 'd64bb1b6-1140-5470-8695-7aadce45262c'::uuid
  and conta_destino_id = 'bbe5ac59-d57f-5149-842e-e4163f9bd0e2'::uuid
  and valor = 50.00;

update public.movimentacoes
set conta_id = (md5('financas:conta:extrato-nubank:filipe'))::uuid,
    observacoes = concat_ws(' ', observacoes, 'Contrapartida no Nubank em 07/01/2026.'),
    metadados = metadados || jsonb_build_object(
      'contrapartida_nubank', jsonb_build_object(
        'arquivo', 'NU_174839302_01JAN2026_31JAN2026.pdf',
        'arquivo_sha256', 'a2cf01bbc6c3d37a0eb0dfec2491c971657c1965ef2e225961b4ea9dcbc04205',
        'pagina', 2, 'data_movimentacao', '2026-01-07',
        'descricao_original', 'Transferencia enviada pelo Pix - Filipe Boddenberg Ribeiro - Itau'
      )
    )
where id = '80622648-14f7-50f2-a410-5252aadb50a1'::uuid
  and usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
  and conta_id = 'bbe5ac59-d57f-5149-842e-e4163f9bd0e2'::uuid
  and conta_destino_id = 'd64bb1b6-1140-5470-8695-7aadce45262c'::uuid
  and valor = 3000.00;

update public.movimentacoes
set conta_destino_id = (md5('financas:conta:extrato-nubank:filipe'))::uuid,
    observacoes = concat_ws(' ', observacoes, 'Contrapartida no Nubank em 13/01/2026.'),
    metadados = metadados || jsonb_build_object(
      'contrapartida_nubank', jsonb_build_object(
        'arquivo', 'NU_174839302_01JAN2026_31JAN2026.pdf',
        'arquivo_sha256', 'a2cf01bbc6c3d37a0eb0dfec2491c971657c1965ef2e225961b4ea9dcbc04205',
        'pagina', 4, 'data_movimentacao', '2026-01-13',
        'descricao_original', 'Transferencia recebida pelo Pix - Filipe Boddenberg Ribeiro - Itau'
      )
    )
where id = '747bfc30-95ca-5cb5-8ba4-eac9b4bd14ab'::uuid
  and usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
  and conta_id = 'd64bb1b6-1140-5470-8695-7aadce45262c'::uuid
  and conta_destino_id = 'bbe5ac59-d57f-5149-842e-e4163f9bd0e2'::uuid
  and valor = 300.00;

update public.movimentacoes
set conta_id = (md5('financas:conta:extrato-nubank:filipe'))::uuid,
    observacoes = concat_ws(' ', observacoes, 'Contrapartida no Nubank em 16/01/2026.'),
    metadados = metadados || jsonb_build_object(
      'contrapartida_nubank', jsonb_build_object(
        'arquivo', 'NU_174839302_01JAN2026_31JAN2026.pdf',
        'arquivo_sha256', 'a2cf01bbc6c3d37a0eb0dfec2491c971657c1965ef2e225961b4ea9dcbc04205',
        'pagina', 5, 'data_movimentacao', '2026-01-16',
        'descricao_original', 'Transferencia enviada pelo Pix - Filipe Boddenberg Ribeiro'
      )
    )
where id = '00ef2a8f-0980-5277-ba1c-850aac8b70ac'::uuid
  and usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
  and conta_id = 'bbe5ac59-d57f-5149-842e-e4163f9bd0e2'::uuid
  and conta_destino_id = '70c10a6f-1882-5411-858a-c465dacecf29'::uuid
  and valor = 50.00;

with dados (
  chave, data_movimentacao, natureza, descricao, valor, forma_pagamento,
  tipo_lancamento, descricao_original, pagina_pdf, conta_destino_id
) as (
  values
    ('01', '2026-01-02'::date, 'receita', 'Transferencia recebida - Caixa Economica Federal', 1138.06, 'transferencia', 'transferencia_recebida', 'Transferencia Recebida - CAIXA ECONOMICA FEDERAL', 1, null::uuid),
    ('02', '2026-01-03'::date, 'despesa', 'Pix - Victor Ellyvan Campagnola', 40.00, 'pix', 'transferencia_pix_enviada', 'Transferencia enviada pelo Pix - Victor Ellyvan Campagnola - Nu Pagamentos', 1, null::uuid),
    ('03', '2026-01-03'::date, 'despesa', 'Demerget', 29.90, 'pix', 'transferencia_pix_enviada', 'Transferencia enviada pelo Pix - DEMERGE - DLOCAL BRASIL IP', 1, null::uuid),
    ('04', '2026-01-04'::date, 'despesa', 'Pasteltop', 14.00, 'debito', 'compra_debito', 'Compra no debito - MP *PASTELTOP', 1, null::uuid),
    ('05', '2026-01-06'::date, 'despesa', 'Pasteltop', 14.00, 'debito', 'compra_debito', 'Compra no debito - MP *PASTELTOP', 1, null::uuid),
    ('06', '2026-01-06'::date, 'despesa', 'Shopee', 50.36, 'pix', 'transferencia_pix_enviada', 'Transferencia enviada pelo Pix - SHPP BRASIL INSTITUICAO DE PAGAMENTO', 1, null::uuid),
    ('07', '2026-01-07'::date, 'receita', 'Booking.com', 3563.05, 'transferencia', 'transferencia_recebida', 'Transferencia Recebida - BOOKING.COM BRASIL SERVICOS DE RESERVA DE HOTEIS', 2, null::uuid),
    ('08', '2026-01-07'::date, 'despesa', 'Hirota Office Ceic', 36.54, 'debito', 'compra_debito', 'Compra no debito - HIROTA OFFICE CEIC ITA', 2, null::uuid),
    ('09', '2026-01-07'::date, 'despesa', 'Hirota Office Ceic', 22.76, 'debito', 'compra_debito', 'Compra no debito - HIROTA OFFICE CEIC ITA', 2, null::uuid),
    ('10', '2026-01-07'::date, 'despesa', 'Carito Confeitaria', 52.00, 'debito', 'compra_debito', 'Compra no debito - CARITO CONFEITARIA ART', 2, null::uuid),
    ('11', '2026-01-08'::date, 'despesa', 'Uber', 35.99, 'pix', 'transferencia_pix_enviada', 'Transferencia enviada pelo Pix - UBER DO BRASIL TECNOLOGIA', 2, null::uuid),
    ('12', '2026-01-08'::date, 'despesa', 'Pastelaria Japa', 11.00, 'debito', 'compra_debito', 'Compra no debito - PASTELARIA JAPA', 2, null::uuid),
    ('13', '2026-01-09'::date, 'despesa', 'iFood', 46.97, 'pix', 'transferencia_pix_enviada', 'Transferencia enviada pelo Pix - IFOOD.COM AGENCIA DE RESTAURANTES ONLINE', 3, null::uuid),
    ('14', '2026-01-09'::date, 'despesa', 'Amanda Cassiolato', 23.55, 'pix', 'transferencia_pix_enviada', 'Transferencia enviada pelo Pix - AMANDA CASSIOLATO INTERMEDIACAO DE NEGOCIOS', 3, null::uuid),
    ('15', '2026-01-10'::date, 'despesa', 'Amanda Cassiolato', 58.87, 'pix', 'transferencia_pix_enviada', 'Transferencia enviada pelo Pix - AMANDA CASSIOLATO INTERMEDIACAO DE NEGOCIOS', 3, null::uuid),
    ('16', '2026-01-10'::date, 'despesa', 'Bacio di Latte', 63.90, 'debito', 'compra_debito', 'Compra no debito - Bacio di Latte-LJ0002', 3, null::uuid),
    ('17', '2026-01-11'::date, 'despesa', 'Pasteltop', 14.00, 'debito', 'compra_debito', 'Compra no debito - MP *PASTELTOP', 3, null::uuid),
    ('18', '2026-01-11'::date, 'despesa', 'HPM Distribuicao', 100.00, 'pix', 'transferencia_pix_enviada', 'Transferencia enviada pelo Pix - HPM DISTRIBUICAO EM MASSA LTDA', 3, null::uuid),
    ('19', '2026-01-11'::date, 'despesa', 'Amanda Cassiolato', 64.76, 'pix', 'transferencia_pix_enviada', 'Transferencia enviada pelo Pix - AMANDA CASSIOLATO INTERMEDIACAO DE NEGOCIOS', 3, null::uuid),
    ('20', '2026-01-11'::date, 'despesa', 'Pasteltop', 14.00, 'debito', 'compra_debito', 'Compra no debito - MP *PASTELTOP', 3, null::uuid),
    ('21', '2026-01-12'::date, 'despesa', 'Factory Games', 30.00, 'pix', 'transferencia_pix_enviada', 'Transferencia enviada pelo Pix - FACTORY GAMES LTDA', 3, null::uuid),
    ('22', '2026-01-13'::date, 'despesa', 'Rappi', 73.96, 'debito', 'compra_debito_nupay', 'Compra no debito via NuPay - Rappi', 4, null::uuid),
    ('23', '2026-01-13'::date, 'transferencia', 'Pagamento da fatura Cartao Carrefour', 116.79, 'transferencia', 'pagamento_fatura_cartao', 'Transferencia enviada pelo Pix - BANCO CSF', 4, '992fdcff-3897-4bac-b006-848247f7f31c'::uuid),
    ('24', '2026-01-14'::date, 'receita', 'Reembolso Uber', 41.90, 'pix', 'reembolso_pix', 'Reembolso recebido pelo Pix - UBER DO BRASIL TECNOLOGIA', 4, null::uuid),
    ('25', '2026-01-14'::date, 'despesa', 'Transferencia para conta propria - 99Pay', 50.00, 'pix', 'transferencia_pix_enviada', 'Transferencia enviada pelo Pix - FILIPE BODDENBERG RIBEIRO - 99PAY', 4, null::uuid),
    ('26', '2026-01-14'::date, 'despesa', 'Uber', 41.90, 'pix', 'transferencia_pix_enviada', 'Transferencia enviada pelo Pix - UBER DO BRASIL TECNOLOGIA', 4, null::uuid),
    ('27', '2026-01-15'::date, 'receita', 'Transferencia recebida - Soraia Hiromi Saito', 100.00, 'pix', 'transferencia_recebida', 'Transferencia recebida pelo Pix - SORAIA HIROMI SAITO', 4, null::uuid),
    ('28', '2026-01-15'::date, 'despesa', 'Uber', 38.97, 'pix', 'transferencia_pix_enviada', 'Transferencia enviada pelo Pix - UBER DO BRASIL TECNOLOGIA', 5, null::uuid),
    ('29', '2026-01-17'::date, 'despesa', 'Uber', 64.66, 'pix', 'transferencia_pix_enviada', 'Transferencia enviada pelo Pix - UBER DO BRASIL TECNOLOGIA', 5, null::uuid),
    ('30', '2026-01-18'::date, 'despesa', 'Pasteltop', 14.00, 'debito', 'compra_debito', 'Compra no debito - MP *PASTELTOP', 5, null::uuid),
    ('31', '2026-01-22'::date, 'despesa', 'Uber', 0.80, 'pix', 'transferencia_pix_enviada', 'Transferencia enviada pelo Pix - UBER DO BRASIL TECNOLOGIA', 5, null::uuid),
    ('32', '2026-01-24'::date, 'despesa', 'Uber', 18.98, 'pix', 'transferencia_pix_enviada', 'Transferencia enviada pelo Pix - UBER DO BRASIL TECNOLOGIA', 5, null::uuid),
    ('33', '2026-01-28'::date, 'receita', 'Transferencia recebida - Banco Inter', 100.00, 'pix', 'transferencia_recebida_conta_propria', 'Transferencia recebida pelo Pix - FILIPE BODDENBERG RIBEIRO - BANCO INTER', 6, null::uuid),
    ('34', '2026-01-28'::date, 'receita', 'Reembolso Uber', 0.01, 'pix', 'reembolso_pix', 'Reembolso recebido pelo Pix - UBER DO BRASIL TECNOLOGIA', 6, null::uuid),
    ('35', '2026-01-28'::date, 'despesa', 'Spotify', 31.90, 'debito', 'compra_debito', 'Compra no debito - EBN*SPOTIFY', 6, null::uuid),
    ('36', '2026-01-28'::date, 'despesa', 'Uber', 34.95, 'pix', 'transferencia_pix_enviada', 'Transferencia enviada pelo Pix - UBER DO BRASIL TECNOLOGIA', 6, null::uuid),
    ('37', '2026-01-28'::date, 'despesa', 'Lanchonete Tradicao', 10.89, 'debito', 'compra_debito', 'Compra no debito - LANCHONETE TRADICAO DO', 6, null::uuid),
    ('38', '2026-01-30'::date, 'despesa', 'Pastel de Feira', 14.00, 'debito', 'compra_debito', 'Compra no debito - MP *PASTELDEFEIRA', 6, null::uuid),
    ('39', '2026-01-30'::date, 'despesa', 'Kiwify', 17.00, 'pix', 'transferencia_pix_enviada', 'Transferencia enviada pelo Pix - Kiwify', 6, null::uuid)
)
insert into public.movimentacoes (
  id, usuario_id, conta_id, conta_destino_id, categoria_id, natureza,
  descricao, valor, data_movimentacao, mes_competencia, status,
  forma_pagamento, origem, observacoes, metadados, confirmado_por_usuario
)
select
  (md5('financas:mov:nubank:filipe:2026-01:' || dados.chave))::uuid,
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
  '2026-01-01'::date,
  'confirmada',
  dados.forma_pagamento,
  'extrato',
  dados.descricao_original || ' - valor no extrato R$ ' ||
    case when dados.natureza = 'receita' then '' else '-' end ||
    to_char(dados.valor, 'FM999999990.00') || '. Extrato Nubank de 2026-01.',
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
    'periodo_extrato', '2026-01',
    'arquivo_origem', 'NU_174839302_01JAN2026_31JAN2026.pdf',
    'arquivo_sha256', 'a2cf01bbc6c3d37a0eb0dfec2491c971657c1965ef2e225961b4ea9dcbc04205',
    'pagina_pdf', dados.pagina_pdf,
    'ordem_pdf', dados.chave::integer,
    'importacao_lote', 'nubank-filipe-2026-01',
    'projetada_pela_ia', false
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
  select count(*)
  into quantidade_novos
  from public.movimentacoes
  where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
    and metadados ->> 'importacao_lote' = 'nubank-filipe-2026-01';

  if quantidade_novos <> 39 then
    raise exception 'Extrato Nubank de janeiro incompleto: esperados 39 novos lancamentos, encontrados %.', quantidade_novos;
  end if;

  select count(*)
  into quantidade_contrapartidas
  from public.movimentacoes
  where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
    and metadados ? 'contrapartida_nubank'
    and metadados -> 'contrapartida_nubank' ->> 'arquivo_sha256' = 'a2cf01bbc6c3d37a0eb0dfec2491c971657c1965ef2e225961b4ea9dcbc04205';

  if quantidade_contrapartidas <> 5 then
    raise exception 'Contrapartidas Nubank incorretas: esperadas 5, encontradas %.', quantidade_contrapartidas;
  end if;

  with movimentos as (
    select *
    from public.movimentacoes
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and (
        metadados ->> 'importacao_lote' = 'nubank-filipe-2026-01'
        or (
          metadados ? 'contrapartida_nubank'
          and metadados -> 'contrapartida_nubank' ->> 'arquivo_sha256' = 'a2cf01bbc6c3d37a0eb0dfec2491c971657c1965ef2e225961b4ea9dcbc04205'
        )
      )
  )
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
  from movimentos;

  if entradas <> 5293.02 or saidas <> 5301.40 then
    raise exception 'Totais Nubank de janeiro divergentes: entradas %, saidas %.', entradas, saidas;
  end if;

  if 10.37 + entradas - saidas <> 1.99 then
    raise exception 'Saldo final Nubank de janeiro nao confere.';
  end if;

  if exists (
    select 1
    from public.movimentacoes
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and metadados ->> 'importacao_lote' = 'nubank-filipe-2026-01'
      and mes_competencia <> '2026-01-01'::date
  ) then
    raise exception 'O extrato Nubank de janeiro alterou outro mes.';
  end if;

  if (
    select count(*)
    from public.linhas_grupos_panorama
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and grupo_id = (md5('financas:grupo:extrato-nubank:filipe'))::uuid
  ) <> 2 then
    raise exception 'As linhas do Extrato Nubank nao ficaram no grupo proprio.';
  end if;
end;
$$;

commit;
