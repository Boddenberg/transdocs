-- A qualidade, o custo agregado e os alertas (fases 2 a 4 da ADR 0008).
--
-- A migration anterior (`20260829010000`) criou o que a instrumentação
-- escreve: interações, spans, chamadas de modelo, erros e a saúde do próprio
-- módulo. Esta cria o que faltava para **responder perguntas** sobre aquilo:
-- a nota do Judge, o registro de versões de prompt, os alertas e o rollup
-- horário que a tela inicial lê.
--
-- A regra de privacidade não muda: nenhuma coluna aqui guarda o texto da
-- pergunta nem o da resposta. O Judge lê o par em memória, logo depois de a
-- resposta sair, e persiste **só os números**. A única exceção é
-- `sugestao_redigida`, que passa por `redacao.redigir()` e só existe para apps
-- fora de `APPS_SEM_PAYLOAD` — FiNanças, Documentos e Cofre nunca a têm.

begin;

-- ----------------------------------------------------------------- avaliações
-- Uma linha por resposta avaliada. `origem` separa as duas fontes: o Judge por
-- LLM, caro e amostrado, e as regras determinísticas, baratas e em 100%.
-- Elas coexistem na mesma tabela de propósito — a pergunta "por que estamos
-- perdendo pontos?" soma as duas, e um `union` entre tabelas separadas seria
-- só uma junta a mais para dar a mesma resposta.
create table public.obs_avaliacoes (
  id bigint generated always as identity primary key,
  trace_id text not null check (trace_id ~ '^[0-9a-f]{32}$'),
  span_id text check (span_id is null or span_id ~ '^[0-9a-f]{16}$'),
  avaliada_em timestamptz not null,
  origem text not null check (origem in ('judge', 'regra')),
  app text check (app is null or char_length(app) <= 40),
  agente text check (agente is null or char_length(agente) <= 60),
  canal text check (canal is null or char_length(canal) <= 40),
  -- O modelo que gerou a resposta avaliada, não o que a avaliou.
  modelo text,
  prompt_id text,
  prompt_versao text,
  -- O braço do experimento, quando a resposta saiu de um A/B. Nulo é o
  -- caminho normal: sem experimento em andamento, ninguém escreve aqui.
  experimento text,
  braco text,
  -- As oito dimensões. 0 a 10 nas sete primeiras, 0 a 100 no `overall`, que
  -- não é a média delas: o Judge o devolve, e uma nota de segurança baixa
  -- precisa poder derrubar o conjunto sem que a média a dilua.
  correctness smallint check (correctness between 0 and 10),
  naturalness smallint check (naturalness between 0 and 10),
  context_usage smallint check (context_usage between 0 and 10),
  verbosity smallint check (verbosity between 0 and 10),
  tone_fit smallint check (tone_fit between 0 and 10),
  tool_grounding smallint check (tool_grounding between 0 and 10),
  safety smallint check (safety between 0 and 10),
  overall smallint check (overall between 0 and 100),
  -- O que saiu errado, em vocabulário fechado: `resposta_longa_demais`,
  -- `abertura_robotizada`, `fecho_de_atendente`… É daqui que sai a divisão
  -- "31% excesso de texto, 24% tom robótico" sem ninguém interpretar texto.
  sinalizacoes text[] not null default '{}',
  modelo_juiz text,
  custo_usd numeric(12, 6) check (custo_usd is null or custo_usd >= 0),
  duracao_ms integer check (duracao_ms is null or duracao_ms >= 0),
  -- A resposta que o Judge acha que teria sido melhor. Ferramenta de análise,
  -- nunca substituição automática — nada no backend lê esta coluna para
  -- responder a ninguém.
  sugestao_redigida text,
  criado_em timestamptz not null default now()
);

-- A tela de qualidade pergunta por janela e por dimensão de corte.
create index obs_avaliacoes_janela_idx
  on public.obs_avaliacoes (avaliada_em desc, app, agente);
-- "A v18 melhorou ou piorou?" é uma varredura por (prompt, versão).
create index obs_avaliacoes_versao_idx
  on public.obs_avaliacoes (prompt_id, prompt_versao, avaliada_em desc)
  where prompt_id is not null;
-- "As respostas com nota baixa" é a lista que se abre primeiro, e ela é uma
-- fração pequena do total: índice parcial em vez de índice cheio.
create index obs_avaliacoes_ruins_idx
  on public.obs_avaliacoes (avaliada_em desc, overall)
  where overall is not null and overall < 75;
-- Uma resposta é avaliada uma vez por origem. Sem isto, uma reentrega do
-- evento (retomada do buffer após falha de rede) dobraria a nota na média.
--
-- `nulls not distinct` e não `coalesce(span_id, '')`: o escritor regrava por
-- `upsert` com `on_conflict=trace_id,origem,span_id`, e o PostgREST precisa
-- encontrar um índice sobre essas três colunas — um índice sobre uma expressão
-- não serve para inferir o conflito. Sem a cláusula, duas linhas com `span_id`
-- nulo não colidiriam, que é justamente o caso mais comum (a avaliação da
-- interação inteira, sem span).
create unique index obs_avaliacoes_unica_idx
  on public.obs_avaliacoes (trace_id, origem, span_id) nulls not distinct;

-- ----------------------------------------------------------- versões de prompt
-- O que muda entre uma resposta boa e uma ruim, quando o modelo é o mesmo.
-- `versao_anterior` é o que permite a comparação par a par da tela: sem ela,
-- comparar v17 com v18 dependeria de alguém saber que uma veio da outra.
create table public.obs_prompt_versoes (
  prompt_id text not null check (char_length(prompt_id) between 1 and 80),
  versao text not null check (char_length(versao) between 1 and 20),
  publicada_em timestamptz not null default now(),
  commit text check (commit is null or char_length(commit) <= 40),
  app text,
  agente text,
  modelo text,
  versao_anterior text,
  notas text check (notas is null or char_length(notas) <= 2000),
  primary key (prompt_id, versao)
);

-- "Publicado nas últimas 24h" decide a amostragem: prompt novo é avaliado em
-- 100% até completar um dia.
create index obs_prompt_versoes_recentes_idx
  on public.obs_prompt_versoes (publicada_em desc);

-- ------------------------------------------------------------------- alertas
create table public.obs_alertas (
  id bigint generated always as identity primary key,
  regra text not null check (char_length(regra) between 1 and 60),
  titulo text not null check (char_length(titulo) between 1 and 200),
  severidade text not null check (severidade in ('aviso', 'critico')),
  disparado_em timestamptz not null default now(),
  resolvido_em timestamptz,
  valor numeric,
  limite numeric,
  janela_minutos integer,
  app text,
  agente text,
  -- Por onde já foi avisado: `{"app": true}` hoje, `{"whatsapp": "..."}`
  -- quando o canal existir. A coluna nasce agora para que ligar o WhatsApp
  -- depois não precise de migration.
  entregue jsonb not null default '{}'::jsonb,
  detalhes jsonb not null default '{}'::jsonb
);

-- Um alerta aberto por regra e por recorte. Sem esta trava, uma regra que
-- continua verdadeira a cada varredura viraria uma linha nova por minuto e a
-- tela mostraria "p95 alto" quarenta vezes em vez de uma vez, aberta há
-- quarenta minutos.
create unique index obs_alertas_abertos_idx
  on public.obs_alertas (regra, coalesce(app, ''), coalesce(agente, ''))
  where resolvido_em is null;
create index obs_alertas_recentes_idx
  on public.obs_alertas (disparado_em desc);

-- -------------------------------------------------------------------- rollup
-- A tela inicial pergunta sempre a mesma coisa sobre as últimas 24h, e é a
-- pergunta mais cara: percentis sobre a tabela de interações inteira. O rollup
-- responde por hora fechada, e a hora corrente sai do dado cru — assim a tela
-- é rápida sem ficar desatualizada.
--
-- `app` e `agente` são `''` e não `null` na chave: em Postgres duas linhas com
-- `null` não colidem, e a primária deixaria passar duplicata justamente do
-- recorte mais comum (interação sem app definido).
create table public.obs_rollup_horario (
  hora timestamptz not null,
  app text not null default '',
  agente text not null default '',
  interacoes integer not null default 0,
  erros integer not null default 0,
  duracao_media integer,
  duracao_p50 integer,
  duracao_p95 integer,
  duracao_p99 integer,
  tokens_total bigint not null default 0,
  custo_usd numeric(14, 6) not null default 0,
  chamadas_llm integer not null default 0,
  avaliacoes integer not null default 0,
  judge_overall numeric(5, 2),
  primary key (hora, app, agente)
);

create index obs_rollup_janela_idx on public.obs_rollup_horario (hora desc);

-- Recalcula as horas fechadas desde `p_desde`. Idempotente de propósito: rodar
-- duas vezes na mesma janela dá o mesmo resultado, então uma retomada depois
-- de falha não precisa saber onde parou.
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
alter table public.obs_avaliacoes enable row level security;
alter table public.obs_avaliacoes force row level security;
revoke all on public.obs_avaliacoes from anon, authenticated;

alter table public.obs_prompt_versoes enable row level security;
alter table public.obs_prompt_versoes force row level security;
revoke all on public.obs_prompt_versoes from anon, authenticated;

alter table public.obs_alertas enable row level security;
alter table public.obs_alertas force row level security;
revoke all on public.obs_alertas from anon, authenticated;

alter table public.obs_rollup_horario enable row level security;
alter table public.obs_rollup_horario force row level security;
revoke all on public.obs_rollup_horario from anon, authenticated;

revoke all on function public.obs_rollup_calcular(timestamptz) from public, anon, authenticated;

-- ------------------------------------------------------------------ retenção
-- A função nasceu na migration anterior com cinco tabelas; agora são nove. As
-- notas ficam o mesmo que as chamadas de modelo (90 dias) porque é com elas
-- que se comparam: uma nota sem a chamada que a gerou não responde nada. O
-- registro de versões de prompt e os alertas não expiram — são poucos, e são
-- a memória de "o que mudou e quando".
create or replace function public.obs_expurgar()
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.obs_spans where inicio < now() - interval '30 days';
  delete from public.obs_llm_chamadas where criado_em < now() - interval '90 days';
  delete from public.obs_avaliacoes where avaliada_em < now() - interval '90 days';
  delete from public.obs_interacoes where inicio < now() - interval '90 days';
  delete from public.obs_erros where ultima_ocorrencia < now() - interval '180 days';
  delete from public.obs_saude where hora < now() - interval '180 days';
  delete from public.obs_rollup_horario where hora < now() - interval '400 days';
$$;

revoke all on function public.obs_expurgar() from public, anon, authenticated;

commit;
