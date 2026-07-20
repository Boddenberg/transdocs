begin;

-- Importacao auditavel das faturas historicas do cartao Mercado Pago final 9260,
-- com competencias de marco a junho de 2026. Pagamentos de fatura foram
-- deliberadamente ignorados para nao duplicar as despesas de cada compra.
-- Parcelas anteriores reutilizam os mesmos grupos das parcelas futuras ja cadastradas.
do $$
begin
  if not exists (
    select 1 from public.perfis
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and lower(coalesce(nome, '')) like '%filipe%'
  ) then
    raise exception 'Perfil do Filipe nao encontrado; importacao cancelada.';
  end if;

  if not exists (
    select 1
    from public.cartoes_credito
    where id = '8de14ef4-91ad-43ec-a238-cf81665b7330'::uuid
      and usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and conta_id = 'd33d76b9-5f1b-436c-aec1-2f7270a863e6'::uuid
  ) then
    raise exception 'Cartao Mercado Pago esperado nao encontrado; importacao cancelada.';
  end if;

  if not exists (
    select 1 from public.movimentacoes
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and grupo_parcelas_id = '72e8a1bf-7738-42f2-be1e-4a5529042dd3'::uuid
      and parcela_numero = 5 and parcelas_total = 8 and valor = 33.68
  ) or not exists (
    select 1 from public.movimentacoes
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and grupo_parcelas_id = '194d0607-89c8-4642-b5d2-75e92967c1ad'::uuid
      and parcela_numero = 5 and parcelas_total = 12 and valor = 92.01
  ) or not exists (
    select 1 from public.movimentacoes
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and grupo_parcelas_id = '1de640d0-cb93-49b5-a229-561183c523c6'::uuid
      and parcela_numero = 3 and parcelas_total = 5 and valor = 16.72
  ) or not exists (
    select 1 from public.movimentacoes
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and grupo_parcelas_id = '8c8372d0-e11a-4364-8d24-9f162562e904'::uuid
      and parcela_numero = 2 and parcelas_total = 6 and valor = 57.01
  ) then
    raise exception 'Parcelas futuras de referencia nao conferem; importacao cancelada.';
  end if;

  if exists (
    select 1 from public.movimentacoes
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and conta_id = 'd33d76b9-5f1b-436c-aec1-2f7270a863e6'::uuid
      and (
        (grupo_parcelas_id = '72e8a1bf-7738-42f2-be1e-4a5529042dd3'::uuid and parcela_numero between 1 and 4)
        or (grupo_parcelas_id = '194d0607-89c8-4642-b5d2-75e92967c1ad'::uuid and parcela_numero between 1 and 4)
        or (grupo_parcelas_id = '1de640d0-cb93-49b5-a229-561183c523c6'::uuid and parcela_numero between 1 and 2)
        or (grupo_parcelas_id = '8c8372d0-e11a-4364-8d24-9f162562e904'::uuid and parcela_numero = 1)
      )
  ) then
    raise exception 'Parcelas historicas ja existem; importacao cancelada para evitar duplicidade.';
  end if;
end;
$$;

update public.contas
set nome = U&'Cart\00E3o Mercado Pago', instituicao = 'Mercado Pago'
where id = 'd33d76b9-5f1b-436c-aec1-2f7270a863e6'::uuid
  and usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid;

update public.cartoes_credito
set limite = 1500.00, final_cartao = '9260'
where id = '8de14ef4-91ad-43ec-a238-cf81665b7330'::uuid
  and usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid;

insert into public.movimentacoes (
  id, usuario_id, conta_id, categoria_id, natureza, descricao, valor,
  data_movimentacao, mes_competencia, status, forma_pagamento,
  parcela_numero, parcelas_total, grupo_parcelas_id, origem,
  observacoes, metadados, confirmado_por_usuario
)
values
  ('0749fac5-43f0-5a25-996a-61c1de046f90'::uuid, 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid, 'd33d76b9-5f1b-436c-aec1-2f7270a863e6'::uuid, null::uuid, 'despesa', 'Compra Mercado Livre nao identificada', 33.73, '2026-03-12'::date, '2026-03-01'::date, 'confirmada', 'credito', 1, 8, '72e8a1bf-7738-42f2-be1e-4a5529042dd3'::uuid, 'fatura', '12/03 - MERCADOLIVRE*24PRODUTO - parcela 1 de 8 - R$ 33.73. Fatura Mercado Pago final 9260 com vencimento em 2026-04-06.', $json${"cartao_id":"8de14ef4-91ad-43ec-a238-cf81665b7330","cartao_final":"9260","instituicao":"Mercado Pago","data_compra":"2026-03-12","descricao_original":"MERCADOLIVRE*24PRODUTO","tipo_lancamento":"parcela","fatura_vencimento":"2026-04-06","fatura_competencia":"2026-03-01","fatura_total":"125.76","fatura_consumos":"125.76","fatura_encargos":"0.00","fatura_paga_em":"2026-03-31","arquivo_origem":"mercado pago 1.pdf","arquivo_sha256":"6f0ef10f1e2b3ff23056976e2a3fb0903f459ec32e31dcb484fc77cf0c654b07","pagina_pdf":2,"importacao_lote":"mercado-pago-cartao-filipe-2026-03-a-06","projetada_pela_ia":false}$json$::jsonb, true),
  ('2924a6fe-3bc9-5eed-830b-d7ed563f4d32'::uuid, 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid, 'd33d76b9-5f1b-436c-aec1-2f7270a863e6'::uuid, null::uuid, 'despesa', 'Compra Mercado Livre com 22 itens', 92.03, '2026-03-12'::date, '2026-03-01'::date, 'confirmada', 'credito', 1, 12, '194d0607-89c8-4642-b5d2-75e92967c1ad'::uuid, 'fatura', '12/03 - MERCADOLIVRE*24PRODUTOS - parcela 1 de 12 - R$ 92.03. Fatura Mercado Pago final 9260 com vencimento em 2026-04-06.', $json${"cartao_id":"8de14ef4-91ad-43ec-a238-cf81665b7330","cartao_final":"9260","instituicao":"Mercado Pago","data_compra":"2026-03-12","descricao_original":"MERCADOLIVRE*24PRODUTOS","tipo_lancamento":"parcela","fatura_vencimento":"2026-04-06","fatura_competencia":"2026-03-01","fatura_total":"125.76","fatura_consumos":"125.76","fatura_encargos":"0.00","fatura_paga_em":"2026-03-31","arquivo_origem":"mercado pago 1.pdf","arquivo_sha256":"6f0ef10f1e2b3ff23056976e2a3fb0903f459ec32e31dcb484fc77cf0c654b07","pagina_pdf":2,"importacao_lote":"mercado-pago-cartao-filipe-2026-03-a-06","projetada_pela_ia":false}$json$::jsonb, true),
  ('6a158e88-b6a4-5cfd-a014-749a79d5d1bb'::uuid, 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid, 'd33d76b9-5f1b-436c-aec1-2f7270a863e6'::uuid, null::uuid, 'despesa', 'Compra Mercado Livre nao identificada', 33.68, '2026-03-12'::date, '2026-04-01'::date, 'confirmada', 'credito', 2, 8, '72e8a1bf-7738-42f2-be1e-4a5529042dd3'::uuid, 'fatura', '12/03 - MERCADOLIVRE*24PRODUTO - parcela 2 de 8 - R$ 33.68. Fatura Mercado Pago final 9260 com vencimento em 2026-05-04.', $json${"cartao_id":"8de14ef4-91ad-43ec-a238-cf81665b7330","cartao_final":"9260","instituicao":"Mercado Pago","data_compra":"2026-03-12","descricao_original":"MERCADOLIVRE*24PRODUTO","tipo_lancamento":"parcela","fatura_vencimento":"2026-05-04","fatura_competencia":"2026-04-01","fatura_total":"125.69","fatura_consumos":"125.69","fatura_encargos":"0.00","fatura_paga_em":"2026-05-08","arquivo_origem":"mercado pago 2.pdf","arquivo_sha256":"dba3ff1752919afd5ece3ff40c5ff977b343f32d3dfefb0d39cd7cc4d6099d82","pagina_pdf":2,"importacao_lote":"mercado-pago-cartao-filipe-2026-03-a-06","projetada_pela_ia":false}$json$::jsonb, true),
  ('700c09d9-5c09-5271-bedc-6bd7acf631c1'::uuid, 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid, 'd33d76b9-5f1b-436c-aec1-2f7270a863e6'::uuid, null::uuid, 'despesa', 'Compra Mercado Livre com 22 itens', 92.01, '2026-03-12'::date, '2026-04-01'::date, 'confirmada', 'credito', 2, 12, '194d0607-89c8-4642-b5d2-75e92967c1ad'::uuid, 'fatura', '12/03 - MERCADOLIVRE*24PRODUTOS - parcela 2 de 12 - R$ 92.01. Fatura Mercado Pago final 9260 com vencimento em 2026-05-04.', $json${"cartao_id":"8de14ef4-91ad-43ec-a238-cf81665b7330","cartao_final":"9260","instituicao":"Mercado Pago","data_compra":"2026-03-12","descricao_original":"MERCADOLIVRE*24PRODUTOS","tipo_lancamento":"parcela","fatura_vencimento":"2026-05-04","fatura_competencia":"2026-04-01","fatura_total":"125.69","fatura_consumos":"125.69","fatura_encargos":"0.00","fatura_paga_em":"2026-05-08","arquivo_origem":"mercado pago 2.pdf","arquivo_sha256":"dba3ff1752919afd5ece3ff40c5ff977b343f32d3dfefb0d39cd7cc4d6099d82","pagina_pdf":2,"importacao_lote":"mercado-pago-cartao-filipe-2026-03-a-06","projetada_pela_ia":false}$json$::jsonb, true),
  ('dda0bb58-f840-5c8b-ab85-d48a30845099'::uuid, 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid, 'd33d76b9-5f1b-436c-aec1-2f7270a863e6'::uuid, null::uuid, 'despesa', 'Compra Mercado Livre nao identificada', 33.68, '2026-03-12'::date, '2026-05-01'::date, 'confirmada', 'credito', 3, 8, '72e8a1bf-7738-42f2-be1e-4a5529042dd3'::uuid, 'fatura', '12/03 - MERCADOLIVRE*24PRODUTO - parcela 3 de 8 - R$ 33.68. Fatura Mercado Pago final 9260 com vencimento em 2026-06-08.', $json${"cartao_id":"8de14ef4-91ad-43ec-a238-cf81665b7330","cartao_final":"9260","instituicao":"Mercado Pago","data_compra":"2026-03-12","descricao_original":"MERCADOLIVRE*24PRODUTO","tipo_lancamento":"parcela","fatura_vencimento":"2026-06-08","fatura_competencia":"2026-05-01","fatura_total":"370.66","fatura_consumos":"364.44","fatura_encargos":"6.22","fatura_paga_em":"2026-06-09","arquivo_origem":"mercado pago 3.pdf","arquivo_sha256":"6f86012b3b6bdfaeb78e69b54b4df8a588a1d4c5754171f03a4051a647b61b7f","pagina_pdf":2,"importacao_lote":"mercado-pago-cartao-filipe-2026-03-a-06","projetada_pela_ia":false}$json$::jsonb, true),
  ('c71bbfe3-6100-51ef-8c4b-054b7caf35e8'::uuid, 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid, 'd33d76b9-5f1b-436c-aec1-2f7270a863e6'::uuid, null::uuid, 'despesa', 'Compra Mercado Livre com 22 itens', 92.01, '2026-03-12'::date, '2026-05-01'::date, 'confirmada', 'credito', 3, 12, '194d0607-89c8-4642-b5d2-75e92967c1ad'::uuid, 'fatura', '12/03 - MERCADOLIVRE*24PRODUTOS - parcela 3 de 12 - R$ 92.01. Fatura Mercado Pago final 9260 com vencimento em 2026-06-08.', $json${"cartao_id":"8de14ef4-91ad-43ec-a238-cf81665b7330","cartao_final":"9260","instituicao":"Mercado Pago","data_compra":"2026-03-12","descricao_original":"MERCADOLIVRE*24PRODUTOS","tipo_lancamento":"parcela","fatura_vencimento":"2026-06-08","fatura_competencia":"2026-05-01","fatura_total":"370.66","fatura_consumos":"364.44","fatura_encargos":"6.22","fatura_paga_em":"2026-06-09","arquivo_origem":"mercado pago 3.pdf","arquivo_sha256":"6f86012b3b6bdfaeb78e69b54b4df8a588a1d4c5754171f03a4051a647b61b7f","pagina_pdf":2,"importacao_lote":"mercado-pago-cartao-filipe-2026-03-a-06","projetada_pela_ia":false}$json$::jsonb, true),
  ('dad07ce1-e54f-59a8-9fb1-7659644e23df'::uuid, 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid, 'd33d76b9-5f1b-436c-aec1-2f7270a863e6'::uuid, null::uuid, 'despesa', 'Mercado Livre', 29.04, '2026-05-10'::date, '2026-05-01'::date, 'confirmada', 'credito', null, null, null::uuid, 'fatura', '10/05 - MERCADOLIVRE*MERCADOLIVRE - R$ 29.04. Fatura Mercado Pago final 9260 com vencimento em 2026-06-08.', $json${"cartao_id":"8de14ef4-91ad-43ec-a238-cf81665b7330","cartao_final":"9260","instituicao":"Mercado Pago","data_compra":"2026-05-10","descricao_original":"MERCADOLIVRE*MERCADOLIVRE","tipo_lancamento":"compra","fatura_vencimento":"2026-06-08","fatura_competencia":"2026-05-01","fatura_total":"370.66","fatura_consumos":"364.44","fatura_encargos":"6.22","fatura_paga_em":"2026-06-09","arquivo_origem":"mercado pago 3.pdf","arquivo_sha256":"6f86012b3b6bdfaeb78e69b54b4df8a588a1d4c5754171f03a4051a647b61b7f","pagina_pdf":2,"importacao_lote":"mercado-pago-cartao-filipe-2026-03-a-06","projetada_pela_ia":false}$json$::jsonb, true),
  ('4870e037-7aec-5219-9496-e4c666fc796c'::uuid, 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid, 'd33d76b9-5f1b-436c-aec1-2f7270a863e6'::uuid, null::uuid, 'despesa', 'Mercado Livre', 192.99, '2026-05-12'::date, '2026-05-01'::date, 'confirmada', 'credito', null, null, null::uuid, 'fatura', '12/05 - MERCADOLIVRE*MERCADOLIVRE - R$ 192.99. Fatura Mercado Pago final 9260 com vencimento em 2026-06-08.', $json${"cartao_id":"8de14ef4-91ad-43ec-a238-cf81665b7330","cartao_final":"9260","instituicao":"Mercado Pago","data_compra":"2026-05-12","descricao_original":"MERCADOLIVRE*MERCADOLIVRE","tipo_lancamento":"compra","fatura_vencimento":"2026-06-08","fatura_competencia":"2026-05-01","fatura_total":"370.66","fatura_consumos":"364.44","fatura_encargos":"6.22","fatura_paga_em":"2026-06-09","arquivo_origem":"mercado pago 3.pdf","arquivo_sha256":"6f86012b3b6bdfaeb78e69b54b4df8a588a1d4c5754171f03a4051a647b61b7f","pagina_pdf":2,"importacao_lote":"mercado-pago-cartao-filipe-2026-03-a-06","projetada_pela_ia":false}$json$::jsonb, true),
  ('f9bd0f40-7ab2-5941-9ed7-fedf8c706410'::uuid, 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid, 'd33d76b9-5f1b-436c-aec1-2f7270a863e6'::uuid, null::uuid, 'despesa', 'Kit com 5 molduras A4 tabaco', 16.72, '2026-05-27'::date, '2026-05-01'::date, 'confirmada', 'credito', 1, 5, '1de640d0-cb93-49b5-a229-561183c523c6'::uuid, 'fatura', '27/05 - MERCADOLIVRE*TOQUEPOP - parcela 1 de 5 - R$ 16.72. Fatura Mercado Pago final 9260 com vencimento em 2026-06-08.', $json${"cartao_id":"8de14ef4-91ad-43ec-a238-cf81665b7330","cartao_final":"9260","instituicao":"Mercado Pago","data_compra":"2026-05-27","descricao_original":"MERCADOLIVRE*TOQUEPOP","tipo_lancamento":"parcela","fatura_vencimento":"2026-06-08","fatura_competencia":"2026-05-01","fatura_total":"370.66","fatura_consumos":"364.44","fatura_encargos":"6.22","fatura_paga_em":"2026-06-09","arquivo_origem":"mercado pago 3.pdf","arquivo_sha256":"6f86012b3b6bdfaeb78e69b54b4df8a588a1d4c5754171f03a4051a647b61b7f","pagina_pdf":2,"importacao_lote":"mercado-pago-cartao-filipe-2026-03-a-06","projetada_pela_ia":false}$json$::jsonb, true),
  ('df3d6028-a637-57ce-a82a-11e099e94eac'::uuid, 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid, 'd33d76b9-5f1b-436c-aec1-2f7270a863e6'::uuid, 'b5a0206d-6ffa-46ed-8375-b2f40d06428e'::uuid, 'despesa', 'Juros do rotativo', 3.00, '2026-05-30'::date, '2026-05-01'::date, 'confirmada', 'credito', null, null, null::uuid, 'fatura', '30/05 - Juros do rotativo - R$ 3.00. Fatura Mercado Pago final 9260 com vencimento em 2026-06-08.', $json${"cartao_id":"8de14ef4-91ad-43ec-a238-cf81665b7330","cartao_final":"9260","instituicao":"Mercado Pago","data_compra":"2026-05-30","descricao_original":"Juros do rotativo","tipo_lancamento":"encargo","fatura_vencimento":"2026-06-08","fatura_competencia":"2026-05-01","fatura_total":"370.66","fatura_consumos":"364.44","fatura_encargos":"6.22","fatura_paga_em":"2026-06-09","arquivo_origem":"mercado pago 3.pdf","arquivo_sha256":"6f86012b3b6bdfaeb78e69b54b4df8a588a1d4c5754171f03a4051a647b61b7f","pagina_pdf":2,"importacao_lote":"mercado-pago-cartao-filipe-2026-03-a-06","projetada_pela_ia":false}$json$::jsonb, true),
  ('2c1ceccd-88d0-5bf5-bec7-67cb72a2d617'::uuid, 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid, 'd33d76b9-5f1b-436c-aec1-2f7270a863e6'::uuid, 'b5a0206d-6ffa-46ed-8375-b2f40d06428e'::uuid, 'despesa', 'Multa por atraso', 2.52, '2026-05-30'::date, '2026-05-01'::date, 'confirmada', 'credito', null, null, null::uuid, 'fatura', '30/05 - Multa por atraso - R$ 2.52. Fatura Mercado Pago final 9260 com vencimento em 2026-06-08.', $json${"cartao_id":"8de14ef4-91ad-43ec-a238-cf81665b7330","cartao_final":"9260","instituicao":"Mercado Pago","data_compra":"2026-05-30","descricao_original":"Multa por atraso","tipo_lancamento":"encargo","fatura_vencimento":"2026-06-08","fatura_competencia":"2026-05-01","fatura_total":"370.66","fatura_consumos":"364.44","fatura_encargos":"6.22","fatura_paga_em":"2026-06-09","arquivo_origem":"mercado pago 3.pdf","arquivo_sha256":"6f86012b3b6bdfaeb78e69b54b4df8a588a1d4c5754171f03a4051a647b61b7f","pagina_pdf":2,"importacao_lote":"mercado-pago-cartao-filipe-2026-03-a-06","projetada_pela_ia":false}$json$::jsonb, true),
  ('a198f8e0-4dfa-5d3e-a73d-38014e8c19b4'::uuid, 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid, 'd33d76b9-5f1b-436c-aec1-2f7270a863e6'::uuid, 'b5a0206d-6ffa-46ed-8375-b2f40d06428e'::uuid, 'despesa', 'Juros de mora', 0.17, '2026-05-30'::date, '2026-05-01'::date, 'confirmada', 'credito', null, null, null::uuid, 'fatura', '30/05 - Juros de mora - R$ 0.17. Fatura Mercado Pago final 9260 com vencimento em 2026-06-08.', $json${"cartao_id":"8de14ef4-91ad-43ec-a238-cf81665b7330","cartao_final":"9260","instituicao":"Mercado Pago","data_compra":"2026-05-30","descricao_original":"Juros de mora","tipo_lancamento":"encargo","fatura_vencimento":"2026-06-08","fatura_competencia":"2026-05-01","fatura_total":"370.66","fatura_consumos":"364.44","fatura_encargos":"6.22","fatura_paga_em":"2026-06-09","arquivo_origem":"mercado pago 3.pdf","arquivo_sha256":"6f86012b3b6bdfaeb78e69b54b4df8a588a1d4c5754171f03a4051a647b61b7f","pagina_pdf":2,"importacao_lote":"mercado-pago-cartao-filipe-2026-03-a-06","projetada_pela_ia":false}$json$::jsonb, true),
  ('48faeb64-2792-5cd0-a940-67923e97581e'::uuid, 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid, 'd33d76b9-5f1b-436c-aec1-2f7270a863e6'::uuid, 'b5a0206d-6ffa-46ed-8375-b2f40d06428e'::uuid, 'despesa', 'IOF do rotativo', 0.53, '2026-05-30'::date, '2026-05-01'::date, 'confirmada', 'credito', null, null, null::uuid, 'fatura', '30/05 - IOF do rotativo - R$ 0.53. Fatura Mercado Pago final 9260 com vencimento em 2026-06-08.', $json${"cartao_id":"8de14ef4-91ad-43ec-a238-cf81665b7330","cartao_final":"9260","instituicao":"Mercado Pago","data_compra":"2026-05-30","descricao_original":"IOF do rotativo","tipo_lancamento":"encargo","fatura_vencimento":"2026-06-08","fatura_competencia":"2026-05-01","fatura_total":"370.66","fatura_consumos":"364.44","fatura_encargos":"6.22","fatura_paga_em":"2026-06-09","arquivo_origem":"mercado pago 3.pdf","arquivo_sha256":"6f86012b3b6bdfaeb78e69b54b4df8a588a1d4c5754171f03a4051a647b61b7f","pagina_pdf":2,"importacao_lote":"mercado-pago-cartao-filipe-2026-03-a-06","projetada_pela_ia":false}$json$::jsonb, true),
  ('e95e7aa7-8ca7-5501-8f3a-b5c2614553fb'::uuid, 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid, 'd33d76b9-5f1b-436c-aec1-2f7270a863e6'::uuid, null::uuid, 'despesa', 'Compra Mercado Livre nao identificada', 33.68, '2026-03-12'::date, '2026-06-01'::date, 'confirmada', 'credito', 4, 8, '72e8a1bf-7738-42f2-be1e-4a5529042dd3'::uuid, 'fatura', '12/03 - MERCADOLIVRE*24PRODUTO - parcela 4 de 8 - R$ 33.68. Fatura Mercado Pago final 9260 com vencimento em 2026-07-06.', $json${"cartao_id":"8de14ef4-91ad-43ec-a238-cf81665b7330","cartao_final":"9260","instituicao":"Mercado Pago","data_compra":"2026-03-12","descricao_original":"MERCADOLIVRE*24PRODUTO","tipo_lancamento":"parcela","fatura_vencimento":"2026-07-06","fatura_competencia":"2026-06-01","fatura_total":"210.60","fatura_consumos":"199.43","fatura_encargos":"11.17","fatura_paga_em":null,"arquivo_origem":"mercado pago 4.pdf","arquivo_sha256":"580e5bac4f3900f60d69869824963052311c6c0cd5e9478dbec21ab7ddb84a83","pagina_pdf":2,"importacao_lote":"mercado-pago-cartao-filipe-2026-03-a-06","projetada_pela_ia":false}$json$::jsonb, true),
  ('0414dc7f-7b91-5631-afbf-79f8d551c2f0'::uuid, 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid, 'd33d76b9-5f1b-436c-aec1-2f7270a863e6'::uuid, null::uuid, 'despesa', 'Compra Mercado Livre com 22 itens', 92.01, '2026-03-12'::date, '2026-06-01'::date, 'confirmada', 'credito', 4, 12, '194d0607-89c8-4642-b5d2-75e92967c1ad'::uuid, 'fatura', '12/03 - MERCADOLIVRE*24PRODUTOS - parcela 4 de 12 - R$ 92.01. Fatura Mercado Pago final 9260 com vencimento em 2026-07-06.', $json${"cartao_id":"8de14ef4-91ad-43ec-a238-cf81665b7330","cartao_final":"9260","instituicao":"Mercado Pago","data_compra":"2026-03-12","descricao_original":"MERCADOLIVRE*24PRODUTOS","tipo_lancamento":"parcela","fatura_vencimento":"2026-07-06","fatura_competencia":"2026-06-01","fatura_total":"210.60","fatura_consumos":"199.43","fatura_encargos":"11.17","fatura_paga_em":null,"arquivo_origem":"mercado pago 4.pdf","arquivo_sha256":"580e5bac4f3900f60d69869824963052311c6c0cd5e9478dbec21ab7ddb84a83","pagina_pdf":2,"importacao_lote":"mercado-pago-cartao-filipe-2026-03-a-06","projetada_pela_ia":false}$json$::jsonb, true),
  ('da9e0a54-2aea-52f2-9230-437edf95457d'::uuid, 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid, 'd33d76b9-5f1b-436c-aec1-2f7270a863e6'::uuid, null::uuid, 'despesa', 'Kit com 5 molduras A4 tabaco', 16.72, '2026-05-27'::date, '2026-06-01'::date, 'confirmada', 'credito', 2, 5, '1de640d0-cb93-49b5-a229-561183c523c6'::uuid, 'fatura', '27/05 - MERCADOLIVRE*TOQUEPOP - parcela 2 de 5 - R$ 16.72. Fatura Mercado Pago final 9260 com vencimento em 2026-07-06.', $json${"cartao_id":"8de14ef4-91ad-43ec-a238-cf81665b7330","cartao_final":"9260","instituicao":"Mercado Pago","data_compra":"2026-05-27","descricao_original":"MERCADOLIVRE*TOQUEPOP","tipo_lancamento":"parcela","fatura_vencimento":"2026-07-06","fatura_competencia":"2026-06-01","fatura_total":"210.60","fatura_consumos":"199.43","fatura_encargos":"11.17","fatura_paga_em":null,"arquivo_origem":"mercado pago 4.pdf","arquivo_sha256":"580e5bac4f3900f60d69869824963052311c6c0cd5e9478dbec21ab7ddb84a83","pagina_pdf":2,"importacao_lote":"mercado-pago-cartao-filipe-2026-03-a-06","projetada_pela_ia":false}$json$::jsonb, true),
  ('d4d2f650-1550-57fd-a71b-1f5a983565c0'::uuid, 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid, 'd33d76b9-5f1b-436c-aec1-2f7270a863e6'::uuid, null::uuid, 'despesa', 'Kit de acessorios para bicicleta', 57.02, '2026-06-10'::date, '2026-06-01'::date, 'confirmada', 'credito', 1, 6, '8c8372d0-e11a-4364-8d24-9f162562e904'::uuid, 'fatura', '10/06 - MERCADOLIVRE*MERCADOLIVRE - parcela 1 de 6 - R$ 57.02. Fatura Mercado Pago final 9260 com vencimento em 2026-07-06.', $json${"cartao_id":"8de14ef4-91ad-43ec-a238-cf81665b7330","cartao_final":"9260","instituicao":"Mercado Pago","data_compra":"2026-06-10","descricao_original":"MERCADOLIVRE*MERCADOLIVRE","tipo_lancamento":"parcela","fatura_vencimento":"2026-07-06","fatura_competencia":"2026-06-01","fatura_total":"210.60","fatura_consumos":"199.43","fatura_encargos":"11.17","fatura_paga_em":null,"arquivo_origem":"mercado pago 4.pdf","arquivo_sha256":"580e5bac4f3900f60d69869824963052311c6c0cd5e9478dbec21ab7ddb84a83","pagina_pdf":2,"importacao_lote":"mercado-pago-cartao-filipe-2026-03-a-06","projetada_pela_ia":false}$json$::jsonb, true),
  ('71cff7e8-ac89-5080-a1a9-0992e5c95427'::uuid, 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid, 'd33d76b9-5f1b-436c-aec1-2f7270a863e6'::uuid, 'b5a0206d-6ffa-46ed-8375-b2f40d06428e'::uuid, 'despesa', 'IOF do rotativo', 1.45, '2026-06-30'::date, '2026-06-01'::date, 'confirmada', 'credito', null, null, null::uuid, 'fatura', '30/06 - IOF do rotativo - R$ 1.45. Fatura Mercado Pago final 9260 com vencimento em 2026-07-06.', $json${"cartao_id":"8de14ef4-91ad-43ec-a238-cf81665b7330","cartao_final":"9260","instituicao":"Mercado Pago","data_compra":"2026-06-30","descricao_original":"IOF do rotativo","tipo_lancamento":"encargo","fatura_vencimento":"2026-07-06","fatura_competencia":"2026-06-01","fatura_total":"210.60","fatura_consumos":"199.43","fatura_encargos":"11.17","fatura_paga_em":null,"arquivo_origem":"mercado pago 4.pdf","arquivo_sha256":"580e5bac4f3900f60d69869824963052311c6c0cd5e9478dbec21ab7ddb84a83","pagina_pdf":2,"importacao_lote":"mercado-pago-cartao-filipe-2026-03-a-06","projetada_pela_ia":false}$json$::jsonb, true),
  ('48c77de5-94d5-5eb5-898c-f0ed00db3a8f'::uuid, 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid, 'd33d76b9-5f1b-436c-aec1-2f7270a863e6'::uuid, 'b5a0206d-6ffa-46ed-8375-b2f40d06428e'::uuid, 'despesa', 'Multa por atraso', 7.37, '2026-06-30'::date, '2026-06-01'::date, 'confirmada', 'credito', null, null, null::uuid, 'fatura', '30/06 - Multa por atraso - R$ 7.37. Fatura Mercado Pago final 9260 com vencimento em 2026-07-06.', $json${"cartao_id":"8de14ef4-91ad-43ec-a238-cf81665b7330","cartao_final":"9260","instituicao":"Mercado Pago","data_compra":"2026-06-30","descricao_original":"Multa por atraso","tipo_lancamento":"encargo","fatura_vencimento":"2026-07-06","fatura_competencia":"2026-06-01","fatura_total":"210.60","fatura_consumos":"199.43","fatura_encargos":"11.17","fatura_paga_em":null,"arquivo_origem":"mercado pago 4.pdf","arquivo_sha256":"580e5bac4f3900f60d69869824963052311c6c0cd5e9478dbec21ab7ddb84a83","pagina_pdf":2,"importacao_lote":"mercado-pago-cartao-filipe-2026-03-a-06","projetada_pela_ia":false}$json$::jsonb, true),
  ('3d6ba009-a1a6-51d3-bc01-2afecfc35586'::uuid, 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid, 'd33d76b9-5f1b-436c-aec1-2f7270a863e6'::uuid, 'b5a0206d-6ffa-46ed-8375-b2f40d06428e'::uuid, 'despesa', 'Juros do rotativo', 2.22, '2026-06-30'::date, '2026-06-01'::date, 'confirmada', 'credito', null, null, null::uuid, 'fatura', '30/06 - Juros do rotativo - R$ 2.22. Fatura Mercado Pago final 9260 com vencimento em 2026-07-06.', $json${"cartao_id":"8de14ef4-91ad-43ec-a238-cf81665b7330","cartao_final":"9260","instituicao":"Mercado Pago","data_compra":"2026-06-30","descricao_original":"Juros do rotativo","tipo_lancamento":"encargo","fatura_vencimento":"2026-07-06","fatura_competencia":"2026-06-01","fatura_total":"210.60","fatura_consumos":"199.43","fatura_encargos":"11.17","fatura_paga_em":null,"arquivo_origem":"mercado pago 4.pdf","arquivo_sha256":"580e5bac4f3900f60d69869824963052311c6c0cd5e9478dbec21ab7ddb84a83","pagina_pdf":2,"importacao_lote":"mercado-pago-cartao-filipe-2026-03-a-06","projetada_pela_ia":false}$json$::jsonb, true),
  ('07428262-dc21-5286-a30c-8fb3ef9bb0c6'::uuid, 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid, 'd33d76b9-5f1b-436c-aec1-2f7270a863e6'::uuid, 'b5a0206d-6ffa-46ed-8375-b2f40d06428e'::uuid, 'despesa', 'Juros de mora', 0.13, '2026-06-30'::date, '2026-06-01'::date, 'confirmada', 'credito', null, null, null::uuid, 'fatura', '30/06 - Juros de mora - R$ 0.13. Fatura Mercado Pago final 9260 com vencimento em 2026-07-06.', $json${"cartao_id":"8de14ef4-91ad-43ec-a238-cf81665b7330","cartao_final":"9260","instituicao":"Mercado Pago","data_compra":"2026-06-30","descricao_original":"Juros de mora","tipo_lancamento":"encargo","fatura_vencimento":"2026-07-06","fatura_competencia":"2026-06-01","fatura_total":"210.60","fatura_consumos":"199.43","fatura_encargos":"11.17","fatura_paga_em":null,"arquivo_origem":"mercado pago 4.pdf","arquivo_sha256":"580e5bac4f3900f60d69869824963052311c6c0cd5e9478dbec21ab7ddb84a83","pagina_pdf":2,"importacao_lote":"mercado-pago-cartao-filipe-2026-03-a-06","projetada_pela_ia":false}$json$::jsonb, true)
on conflict (id) do nothing;

-- Reutiliza nomes e composicoes detalhadas das parcelas futuras ja revisadas.
with modelos as (
  select distinct on (grupo_parcelas_id)
    grupo_parcelas_id, descricao, metadados -> 'composicao_fatura' as composicao
  from public.movimentacoes
  where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
    and grupo_parcelas_id in (
      '72e8a1bf-7738-42f2-be1e-4a5529042dd3'::uuid, '194d0607-89c8-4642-b5d2-75e92967c1ad'::uuid,
      '1de640d0-cb93-49b5-a229-561183c523c6'::uuid, '8c8372d0-e11a-4364-8d24-9f162562e904'::uuid
    )
    and metadados ? 'composicao_fatura'
  order by grupo_parcelas_id, parcela_numero desc
)
update public.movimentacoes as movimentacao
set
  descricao = modelo.descricao,
  metadados = movimentacao.metadados
    || jsonb_build_object('composicao_fatura', modelo.composicao)
from modelos as modelo
where movimentacao.usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
  and movimentacao.metadados ->> 'importacao_lote' = 'mercado-pago-cartao-filipe-2026-03-a-06'
  and movimentacao.grupo_parcelas_id = modelo.grupo_parcelas_id;

-- Completa a data original e o final do cartao nas parcelas futuras vinculadas.
with compras (grupo_id, data_compra) as (
  values
    ('72e8a1bf-7738-42f2-be1e-4a5529042dd3'::uuid, '2026-03-12'::date),
    ('194d0607-89c8-4642-b5d2-75e92967c1ad'::uuid, '2026-03-12'::date),
    ('1de640d0-cb93-49b5-a229-561183c523c6'::uuid, '2026-05-27'::date),
    ('8c8372d0-e11a-4364-8d24-9f162562e904'::uuid, '2026-06-10'::date)
)
update public.movimentacoes as movimentacao
set metadados = movimentacao.metadados || jsonb_build_object(
  'data_compra', compras.data_compra::text,
  'cartao_final', '9260'
)
from compras
where movimentacao.usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
  and movimentacao.grupo_parcelas_id = compras.grupo_id;

do $$
declare
  quantidade integer;
  total numeric(14, 2);
  total_marco numeric(14, 2);
  total_abril numeric(14, 2);
  total_maio numeric(14, 2);
  total_junho numeric(14, 2);
  grupo record;
begin
  select
    count(*),
    coalesce(sum(valor), 0),
    coalesce(sum(valor) filter (where mes_competencia = '2026-03-01'::date), 0),
    coalesce(sum(valor) filter (where mes_competencia = '2026-04-01'::date), 0),
    coalesce(sum(valor) filter (where mes_competencia = '2026-05-01'::date), 0),
    coalesce(sum(valor) filter (where mes_competencia = '2026-06-01'::date), 0)
  into quantidade, total, total_marco, total_abril, total_maio, total_junho
  from public.movimentacoes
  where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
    and metadados ->> 'importacao_lote' = 'mercado-pago-cartao-filipe-2026-03-a-06';

  if quantidade <> 21 or total <> 832.71
     or total_marco <> 125.76 or total_abril <> 125.69
     or total_maio <> 370.66 or total_junho <> 210.60 then
    raise exception
      'Validacao das faturas falhou: % itens, total %, meses %/%/%/%.',
      quantidade, total, total_marco, total_abril, total_maio, total_junho;
  end if;

  for grupo in
    select esperado.grupo_id, esperado.total_parcelas,
      count(movimentacao.id) as quantidade,
      count(distinct movimentacao.parcela_numero) as parcelas_distintas,
      min(movimentacao.parcela_numero) as primeira,
      max(movimentacao.parcela_numero) as ultima
    from (values
      ('72e8a1bf-7738-42f2-be1e-4a5529042dd3'::uuid, 8),
      ('194d0607-89c8-4642-b5d2-75e92967c1ad'::uuid, 12),
      ('1de640d0-cb93-49b5-a229-561183c523c6'::uuid, 5),
      ('8c8372d0-e11a-4364-8d24-9f162562e904'::uuid, 6)
    ) as esperado(grupo_id, total_parcelas)
    left join public.movimentacoes as movimentacao
      on movimentacao.grupo_parcelas_id = esperado.grupo_id
     and movimentacao.usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
    group by esperado.grupo_id, esperado.total_parcelas
  loop
    if grupo.quantidade <> grupo.total_parcelas
       or grupo.parcelas_distintas <> grupo.total_parcelas
       or grupo.primeira <> 1 or grupo.ultima <> grupo.total_parcelas then
      raise exception 'Sequencia incompleta ou duplicada no grupo %.', grupo.grupo_id;
    end if;
  end loop;
end;
$$;

commit;
