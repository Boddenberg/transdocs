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

update public.movimentacoes
set conta_id = (md5('financas:conta:extrato-nubank:filipe'))::uuid,
    observacoes = concat_ws(' ', observacoes, 'Contrapartida no Nubank em 06/02/2026.'),
    metadados = metadados || jsonb_build_object(
      'contrapartida_nubank', jsonb_build_object(
        'arquivo', 'NU_174839302_01FEV2026_28FEV2026.pdf',
        'arquivo_sha256', '738b31e1a9ed1f87fb246429c9ca526f638ff4a46b8ace56f16a72f9eacce7da',
        'pagina', 1, 'data_movimentacao', '2026-02-06',
        'descricao_original', 'Transferencia enviada pelo Pix - Filipe Boddenberg Ribeiro - Itau'
      )
    )
where id = 'b12876f7-7195-533c-8d06-d987bc39475f'::uuid
  and usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
  and conta_id = 'bbe5ac59-d57f-5149-842e-e4163f9bd0e2'::uuid
  and conta_destino_id = 'd64bb1b6-1140-5470-8695-7aadce45262c'::uuid
  and valor = 4700.00;

with dados (
  chave, data_movimentacao, natureza, descricao, valor, forma_pagamento,
  tipo_lancamento, descricao_original, pagina_pdf
) as (
  values
    ('01', '2026-02-06'::date, 'receita', 'Booking.com', 4738.41, 'transferencia', 'transferencia_recebida', 'Transferencia Recebida - BOOKING.COM BRASIL SERVICOS DE RESERVA DE HOTEIS', 1),
    ('02', '2026-02-14'::date, 'despesa', 'Dracoins', 26.70, 'pix', 'transferencia_pix_enviada', 'Transferencia enviada pelo Pix - DRACOINS', 1),
    ('03', '2026-02-20'::date, 'receita', 'Transferencia recebida - Leonardo Santos', 69.60, 'pix', 'transferencia_recebida', 'Transferencia recebida pelo Pix - LEONARDO SANTOS DA CONCEICAO', 1),
    ('04', '2026-02-21'::date, 'receita', 'Transferencia recebida - Iago Rodrigues', 116.00, 'pix', 'transferencia_recebida', 'Transferencia recebida pelo Pix - IAGO RODRIGUES DOS SANTOS', 2),
    ('05', '2026-02-24'::date, 'despesa', 'Spotify', 31.90, 'debito', 'compra_debito', 'Compra no debito - EBN*SPOTIFY', 2),
    ('06', '2026-02-24'::date, 'despesa', 'iFood', 99.69, 'pix', 'transferencia_pix_enviada', 'Transferencia enviada pelo Pix - IFOOD.COM AGENCIA DE RESTAURANTES ONLINE', 2),
    ('07', '2026-02-26'::date, 'despesa', 'Uber', 42.15, 'pix', 'transferencia_pix_enviada', 'Transferencia enviada pelo Pix - UBER DO BRASIL TECNOLOGIA LTDA', 2)
)
insert into public.movimentacoes (
  id, usuario_id, conta_id, conta_destino_id, categoria_id, natureza,
  descricao, valor, data_movimentacao, mes_competencia, status,
  forma_pagamento, origem, observacoes, metadados, confirmado_por_usuario
)
select
  (md5('financas:mov:nubank:filipe:2026-02:' || dados.chave))::uuid,
  'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid,
  (md5('financas:conta:extrato-nubank:filipe'))::uuid,
  null::uuid,
  (md5('financas:categoria:extrato-nubank:filipe'))::uuid,
  dados.natureza, dados.descricao, dados.valor, dados.data_movimentacao,
  '2026-02-01'::date, 'confirmada', dados.forma_pagamento, 'extrato',
  dados.descricao_original || ' - valor no extrato R$ ' ||
    case when dados.natureza = 'receita' then '' else '-' end ||
    to_char(dados.valor, 'FM999999990.00') || '. Extrato Nubank de 2026-02.',
  jsonb_build_object(
    'instituicao', 'Nubank', 'tipo_documento', 'extrato_conta',
    'agencia', '0001', 'conta_extrato', '17483930-2',
    'tipo_lancamento', dados.tipo_lancamento,
    'descricao_original', dados.descricao_original,
    'valor_assinado', case when dados.natureza = 'receita'
      then to_char(dados.valor, 'FM999999990.00')
      else '-' || to_char(dados.valor, 'FM999999990.00') end,
    'saldo_inicial_periodo', '1.99', 'saldo_final_periodo', '25.56',
    'periodo_extrato', '2026-02',
    'arquivo_origem', 'NU_174839302_01FEV2026_28FEV2026.pdf',
    'arquivo_sha256', '738b31e1a9ed1f87fb246429c9ca526f638ff4a46b8ace56f16a72f9eacce7da',
    'pagina_pdf', dados.pagina_pdf, 'ordem_pdf', dados.chave::integer,
    'importacao_lote', 'nubank-filipe-2026-02', 'projetada_pela_ia', false
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
  select count(*) into quantidade
  from public.movimentacoes
  where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
    and metadados ->> 'importacao_lote' = 'nubank-filipe-2026-02';

  if quantidade <> 7 then
    raise exception 'Extrato Nubank de fevereiro incompleto: esperados 7 novos lancamentos, encontrados %.', quantidade;
  end if;

  with movimentos as (
    select * from public.movimentacoes
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and (
        metadados ->> 'importacao_lote' = 'nubank-filipe-2026-02'
        or metadados -> 'contrapartida_nubank' ->> 'arquivo_sha256' = '738b31e1a9ed1f87fb246429c9ca526f638ff4a46b8ace56f16a72f9eacce7da'
      )
  )
  select
    sum(case when natureza = 'receita' and conta_id = (md5('financas:conta:extrato-nubank:filipe'))::uuid then valor
             when natureza = 'transferencia' and conta_destino_id = (md5('financas:conta:extrato-nubank:filipe'))::uuid then valor else 0 end),
    sum(case when natureza = 'despesa' and conta_id = (md5('financas:conta:extrato-nubank:filipe'))::uuid then valor
             when natureza = 'transferencia' and conta_id = (md5('financas:conta:extrato-nubank:filipe'))::uuid then valor else 0 end)
  into entradas, saidas from movimentos;

  if entradas <> 4924.01 or saidas <> 4900.44 or 1.99 + entradas - saidas <> 25.56 then
    raise exception 'Totais ou saldo do Nubank de fevereiro nao conferem.';
  end if;

  if exists (
    select 1 from public.movimentacoes
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and metadados ->> 'importacao_lote' = 'nubank-filipe-2026-02'
      and mes_competencia <> '2026-02-01'::date
  ) then
    raise exception 'O extrato Nubank de fevereiro alterou outro mes.';
  end if;
end;
$$;

commit;
