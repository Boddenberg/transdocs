begin;

-- Importacao auditavel somente de janeiro e junho de 2026 do extrato
-- consolidado do Banco Inter do Filipe. O usuario confirmou o cadastro.
do $$
begin
  if not exists (
    select 1
    from public.perfis
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and lower(coalesce(nome, '')) like '%filipe%'
  ) then
    raise exception 'Perfil do Filipe nao encontrado; importacao Inter cancelada.';
  end if;

  if exists (
    select 1
    from public.contas
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and lower(nome) = lower('Extrato Inter')
      and id <> (md5('financas:conta:extrato-inter:filipe'))::uuid
  ) then
    raise exception 'Ja existe outra conta chamada Extrato Inter; importacao cancelada.';
  end if;

  if exists (
    select 1
    from public.categorias
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and lower(nome) = lower('Extrato Inter')
      and id <> (md5('financas:categoria:extrato-inter:filipe'))::uuid
  ) then
    raise exception 'Ja existe outra categoria chamada Extrato Inter; importacao cancelada.';
  end if;

  if exists (
    select 1
    from public.grupos_fontes_panorama
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and lower(nome) = lower('Extrato Inter')
      and id <> (md5('financas:grupo:extrato-inter:filipe'))::uuid
  ) then
    raise exception 'Ja existe outro grupo chamado Extrato Inter; importacao cancelada.';
  end if;

  if exists (
    select 1
    from public.movimentacoes
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and metadados ->> 'importacao_lote' = 'inter-filipe-2026-01-e-06'
  ) then
    raise exception 'O extrato Inter ja possui lancamentos; importacao cancelada.';
  end if;

  if not exists (
    select 1 from public.contas
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and id in (
        'd64bb1b6-1140-5470-8695-7aadce45262c'::uuid,
        (md5('financas:conta:extrato-nubank:filipe'))::uuid
      )
    group by usuario_id
    having count(*) = 2
  ) then
    raise exception 'Contas de contrapartida do Inter nao foram encontradas; importacao cancelada.';
  end if;
end;
$$;

insert into public.contas (
  id, usuario_id, nome, tipo, instituicao, cor, saldo_inicial,
  data_saldo_inicial, incluir_no_patrimonio, ativa
)
values (
  (md5('financas:conta:extrato-inter:filipe'))::uuid,
  'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid,
  'Extrato Inter', 'conta_corrente', 'Banco Inter', '#FF7A00', 0,
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
  (md5('financas:categoria:extrato-inter:filipe'))::uuid,
  'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid,
  'Extrato Inter', 'ambos', 'landmark', '#FF7A00', false, true
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
  (md5('financas:grupo:extrato-inter:filipe'))::uuid,
  'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid,
  'Extrato Inter', 5, false
)
on conflict (id) do update
set nome = excluded.nome,
    ordem = excluded.ordem,
    recolhido = excluded.recolhido;

insert into public.fontes_grupos_panorama (
  id, usuario_id, grupo_id, fonte_tipo, fonte_id, ordem
)
values (
  (md5('financas:fonte-grupo:extrato-inter:filipe'))::uuid,
  'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid,
  (md5('financas:grupo:extrato-inter:filipe'))::uuid,
  'conta', (md5('financas:conta:extrato-inter:filipe'))::uuid, 0
)
on conflict (usuario_id, fonte_tipo, fonte_id) do update
set grupo_id = excluded.grupo_id,
    ordem = excluded.ordem;

insert into public.linhas_grupos_panorama (
  id, usuario_id, grupo_id, fonte_chave, ordem
)
values
  (
    (md5('financas:linha-grupo:extrato-inter:entradas:filipe'))::uuid,
    'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid,
    (md5('financas:grupo:extrato-inter:filipe'))::uuid,
    'entradas:categoria:' || (md5('financas:categoria:extrato-inter:filipe'))::uuid::text, 0
  ),
  (
    (md5('financas:linha-grupo:extrato-inter:despesas:filipe'))::uuid,
    'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid,
    (md5('financas:grupo:extrato-inter:filipe'))::uuid,
    'despesas_variaveis:categoria:' || (md5('financas:categoria:extrato-inter:filipe'))::uuid::text, 1
  )
on conflict (usuario_id, fonte_chave) do update
set grupo_id = excluded.grupo_id,
    ordem = excluded.ordem;

-- Reutiliza a transferencia de R$ 4.400 ja registrada no extrato Itau.
update public.movimentacoes
set conta_destino_id = (md5('financas:conta:extrato-inter:filipe'))::uuid,
    observacoes = concat_ws(' ', observacoes, 'Contrapartida no Banco Inter em 02/01/2026.'),
    metadados = metadados || jsonb_build_object(
      'contrapartida_inter', jsonb_build_object(
        'arquivo', 'Extrato-01-01-2026-a-22-07-2026-PDF.pdf',
        'arquivo_sha256', 'b8eafb6c75d52185c4de372391d492a0b4ad61963479278ab44633e373fa6818',
        'pagina', 1, 'data_movimentacao', '2026-01-02',
        'descricao_original', 'Pix recebido - FILIPE BODDENBERG RIBEIRO'
      )
    )
where id = 'acc77281-a279-5e45-b0cb-b3afdb7e3581'::uuid
  and usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
  and conta_id = 'd64bb1b6-1140-5470-8695-7aadce45262c'::uuid
  and conta_destino_id = 'bbe5ac59-d57f-5149-842e-e4163f9bd0e2'::uuid
  and valor = 4400.00;

-- Converte a entrada Nubank de R$ 100 em uma unica transferencia Inter -> Nubank.
update public.movimentacoes
set conta_id = (md5('financas:conta:extrato-inter:filipe'))::uuid,
    conta_destino_id = (md5('financas:conta:extrato-nubank:filipe'))::uuid,
    categoria_id = null,
    natureza = 'transferencia',
    descricao = 'Transferencia entre contas do Inter para o Nubank',
    forma_pagamento = 'pix',
    observacoes = concat_ws(' ', observacoes, 'Contrapartida no Banco Inter em 28/01/2026.'),
    metadados = metadados || jsonb_build_object(
      'tipo_lancamento', 'transferencia_entre_contas',
      'contrapartida_inter', jsonb_build_object(
        'arquivo', 'Extrato-01-01-2026-a-22-07-2026-PDF.pdf',
        'arquivo_sha256', 'b8eafb6c75d52185c4de372391d492a0b4ad61963479278ab44633e373fa6818',
        'pagina', 2, 'data_movimentacao', '2026-01-28',
        'descricao_original', 'Pix enviado - Filipe Boddenberg Ribeiro'
      )
    )
where id = (md5('financas:mov:nubank:filipe:2026-01:33'))::uuid
  and usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
  and conta_id = (md5('financas:conta:extrato-nubank:filipe'))::uuid
  and conta_destino_id is null
  and natureza = 'receita'
  and valor = 100.00;

-- Reutiliza a transferencia de R$ 1.500 ja registrada no extrato Itau.
update public.movimentacoes
set conta_id = (md5('financas:conta:extrato-inter:filipe'))::uuid,
    observacoes = concat_ws(' ', observacoes, 'Contrapartida no Banco Inter em 13/06/2026.'),
    metadados = metadados || jsonb_build_object(
      'contrapartida_inter', jsonb_build_object(
        'arquivo', 'Extrato-01-01-2026-a-22-07-2026-PDF.pdf',
        'arquivo_sha256', 'b8eafb6c75d52185c4de372391d492a0b4ad61963479278ab44633e373fa6818',
        'pagina', 6, 'data_movimentacao', '2026-06-13',
        'descricao_original', 'Pix enviado - Filipe Boddenberg Ribeiro'
      )
    )
where id = 'e4ecae49-f6cb-598c-b168-3be0486250c8'::uuid
  and usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
  and conta_id = 'bbe5ac59-d57f-5149-842e-e4163f9bd0e2'::uuid
  and conta_destino_id = 'd64bb1b6-1140-5470-8695-7aadce45262c'::uuid
  and valor = 1500.00;

with dados (
  chave, data_movimentacao, mes_competencia, natureza, descricao, valor,
  forma_pagamento, tipo_lancamento, descricao_original, pagina_pdf,
  saldo_inicial_periodo, saldo_final_periodo
) as (
  values
    ('J01', '2026-01-02'::date, '2026-01-01'::date, 'despesa', 'Pix - Celio Ribeiro Boucas', 2200.00, 'pix', 'pix_enviado', 'Pix enviado - Celio Ribeiro Boucas', 1, '0.00', '42.04'),
    ('J02', '2026-01-02'::date, '2026-01-01'::date, 'despesa', 'Pix - Thiago Boddenberg Ribeiro', 2200.00, 'pix', 'pix_enviado', 'Pix enviado - Thiago Boddenberg Ribeiro', 1, '0.00', '42.04'),
    ('J03', '2026-01-07'::date, '2026-01-01'::date, 'receita', 'Booking.com', 2238.71, 'transferencia', 'pix_recebido', 'Pix recebido - BOOKING COM BRASIL SERVICOS DE RESERVA DE HOTEIS LTDA', 1, '0.00', '42.04'),
    ('J04', '2026-01-15'::date, '2026-01-01'::date, 'despesa', 'Bosforo Alimentacao', 146.69, 'debito', 'compra_debito', 'Compra no debito - IFD*BOSFORO ALIMENTACA', 1, '0.00', '42.04'),
    ('J05', '2026-01-15'::date, '2026-01-01'::date, 'despesa', 'iFood Club', 13.90, 'debito', 'compra_debito', 'Compra no debito - IFD*IFOOD CLUB', 1, '0.00', '42.04'),
    ('J06', '2026-01-15'::date, '2026-01-01'::date, 'despesa', 'Pagamento Banco Santander', 439.23, 'boleto', 'pagamento_efetuado', 'Pagamento efetuado - BANCO SANTANDER (BRASIL) S.A.', 1, '0.00', '42.04'),
    ('J07', '2026-01-16'::date, '2026-01-01'::date, 'despesa', 'Pix - Victor Ellyvan Campagnola', 700.00, 'pix', 'pix_enviado', 'Pix enviado - Victor Ellyvan Campagnola', 1, '0.00', '42.04'),
    ('J08', '2026-01-16'::date, '2026-01-01'::date, 'despesa', 'Pix - Victor Ellyvan Campagnola', 69.00, 'pix', 'pix_enviado', 'Pix enviado - Victor Ellyvan Campagnola', 1, '0.00', '42.04'),
    ('J09', '2026-01-16'::date, '2026-01-01'::date, 'despesa', 'Vegsim', 112.71, 'debito', 'compra_debito', 'Compra no debito - IFD*VEGSIM LTDA', 1, '0.00', '42.04'),
    ('J10', '2026-01-19'::date, '2026-01-01'::date, 'despesa', 'Mercado Extra', 160.21, 'debito', 'compra_debito', 'Compra no debito - MERCADO EXTRA-1769', 1, '0.00', '42.04'),
    ('J11', '2026-01-19'::date, '2026-01-01'::date, 'despesa', 'Pix - Paulo Henrique Cabrera', 110.00, 'pix', 'pix_enviado', 'Pix enviado - PAULO HENRIQUE CABRERA', 1, '0.00', '42.04'),
    ('J12', '2026-01-20'::date, '2026-01-01'::date, 'despesa', 'Smart Fit', 149.90, 'debito', 'compra_debito', 'Compra no debito - SMARTFIT ESCOLA DE GI', 1, '0.00', '42.04'),
    ('J13', '2026-01-20'::date, '2026-01-01'::date, 'receita', 'Credito Banco Inter', 897.20, 'pix', 'pix_recebido', 'Pix recebido - 00019 260762326 BANCO INTER SA', 1, '0.00', '42.04'),
    ('J14', '2026-01-20'::date, '2026-01-01'::date, 'despesa', 'Dracoins', 151.30, 'pix', 'pix_enviado', 'Pix enviado - DRACOINS', 1, '0.00', '42.04'),
    ('J15', '2026-01-21'::date, '2026-01-01'::date, 'despesa', 'Braz Quintal', 124.00, 'debito', 'compra_debito', 'Compra no debito - BRAZ QUINTAL', 1, '0.00', '42.04'),
    ('J16', '2026-01-21'::date, '2026-01-01'::date, 'despesa', 'Uber', 34.93, 'pix', 'pix_enviado', 'Pix enviado - UBER DO BRASIL TECNOLOGIA LTDA', 1, '0.00', '42.04'),
    ('J17', '2026-01-22'::date, '2026-01-01'::date, 'despesa', 'Dionisio', 21.00, 'debito', 'compra_debito', 'Compra no debito - MP *DIONISIO', 2, '0.00', '42.04'),
    ('J18', '2026-01-22'::date, '2026-01-01'::date, 'despesa', 'Uber', 36.93, 'pix', 'pix_enviado', 'Pix enviado - UBER DO BRASIL TECNOLOGIA LTDA', 2, '0.00', '42.04'),
    ('J19', '2026-01-22'::date, '2026-01-01'::date, 'despesa', 'Uber', 54.98, 'pix', 'pix_enviado', 'Pix enviado - UBER DO BRASIL TECNOLOGIA LTDA', 2, '0.00', '42.04'),
    ('J20', '2026-01-24'::date, '2026-01-01'::date, 'despesa', 'Swift', 363.81, 'debito', 'compra_debito', 'Compra no debito - SWIFT CHACARA ST. AN', 2, '0.00', '42.04'),
    ('J21', '2026-01-24'::date, '2026-01-01'::date, 'despesa', 'Factory Games', 30.00, 'pix', 'pix_enviado', 'Pix enviado - FACTORY GAMES LTDA', 2, '0.00', '42.04'),
    ('J22', '2026-01-25'::date, '2026-01-01'::date, 'despesa', 'Factory Games', 30.00, 'pix', 'pix_enviado', 'Pix enviado - FACTORY GAMES LTDA', 2, '0.00', '42.04'),
    ('J23', '2026-01-25'::date, '2026-01-01'::date, 'despesa', 'C&A', 56.35, 'debito', 'compra_debito', 'Compra no debito - CEA MRB 140 ECPC', 2, '0.00', '42.04'),
    ('J24', '2026-01-25'::date, '2026-01-01'::date, 'despesa', 'Auto Posto Carlu', 13.99, 'debito', 'compra_debito', 'Compra no debito - AUTO POSTO CARLU', 2, '0.00', '42.04'),
    ('J25', '2026-01-25'::date, '2026-01-01'::date, 'despesa', 'Factory Games', 30.00, 'pix', 'pix_enviado', 'Pix enviado - FACTORY GAMES LTDA', 2, '0.00', '42.04'),
    ('J26', '2026-01-26'::date, '2026-01-01'::date, 'despesa', 'Dionisio', 26.00, 'debito', 'compra_debito', 'Compra no debito - MP *DIONISIO', 2, '0.00', '42.04'),
    ('J27', '2026-01-27'::date, '2026-01-01'::date, 'despesa', 'Factory Games', 50.00, 'pix', 'pix_enviado', 'Pix enviado - FACTORY GAMES LTDA', 2, '0.00', '42.04'),
    ('J28', '2026-01-28'::date, '2026-01-01'::date, 'despesa', 'Factory Games', 30.00, 'pix', 'pix_enviado', 'Pix enviado - FACTORY GAMES LTDA', 2, '0.00', '42.04'),
    ('J29', '2026-01-29'::date, '2026-01-01'::date, 'despesa', 'Uber', 38.94, 'pix', 'pix_enviado', 'Pix enviado - UBER DO BRASIL TECNOLOGIA LTDA', 2, '0.00', '42.04'),
    ('U01', '2026-06-01'::date, '2026-06-01'::date, 'receita', 'Booking.com', 890.01, 'transferencia', 'transferencia_recebida', 'Transferencia recebida - BOOKING.COM BRASIL SERVICOS DE RESERVA', 6, '9.25', '703.56'),
    ('U02', '2026-06-01'::date, '2026-06-01'::date, 'receita', 'Booking.com', 1666.21, 'transferencia', 'transferencia_recebida', 'Transferencia recebida - BOOKING.COM BRASIL SERVICOS DE RESERVA', 6, '9.25', '703.56'),
    ('U03', '2026-06-14'::date, '2026-06-01'::date, 'despesa', 'Pix - Norma Lottenberg Semer', 240.00, 'pix', 'pix_enviado', 'Pix enviado - Norma Lottenberg Semer', 6, '9.25', '703.56'),
    ('U04', '2026-06-18'::date, '2026-06-01'::date, 'despesa', 'Pagamento Banco Santander', 439.23, 'boleto', 'pagamento_efetuado', 'Pagamento efetuado - BANCO SANTANDER (BRASIL) S.A.', 6, '9.25', '703.56'),
    ('U05', '2026-06-18'::date, '2026-06-01'::date, 'receita', 'Credito Banco Inter', 801.75, 'pix', 'pix_recebido', 'Pix recebido - 00019 260761460 BANCO INTER SA', 6, '9.25', '703.56'),
    ('U06', '2026-06-19'::date, '2026-06-01'::date, 'despesa', 'Rei dos Coins', 87.45, 'pix', 'pix_enviado', 'Pix enviado - REI DOS COINS', 6, '9.25', '703.56'),
    ('U07', '2026-06-20'::date, '2026-06-01'::date, 'despesa', 'Smart Fit', 149.90, 'debito', 'compra_debito', 'Compra no debito - SMARTFIT ESCOLA DE GI', 6, '9.25', '703.56'),
    ('U08', '2026-06-23'::date, '2026-06-01'::date, 'despesa', 'Rei dos Coins', 247.08, 'pix', 'pix_enviado', 'Pix enviado - REI DOS COINS', 6, '9.25', '703.56')
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
  dados.natureza,
  dados.descricao,
  dados.valor,
  dados.data_movimentacao,
  dados.mes_competencia,
  'confirmada',
  dados.forma_pagamento,
  'extrato',
  dados.descricao_original || ' - valor no extrato R$ ' ||
    case when dados.natureza = 'receita' then '' else '-' end ||
    to_char(dados.valor, 'FM999999990.00') || '. Extrato Banco Inter de ' ||
    to_char(dados.mes_competencia, 'YYYY-MM') || '.',
  jsonb_build_object(
    'instituicao', 'Banco Inter',
    'tipo_documento', 'extrato_conta',
    'agencia', '0001-9',
    'conta_extrato', '15070262-0',
    'tipo_lancamento', dados.tipo_lancamento,
    'descricao_original', dados.descricao_original,
    'valor_assinado', case
      when dados.natureza = 'receita' then to_char(dados.valor, 'FM999999990.00')
      else '-' || to_char(dados.valor, 'FM999999990.00')
    end,
    'saldo_inicial_periodo', dados.saldo_inicial_periodo,
    'saldo_final_periodo', dados.saldo_final_periodo,
    'periodo_extrato', to_char(dados.mes_competencia, 'YYYY-MM'),
    'arquivo_origem', 'Extrato-01-01-2026-a-22-07-2026-PDF.pdf',
    'arquivo_sha256', 'b8eafb6c75d52185c4de372391d492a0b4ad61963479278ab44633e373fa6818',
    'pagina_pdf', dados.pagina_pdf,
    'ordem_pdf', dados.chave,
    'importacao_lote', 'inter-filipe-2026-01-e-06',
    'projetada_pela_ia', false
  ),
  true
from dados
on conflict (id) do nothing;

do $$
declare
  quantidade_novos integer;
  quantidade_contrapartidas integer;
begin
  select count(*)
  into quantidade_novos
  from public.movimentacoes
  where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
    and metadados ->> 'importacao_lote' = 'inter-filipe-2026-01-e-06';

  if quantidade_novos <> 37 then
    raise exception 'Extrato Inter incompleto: esperados 37 novos lancamentos, encontrados %.', quantidade_novos;
  end if;

  select count(*)
  into quantidade_contrapartidas
  from public.movimentacoes
  where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
    and metadados ? 'contrapartida_inter'
    and metadados -> 'contrapartida_inter' ->> 'arquivo_sha256' = 'b8eafb6c75d52185c4de372391d492a0b4ad61963479278ab44633e373fa6818';

  if quantidade_contrapartidas <> 3 then
    raise exception 'Contrapartidas Inter incorretas: esperadas 3, encontradas %.', quantidade_contrapartidas;
  end if;

  if exists (
    select 1
    from public.movimentacoes
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and metadados ->> 'importacao_lote' = 'inter-filipe-2026-01-e-06'
      and mes_competencia not in ('2026-01-01'::date, '2026-06-01'::date)
  ) then
    raise exception 'O extrato Inter alterou um mes diferente de janeiro ou junho de 2026.';
  end if;

  if exists (
    with movimentos as (
      select *
      from public.movimentacoes
      where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
        and (
          metadados ->> 'importacao_lote' = 'inter-filipe-2026-01-e-06'
          or (
            metadados ? 'contrapartida_inter'
            and metadados -> 'contrapartida_inter' ->> 'arquivo_sha256' = 'b8eafb6c75d52185c4de372391d492a0b4ad61963479278ab44633e373fa6818'
          )
        )
    ),
    apurados as (
      select
        mes_competencia,
        sum(case
          when natureza = 'receita' and conta_id = (md5('financas:conta:extrato-inter:filipe'))::uuid then valor
          when natureza = 'transferencia' and conta_destino_id = (md5('financas:conta:extrato-inter:filipe'))::uuid then valor
          else 0
        end)::numeric as entradas,
        sum(case
          when natureza = 'despesa' and conta_id = (md5('financas:conta:extrato-inter:filipe'))::uuid then valor
          when natureza = 'transferencia' and conta_id = (md5('financas:conta:extrato-inter:filipe'))::uuid then valor
          else 0
        end)::numeric as saidas
      from movimentos
      group by mes_competencia
    ),
    esperados (mes_competencia, entradas, saidas) as (
      values
        ('2026-01-01'::date, 7535.91::numeric, 7493.87::numeric),
        ('2026-06-01'::date, 3357.97::numeric, 2663.66::numeric)
    )
    select 1
    from esperados e
    full join apurados a using (mes_competencia)
    where e.entradas is distinct from a.entradas
       or e.saidas is distinct from a.saidas
  ) then
    raise exception 'Os totais de janeiro ou junho do Banco Inter nao conferem.';
  end if;

  if 0.00 + 7535.91 - 7493.87 <> 42.04 then
    raise exception 'Saldo final Inter de janeiro nao confere.';
  end if;

  if 9.25 + 3357.97 - 2663.66 <> 703.56 then
    raise exception 'Saldo final Inter de junho nao confere.';
  end if;

  if (
    select count(*)
    from public.linhas_grupos_panorama
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and grupo_id = (md5('financas:grupo:extrato-inter:filipe'))::uuid
  ) <> 2 then
    raise exception 'As linhas do Extrato Inter nao ficaram no grupo proprio.';
  end if;
end;
$$;

commit;
