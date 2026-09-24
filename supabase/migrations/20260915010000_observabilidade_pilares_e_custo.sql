-- Os quatro pilares do juiz, e o custo que parou de ser zero.
--
-- Duas coisas, e elas vieram na mesma migration porque a tela que as mostra é
-- a mesma:
--
-- ## 1. O custo mentia
--
-- `custo_usd numeric(12, 6)` guarda até o microdólar; uma chamada de embedding
-- de 20 tokens custa US$ 0,0000004 e era gravada como **zero**. Pior: o custo
-- só era calculado quando o nome do modelo batia por igualdade exata com uma
-- tabela de três linhas, e o provedor devolve o instantâneo datado
-- (`gpt-5.4-mini-2026-03-01`). Na prática, o painel afirmava que o hub não
-- gasta nada.
--
-- Aqui o tipo vira `numeric(14, 8)` — oito casas é o que `precos.py` arredonda
-- — e entram as colunas que faltavam para a conta fechar: token servido do
-- cache (custa uma fração), segundos de áudio (há modelo cobrado por minuto) e
-- a procedência do número, para a tela poder dizer "estimado" em vez de fingir
-- exatidão.
--
-- ## 2. O juiz virou quatro pilares
--
-- Sete notas soltas respondiam "quanto tirou" e não respondiam "em que está
-- ruim". As nove dimensões de `pilares.py` se agrupam agora em Resolução,
-- Fidelidade, Comunicação e Segurança, e o agrupamento é **gravado**, não
-- recalculado na leitura: a fórmula pode mudar amanhã, e a nota de ontem tem
-- de continuar sendo a que foi dada — a mesma regra do custo.
--
-- As colunas de pilar são preenchidas pelas **duas** origens. As regras
-- determinísticas rodam em 100% das respostas e sabem pontuar pilar; sem isso
-- a média macro só existiria na fatia amostrada do juiz, e um painel que diz
-- "82" sobre 9% das respostas é uma amostra, não um painel.
--
-- Nada aqui guarda texto de conversa. `motivo_redigido` é a única coluna nova
-- parecida com texto: ela passa por `redacao.redigir()`, tem teto de 300
-- caracteres e só existe para apps fora de `APPS_SEM_PAYLOAD`.

begin;

-- ---------------------------------------------------------------- 1. o custo
alter table public.obs_interacoes
  alter column custo_usd type numeric(14, 8),
  add column custo_estimado boolean not null default false;

alter table public.obs_llm_chamadas
  alter column custo_usd type numeric(14, 8),
  -- Subconjunto de `tokens_entrada`, e não parcela a somar: é assim que o
  -- provedor o reporta em `input_token_details`.
  add column tokens_cacheados integer
    check (tokens_cacheados is null or tokens_cacheados >= 0),
  add column segundos_audio numeric(10, 2)
    check (segundos_audio is null or segundos_audio >= 0),
  add column custo_origem text
    check (custo_origem is null or custo_origem in ('tabela', 'familia', 'estimado'));

alter table public.obs_avaliacoes
  alter column custo_usd type numeric(14, 8);

alter table public.obs_rollup_horario
  alter column custo_usd type numeric(14, 8);

-- --------------------------------------------------------------- 2. o juiz
alter table public.obs_avaliacoes
  add column atendimento smallint check (atendimento between 0 and 10),
  add column completude smallint check (completude between 0 and 10),
  add column pilar_resolucao smallint check (pilar_resolucao between 0 and 100),
  add column pilar_fidelidade smallint check (pilar_fidelidade between 0 and 100),
  add column pilar_comunicacao smallint check (pilar_comunicacao between 0 and 100),
  add column pilar_seguranca smallint check (pilar_seguranca between 0 and 100),
  add column motivo_redigido text
    check (motivo_redigido is null or char_length(motivo_redigido) <= 400);

-- O painel abre pelos pilares e desce até a resposta individual: a varredura
-- é sempre por janela, e a ordenação, por um pilar. Um índice por pilar seria
-- quatro índices para a mesma varredura — este cobre a janela, que é o filtro
-- que corta o volume, e os quatro valores vêm na linha.
create index obs_avaliacoes_pilares_idx
  on public.obs_avaliacoes (avaliada_em desc)
  include (pilar_resolucao, pilar_fidelidade, pilar_comunicacao, pilar_seguranca);

-- ------------------------------------------------------- panorama com pilar
-- A manchete passa a trazer os quatro pilares: é o que permite a tela inicial
-- mostrar o estado da qualidade sem ninguém abrir a aba de qualidade. Sem
-- muitos cliques era o pedido, e uma aba a mais é um clique a mais.
create or replace function public.obs_panorama(
  p_desde timestamptz,
  p_ate timestamptz default null
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with janela as (
    select i.*
      from public.obs_interacoes i
     where i.inicio >= p_desde and i.inicio < coalesce(p_ate, now())
  ),
  notas as (
    select avg(overall)::numeric as media,
           count(*) as total,
           count(*) filter (where origem = 'judge') as pelo_juiz,
           avg(pilar_resolucao)::numeric as resolucao,
           avg(pilar_fidelidade)::numeric as fidelidade,
           avg(pilar_comunicacao)::numeric as comunicacao,
           avg(pilar_seguranca)::numeric as seguranca
      from public.obs_avaliacoes
     where avaliada_em >= p_desde and avaliada_em < coalesce(p_ate, now())
       and overall is not null
  )
  select jsonb_build_object(
    'interacoes', (select count(*) from janela),
    'erros', (select count(*) filter (where status = 'erro') from janela),
    'parciais', (select count(*) filter (where status = 'parcial') from janela),
    -- Disponibilidade conta erro como falha e parcial como sucesso: a resposta
    -- saiu. Sem interação na janela a resposta é `null`, e não 100% — "nada
    -- aconteceu" e "tudo deu certo" não são a mesma frase.
    'disponibilidade', (
      select case when count(*) = 0 then null
             else round(100.0 * count(*) filter (where status <> 'erro') / count(*), 2)
             end from janela
    ),
    'duracao_media', (select round(avg(duracao_ms))::integer from janela),
    'p50', (select percentile_disc(0.50) within group (order by duracao_ms) from janela),
    'p95', (select percentile_disc(0.95) within group (order by duracao_ms) from janela),
    'p99', (select percentile_disc(0.99) within group (order by duracao_ms) from janela),
    'tokens', (select coalesce(sum(tokens_total), 0) from janela),
    'custo_usd', (select coalesce(sum(custo_usd), 0) from janela),
    -- Uma interação estimada basta para o total deixar de ser exato: a tela
    -- mostra "por volta de" em vez de um número que não fecha com a fatura.
    'custo_estimado', (
      select coalesce(bool_or(custo_estimado), false) from janela
    ),
    'chamadas_llm', (select coalesce(sum(chamadas_llm), 0) from janela),
    'judge_overall', (select round(media, 1) from notas),
    'avaliacoes', (select total from notas),
    'avaliacoes_judge', (select pelo_juiz from notas),
    'pilares', (
      select jsonb_build_object(
        'resolucao', round(resolucao, 1),
        'fidelidade', round(fidelidade, 1),
        'comunicacao', round(comunicacao, 1),
        'seguranca', round(seguranca, 1)
      ) from notas
    ),
    'alertas_abertos', (
      select count(*) from public.obs_alertas where resolvido_em is null
    ),
    -- A saúde do próprio módulo entra no panorama de propósito: sem ela, a
    -- tela diz "zero erros" quando a verdade é "não recebi nada".
    'eventos_perdidos', (
      select coalesce(sum(eventos_perdidos), 0) from public.obs_saude
       where hora >= p_desde
    ),
    'falhas_persistencia', (
      select coalesce(sum(falhas_persistencia), 0) from public.obs_saude
       where hora >= p_desde
    )
  );
$$;

-- ---------------------------------------------------- o mapa: pilar × recorte
-- A pergunta macro em uma consulta: "quem está pior, e em quê". Uma linha por
-- app, agente ou canal; uma coluna por pilar. É o mapa de calor da tela, e ele
-- é uma consulta e não quatro porque a alternativa — pedir a média de cada
-- pilar em separado — faria a mesma varredura quatro vezes.
create or replace function public.obs_qualidade_por_dimensao(
  p_dimensao text,
  p_desde timestamptz,
  p_ate timestamptz default null,
  p_limite integer default 20
)
returns table (
  chave text,
  avaliacoes bigint,
  judge bigint,
  overall numeric,
  resolucao numeric,
  fidelidade numeric,
  comunicacao numeric,
  seguranca numeric,
  pior_pilar text,
  sinalizacoes bigint
)
language sql
stable
security definer
set search_path = ''
as $$
  with janela as (
    select case when p_dimensao = 'agente' then coalesce(a.agente, '(sem agente)')
                when p_dimensao = 'canal' then coalesce(a.canal, '(sem canal)')
                else coalesce(a.app, '(hub)') end as chave,
           a.*
      from public.obs_avaliacoes a
     where a.avaliada_em >= p_desde and a.avaliada_em < coalesce(p_ate, now())
  ),
  agregado as (
    select j.chave,
           count(*) as avaliacoes,
           count(*) filter (where j.origem = 'judge') as judge,
           round(avg(j.overall)::numeric, 1) as overall,
           round(avg(j.pilar_resolucao)::numeric, 1) as resolucao,
           round(avg(j.pilar_fidelidade)::numeric, 1) as fidelidade,
           round(avg(j.pilar_comunicacao)::numeric, 1) as comunicacao,
           round(avg(j.pilar_seguranca)::numeric, 1) as seguranca,
           coalesce(sum(cardinality(j.sinalizacoes)), 0) as sinalizacoes
      from janela j
     group by j.chave
  )
  select g.chave, g.avaliacoes, g.judge, g.overall,
         g.resolucao, g.fidelidade, g.comunicacao, g.seguranca,
         -- O pilar mais baixo, escrito por extenso: é o que a tela precisa
         -- para dizer "Casa: fidelidade" sem comparar quatro números no
         -- cliente e sem desempate arbitrário. O empate é resolvido pela
         -- ordem em que `pilares.py` os declara, que é a ordem da tela.
         case
           when coalesce(g.resolucao, g.fidelidade, g.comunicacao, g.seguranca) is null
             then null
           else case least(coalesce(g.resolucao, 101), coalesce(g.fidelidade, 101),
                           coalesce(g.comunicacao, 101), coalesce(g.seguranca, 101))
                  when coalesce(g.resolucao, 101) then 'resolucao'
                  when coalesce(g.fidelidade, 101) then 'fidelidade'
                  when coalesce(g.comunicacao, 101) then 'comunicacao'
                  else 'seguranca'
                end
         end,
         g.sinalizacoes
    from agregado g
   order by coalesce(g.overall, 100), g.avaliacoes desc
   limit greatest(1, p_limite);
$$;

-- ------------------------------------------------------- a série dos pilares
-- "Melhorou ou piorou?" — os quatro pilares por período, para o painel
-- desenhar a linha sem trazer avaliação nenhuma para o cliente.
create or replace function public.obs_qualidade_serie(
  p_desde timestamptz,
  p_grao text default 'day',
  p_ate timestamptz default null,
  p_app text default null,
  p_agente text default null
)
returns table (
  periodo timestamptz,
  avaliacoes bigint,
  overall numeric,
  resolucao numeric,
  fidelidade numeric,
  comunicacao numeric,
  seguranca numeric
)
language sql
stable
security definer
set search_path = ''
as $$
  select date_trunc(
           case when p_grao in ('hour', 'day', 'week', 'month') then p_grao else 'day' end,
           a.avaliada_em
         ) as periodo,
         count(*),
         round(avg(a.overall)::numeric, 1),
         round(avg(a.pilar_resolucao)::numeric, 1),
         round(avg(a.pilar_fidelidade)::numeric, 1),
         round(avg(a.pilar_comunicacao)::numeric, 1),
         round(avg(a.pilar_seguranca)::numeric, 1)
    from public.obs_avaliacoes a
   where a.avaliada_em >= p_desde and a.avaliada_em < coalesce(p_ate, now())
     and (p_app is null or a.app = p_app)
     and (p_agente is null or a.agente = p_agente)
   group by 1
   order by 1;
$$;

-- --------------------------------------------------- a qualidade, com pilares
-- A mesma função de antes, agora respondendo três perguntas em vez de uma:
-- quanto tiramos em cada pilar, quanto tirávamos na janela anterior do mesmo
-- tamanho, e por que estamos perdendo pontos.
--
-- A janela anterior é calculada aqui e não na tela: comparar depende de as
-- duas janelas terem exatamente a mesma duração, e essa é uma conta que erra
-- silenciosamente quando cada cliente a faz por conta.
create or replace function public.obs_qualidade(
  p_desde timestamptz,
  p_ate timestamptz default null,
  p_app text default null,
  p_agente text default null,
  p_prompt_id text default null
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with limites as (
    select p_desde as desde, coalesce(p_ate, now()) as ate
  ),
  janela as (
    select a.* from public.obs_avaliacoes a, limites l
     where a.avaliada_em >= l.desde and a.avaliada_em < l.ate
       and (p_app is null or a.app = p_app)
       and (p_agente is null or a.agente = p_agente)
       and (p_prompt_id is null or a.prompt_id = p_prompt_id)
  ),
  anterior as (
    select a.* from public.obs_avaliacoes a, limites l
     where a.avaliada_em >= l.desde - (l.ate - l.desde)
       and a.avaliada_em < l.desde
       and (p_app is null or a.app = p_app)
       and (p_agente is null or a.agente = p_agente)
       and (p_prompt_id is null or a.prompt_id = p_prompt_id)
  )
  select jsonb_build_object(
    'avaliacoes', (select count(*) from janela),
    'judge', (select count(*) from janela where origem = 'judge'),
    'regra', (select count(*) from janela where origem = 'regra'),
    'dimensoes', (
      select jsonb_build_object(
        'atendimento', round(avg(atendimento)::numeric, 2),
        'completude', round(avg(completude)::numeric, 2),
        'correctness', round(avg(correctness)::numeric, 2),
        'naturalness', round(avg(naturalness)::numeric, 2),
        'context_usage', round(avg(context_usage)::numeric, 2),
        'verbosity', round(avg(verbosity)::numeric, 2),
        'tone_fit', round(avg(tone_fit)::numeric, 2),
        'tool_grounding', round(avg(tool_grounding)::numeric, 2),
        'safety', round(avg(safety)::numeric, 2),
        'overall', round(avg(overall)::numeric, 1)
      ) from janela
    ),
    -- Um objeto por pilar, com a nota de agora, a de antes e quantas
    -- avaliações a sustentam. A contagem vai junto porque uma nota 100 sobre
    -- duas avaliações não é a mesma notícia que uma nota 100 sobre duzentas.
    'pilares', (
      select jsonb_build_object(
        'resolucao', jsonb_build_object(
          'nota', (select round(avg(pilar_resolucao)::numeric, 1) from janela),
          'anterior', (select round(avg(pilar_resolucao)::numeric, 1) from anterior),
          'avaliacoes', (select count(pilar_resolucao) from janela)
        ),
        'fidelidade', jsonb_build_object(
          'nota', (select round(avg(pilar_fidelidade)::numeric, 1) from janela),
          'anterior', (select round(avg(pilar_fidelidade)::numeric, 1) from anterior),
          'avaliacoes', (select count(pilar_fidelidade) from janela)
        ),
        'comunicacao', jsonb_build_object(
          'nota', (select round(avg(pilar_comunicacao)::numeric, 1) from janela),
          'anterior', (select round(avg(pilar_comunicacao)::numeric, 1) from anterior),
          'avaliacoes', (select count(pilar_comunicacao) from janela)
        ),
        'seguranca', jsonb_build_object(
          'nota', (select round(avg(pilar_seguranca)::numeric, 1) from janela),
          'anterior', (select round(avg(pilar_seguranca)::numeric, 1) from anterior),
          'avaliacoes', (select count(pilar_seguranca) from janela)
        )
      )
    ),
    'overall_anterior', (select round(avg(overall)::numeric, 1) from anterior),
    'sinalizacoes', coalesce((
      select jsonb_agg(jsonb_build_object('sinal', sinal, 'total', total)
                       order by total desc)
        from (
          select s as sinal, count(*) as total
            from janela, unnest(janela.sinalizacoes) as s
           group by s
        ) c
    ), '[]'::jsonb),
    'piores', coalesce((
      select jsonb_agg(jsonb_build_object(
               'trace_id', trace_id, 'overall', overall, 'agente', agente,
               'app', app, 'avaliada_em', avaliada_em, 'origem', origem,
               'sinalizacoes', sinalizacoes,
               'pilar_resolucao', pilar_resolucao,
               'pilar_fidelidade', pilar_fidelidade,
               'pilar_comunicacao', pilar_comunicacao,
               'pilar_seguranca', pilar_seguranca,
               'motivo_redigido', motivo_redigido)
             order by overall)
        from (select * from janela where overall is not null
               order by overall limit 20) p
    ), '[]'::jsonb)
  );
$$;

-- ---------------------------------------------- as avaliações, uma por linha
-- O lado individual do painel: a lista das respostas avaliadas, com as nove
-- notas, os quatro pilares e o porquê. É o que responde "e esta aqui, o que
-- houve?" sem sair da tela — a alternativa era abrir o trace de cada uma.
--
-- `p_origem` existe porque as duas origens respondem a perguntas diferentes:
-- `judge` é a leitura fina de uma fatia, `regra` é a varredura barata de
-- tudo. Misturá-las na mesma lista sem poder separar confunde as duas.
create or replace function public.obs_avaliacoes_lista(
  p_desde timestamptz,
  p_ate timestamptz default null,
  p_app text default null,
  p_agente text default null,
  p_origem text default null,
  p_pilar text default null,
  p_abaixo_de integer default null,
  p_sinal text default null,
  p_limite integer default 50
)
returns table (
  trace_id text,
  avaliada_em timestamptz,
  origem text,
  app text,
  agente text,
  canal text,
  modelo text,
  overall smallint,
  atendimento smallint,
  completude smallint,
  correctness smallint,
  context_usage smallint,
  tool_grounding smallint,
  naturalness smallint,
  tone_fit smallint,
  verbosity smallint,
  safety smallint,
  pilar_resolucao smallint,
  pilar_fidelidade smallint,
  pilar_comunicacao smallint,
  pilar_seguranca smallint,
  sinalizacoes text[],
  motivo_redigido text,
  sugestao_redigida text,
  duracao_ms integer,
  custo_usd numeric
)
language sql
stable
security definer
set search_path = ''
as $$
  select a.trace_id, a.avaliada_em, a.origem, a.app, a.agente, a.canal, a.modelo,
         a.overall, a.atendimento, a.completude, a.correctness, a.context_usage,
         a.tool_grounding, a.naturalness, a.tone_fit, a.verbosity, a.safety,
         a.pilar_resolucao, a.pilar_fidelidade, a.pilar_comunicacao, a.pilar_seguranca,
         a.sinalizacoes, a.motivo_redigido, a.sugestao_redigida,
         a.duracao_ms, a.custo_usd
    from public.obs_avaliacoes a
   where a.avaliada_em >= p_desde and a.avaliada_em < coalesce(p_ate, now())
     and (p_app is null or a.app = p_app)
     and (p_agente is null or a.agente = p_agente)
     and (p_origem is null or a.origem = p_origem)
     and (p_sinal is null or a.sinalizacoes @> array[p_sinal])
     and (
       p_abaixo_de is null
       or case p_pilar
            when 'resolucao' then a.pilar_resolucao
            when 'fidelidade' then a.pilar_fidelidade
            when 'comunicacao' then a.pilar_comunicacao
            when 'seguranca' then a.pilar_seguranca
            else a.overall
          end < p_abaixo_de
     )
   order by case p_pilar
              when 'resolucao' then a.pilar_resolucao
              when 'fidelidade' then a.pilar_fidelidade
              when 'comunicacao' then a.pilar_comunicacao
              when 'seguranca' then a.pilar_seguranca
              else a.overall
            end asc nulls last,
            a.avaliada_em desc
   limit greatest(1, least(p_limite, 200));
$$;

-- --------------------------------------------------------- modelos e custos
-- As duas ganham a mesma coluna: quanto do total é estimativa. Um painel de
-- custo que não distingue "medido" de "por volta de" faz a conta parecer mais
-- firme do que ela é.
--
-- `drop` antes do `create`, e só nestas duas: `create or replace` recusa
-- mudar a lista de parâmetros OUT ("cannot change return type of existing
-- function"), e as duas ganharam coluna. As outras funções deste arquivo
-- devolvem `jsonb` ou a mesma tabela de antes, e se substituem no lugar.
drop function if exists public.obs_modelos(timestamptz, timestamptz);
create or replace function public.obs_modelos(
  p_desde timestamptz,
  p_ate timestamptz default null
)
returns table (
  modelo text,
  chamadas bigint,
  tokens_entrada bigint,
  tokens_saida bigint,
  tokens_cacheados bigint,
  custo_usd numeric,
  custo_estimado boolean,
  duracao_media integer,
  p95 integer,
  retries bigint,
  erros bigint
)
language sql
stable
security definer
set search_path = ''
as $$
  select c.modelo,
         count(*),
         coalesce(sum(c.tokens_entrada), 0),
         coalesce(sum(c.tokens_saida), 0),
         coalesce(sum(c.tokens_cacheados), 0),
         coalesce(sum(c.custo_usd), 0),
         coalesce(bool_or(c.custo_origem = 'estimado'), false),
         round(avg(c.duracao_ms))::integer,
         percentile_disc(0.95) within group (order by c.duracao_ms)::integer,
         count(*) filter (where c.tentativas > 1),
         count(*) filter (where c.erro is not null)
    from public.obs_llm_chamadas c
   where c.criado_em >= p_desde and c.criado_em < coalesce(p_ate, now())
   group by c.modelo
   order by coalesce(sum(c.custo_usd), 0) desc;
$$;

drop function if exists public.obs_custos(timestamptz, text, timestamptz);
create or replace function public.obs_custos(
  p_desde timestamptz,
  p_grao text default 'day',
  p_ate timestamptz default null
)
returns table (
  periodo timestamptz,
  custo_usd numeric,
  tokens bigint,
  interacoes bigint,
  chamadas_llm bigint,
  custo_por_interacao numeric,
  custo_estimado boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select date_trunc(
           case when p_grao in ('hour', 'day', 'week', 'month') then p_grao else 'day' end,
           i.inicio
         ) as periodo,
         coalesce(sum(i.custo_usd), 0),
         coalesce(sum(i.tokens_total), 0),
         count(*),
         coalesce(sum(i.chamadas_llm), 0),
         case when count(*) = 0 then 0
              else round(coalesce(sum(i.custo_usd), 0) / count(*), 8) end,
         coalesce(bool_or(i.custo_estimado), false)
    from public.obs_interacoes i
   where i.inicio >= p_desde and i.inicio < coalesce(p_ate, now())
   group by 1
   order by 1;
$$;

-- --------------------------------------------- o rollup também soma o pilar
create or replace function public.obs_rollup_calcular(p_desde timestamptz default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_desde timestamptz := coalesce(p_desde, now() - interval '48 hours');
  v_ate timestamptz := date_trunc('hour', now());
  v_linhas integer;
begin
  delete from public.obs_rollup_horario
   where hora >= date_trunc('hour', v_desde) and hora < v_ate;

  insert into public.obs_rollup_horario (
    hora, app, agente, interacoes, erros, duracao_media,
    duracao_p50, duracao_p95, duracao_p99,
    tokens_total, custo_usd, chamadas_llm
  )
  select date_trunc('hour', i.inicio),
         coalesce(i.app, ''),
         coalesce(i.agente, ''),
         count(*),
         count(*) filter (where i.status = 'erro'),
         round(avg(i.duracao_ms))::integer,
         percentile_disc(0.50) within group (order by i.duracao_ms)::integer,
         percentile_disc(0.95) within group (order by i.duracao_ms)::integer,
         percentile_disc(0.99) within group (order by i.duracao_ms)::integer,
         sum(i.tokens_total),
         sum(i.custo_usd),
         sum(i.chamadas_llm)
    from public.obs_interacoes i
   where i.inicio >= date_trunc('hour', v_desde) and i.inicio < v_ate
   group by 1, 2, 3;

  get diagnostics v_linhas = row_count;

  -- A nota entra por update, e não na agregação acima: uma avaliação chega
  -- depois da interação (o Judge roda após a resposta sair), e um `left join`
  -- na hora do insert perderia a nota que ainda não existia.
  update public.obs_rollup_horario r
     set avaliacoes = a.total,
         judge_overall = a.media
    from (
      select date_trunc('hour', avaliada_em) as hora,
             coalesce(app, '') as app,
             coalesce(agente, '') as agente,
             count(*) as total,
             round(avg(overall)::numeric, 2) as media
        from public.obs_avaliacoes
       where avaliada_em >= date_trunc('hour', v_desde) and avaliada_em < v_ate
         and overall is not null
       group by 1, 2, 3
    ) a
   where r.hora = a.hora and r.app = a.app and r.agente = a.agente;

  return v_linhas;
end;
$$;

-- ------------------------------------------------------------------ segurança
revoke all on function public.obs_panorama(timestamptz, timestamptz) from public, anon, authenticated;
revoke all on function public.obs_modelos(timestamptz, timestamptz) from public, anon, authenticated;
revoke all on function public.obs_custos(timestamptz, text, timestamptz) from public, anon, authenticated;
revoke all on function public.obs_qualidade(timestamptz, timestamptz, text, text, text) from public, anon, authenticated;
revoke all on function public.obs_qualidade_por_dimensao(text, timestamptz, timestamptz, integer) from public, anon, authenticated;
revoke all on function public.obs_qualidade_serie(timestamptz, text, timestamptz, text, text) from public, anon, authenticated;
revoke all on function public.obs_avaliacoes_lista(timestamptz, timestamptz, text, text, text, text, integer, text, integer) from public, anon, authenticated;

commit;
