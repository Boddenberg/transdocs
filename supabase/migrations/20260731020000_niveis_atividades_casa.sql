begin;

-- A pontuacao deixa de ser calculada por peso, dimensao e quantidade. Cada
-- atividade passa a declarar diretamente os pontos dos niveis que oferece.
alter table public.catalogo_atividades_casa
  add column pontos_p numeric(8, 2),
  add column pontos_m numeric(8, 2),
  add column pontos_g numeric(8, 2);

update public.catalogo_atividades_casa
set pontos_p = peso_base,
    usa_dimensao = false,
    usa_quantidade = false;

alter table public.catalogo_atividades_casa
  alter column pontos_p set not null,
  add constraint catalogo_atividades_casa_pontos_p_validos
    check (pontos_p > 0 and pontos_p <= 999),
  add constraint catalogo_atividades_casa_pontos_m_validos
    check (pontos_m is null or (pontos_m > pontos_p and pontos_m <= 999)),
  add constraint catalogo_atividades_casa_pontos_g_validos
    check (
      pontos_g is null
      or (pontos_m is not null and pontos_g > pontos_m and pontos_g <= 999)
    ),
  add constraint catalogo_atividades_casa_peso_espelha_p
    check (peso_base = pontos_p);

-- O catalogo visivel passa a ser exatamente o que esta dentro de um comodo.
-- Itens antigos sem lugar ficam preservados para configuracao e historico,
-- mas deixam de ser oferecidos como uma terceira lista divergente.
update public.catalogo_atividades_casa as atividade
set status = 'arquivada',
    atualizado_em = now()
where atividade.status = 'ativa'
  and not exists (
    select 1
    from public.ambientes_catalogo_atividades_casa as ligacao
    where ligacao.atividade_id = atividade.id
  );

-- Nulo identifica os registros legados. Novos registros sempre guardam a
-- faixa escolhida; a pontuacao_total continua sendo o snapshot financeiro do
-- momento e nunca muda quando o catalogo for editado no futuro.
alter table public.registros_atividades_casa
  add column nivel_atividade text
    check (nivel_atividade is null or nivel_atividade in ('P', 'M', 'G'));

commit;
