-- As perguntas da tela, escritas uma vez em SQL.
--
-- Por que funções e não `select` pelo PostgREST: percentil não é filtro, é
-- agregação com `within group`, e o PostgREST não a expõe. Fazer isso em
-- Python significaria trazer as interações da janela inteira pela rede para
-- ordenar na memória do processo — a conta mais cara da tela, feita no lugar
-- mais caro.
--
-- Todas são `security definer` com `search_path` vazio e sem `grant` para
-- `anon` nem `authenticated`, como o resto do módulo: quem lê é o backend com
-- a service role, e é o app de observabilidade que decide quem enxerga.
--
-- Nenhuma devolve texto de conversa. O que sai daqui são contagens, durações,
-- custos e notas — e, no caso do trace aberto, os atributos que a
-- instrumentação já gravou redigidos.

begin;

-- ------------------------------------------------------------------ panorama
-- A manchete: as últimas N horas em oito números. Lê do rollup nas horas
-- fechadas e do dado cru na hora corrente — a soma é rápida e não atrasa.
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
    select avg(overall)::numeric as media, count(*) as total
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
    'chamadas_llm', (select coalesce(sum(chamadas_llm), 0) from janela),
    'judge_overall', (select round(media, 1) from notas),
    'avaliacoes', (select total from notas),
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

-- ------------------------------------------------------- recortes da tela
-- Os cartões por domínio, e o mesmo formato serve para app e para agente: a
-- tela desenha uma lista só, e o drill-down troca a dimensão.
create or replace function public.obs_por_dimensao(
  p_dimensao text,
  p_desde timestamptz,
  p_ate timestamptz default null
)
returns table (
  chave text,
  interacoes bigint,
  erros bigint,
  duracao_media integer,
  p95 integer,
  custo_usd numeric,
  judge_overall numeric,
  avaliacoes bigint
)
language sql
stable
security definer
set search_path = ''
as $$
  with janela as (
    select case when p_dimensao = 'agente' then coalesce(i.agente, '(sem agente)')
                when p_dimensao = 'canal' then i.canal
                else coalesce(i.app, '(hub)') end as chave,
           i.*
      from public.obs_interacoes i
     where i.inicio >= p_desde and i.inicio < coalesce(p_ate, now())
  ),
  notas as (
    select case when p_dimensao = 'agente' then coalesce(a.agente, '(sem agente)')
                when p_dimensao = 'canal' then coalesce(a.canal, '')
                else coalesce(a.app, '(hub)') end as chave,
           avg(a.overall)::numeric as media,
           count(*) as total
      from public.obs_avaliacoes a
     where a.avaliada_em >= p_desde and a.avaliada_em < coalesce(p_ate, now())
       and a.overall is not null
     group by 1
  )
  select j.chave,
         count(*),
         count(*) filter (where j.status = 'erro'),
         round(avg(j.duracao_ms))::integer,
         percentile_disc(0.95) within group (order by j.duracao_ms)::integer,
         coalesce(sum(j.custo_usd), 0),
         round(max(n.media), 1),
         coalesce(max(n.total), 0)
    from janela j
    left join notas n on n.chave = j.chave
   group by j.chave
   order by count(*) desc;
$$;

-- --------------------------------------------------------------- endpoints
-- "Qual endpoint está falhando?" O caminho e o status moram nos atributos da
-- interação, gravados pelo middleware — não há tabela de requisição separada,
-- e não precisa haver: uma requisição HTTP **é** uma interação.
create or replace function public.obs_endpoints(
  p_desde timestamptz,
  p_ate timestamptz default null,
  p_limite integer default 40
)
returns table (
  metodo text,
  caminho text,
  requisicoes bigint,
  erros bigint,
  p95 integer,
  status_ruins bigint
)
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(i.atributos ->> 'http_metodo', '?'),
         coalesce(i.atributos ->> 'http_caminho', '?'),
         count(*),
         count(*) filter (where i.status = 'erro'),
         percentile_disc(0.95) within group (order by i.duracao_ms)::integer,
         count(*) filter (
           where (i.atributos ->> 'http_status') ~ '^[45]'
         )
    from public.obs_interacoes i
   where i.inicio >= p_desde and i.inicio < coalesce(p_ate, now())
     and i.atributos ? 'http_caminho'
   group by 1, 2
   order by count(*) filter (where i.status = 'erro') desc, count(*) desc
   limit greatest(p_limite, 1);
$$;

-- --------------------------------------------------------------- ferramentas
-- "Qual tool está dando timeout?" Vem dos spans, que é onde a tool aparece com
-- duração e status próprios.
create or replace function public.obs_ferramentas(
  p_desde timestamptz,
  p_ate timestamptz default null
)
returns table (
  ferramenta text,
  execucoes bigint,
  erros bigint,
  timeouts bigint,
  duracao_media integer,
  p95 integer
)
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(s.atributos ->> 'ferramenta', s.nome),
         count(*),
         count(*) filter (where s.status = 'erro'),
         count(*) filter (where s.status = 'timeout'),
         round(avg(s.duracao_ms))::integer,
         percentile_disc(0.95) within group (order by s.duracao_ms)::integer
    from public.obs_spans s
   where s.tipo = 'tool'
     and s.inicio >= p_desde and s.inicio < coalesce(p_ate, now())
   group by 1
   order by count(*) filter (where s.status <> 'ok') desc, count(*) desc;
$$;

-- ------------------------------------------------------------------- modelos
-- "Qual modelo está sendo mais usado" e "quanto custa cada um".
create or replace function public.obs_modelos(
  p_desde timestamptz,
  p_ate timestamptz default null
)
returns table (
  modelo text,
  chamadas bigint,
  tokens_entrada bigint,
  tokens_saida bigint,
  custo_usd numeric,
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
         coalesce(sum(c.custo_usd), 0),
         round(avg(c.duracao_ms))::integer,
         percentile_disc(0.95) within group (order by c.duracao_ms)::integer,
         count(*) filter (where c.tentativas > 1),
         count(*) filter (where c.erro is not null)
    from public.obs_llm_chamadas c
   where c.criado_em >= p_desde and c.criado_em < coalesce(p_ate, now())
   group by c.modelo
   order by coalesce(sum(c.custo_usd), 0) desc;
$$;

-- -------------------------------------------------------------------- custos
-- A série que a tela de custo desenha, com o grão que ela pedir. `p_grao`
-- passa por `date_trunc`, então só os valores que ele aceita entram — a
-- validação está aqui e não na tela para que uma chamada direta ao banco não
-- consiga injetar outra coisa.
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
  custo_por_interacao numeric
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
              else round(coalesce(sum(i.custo_usd), 0) / count(*), 6) end
    from public.obs_interacoes i
   where i.inicio >= p_desde and i.inicio < coalesce(p_ate, now())
   group by 1
   order by 1;
$$;

-- ------------------------------------------------------------------- traces
-- A lista da tela de inspeção. Os filtros são todos opcionais e todos `null`
-- por padrão: a tela manda o que o operador marcou, e o que ele não marcou não
-- estreita nada.
create or replace function public.obs_traces(
  p_desde timestamptz,
  p_ate timestamptz default null,
  p_app text default null,
  p_agente text default null,
  p_canal text default null,
  p_modelo text default null,
  p_ferramenta text default null,
  p_prompt_versao text default null,
  p_so_erros boolean default false,
  p_judge_abaixo integer default null,
  p_duracao_acima integer default null,
  p_custo_acima numeric default null,
  p_limite integer default 100
)
returns table (
  trace_id text,
  inicio timestamptz,
  duracao_ms integer,
  canal text,
  app text,
  agente text,
  status text,
  tokens_total integer,
  custo_usd numeric,
  chamadas_llm smallint,
  erro_assinatura text,
  judge_overall smallint,
  http_status text
)
language sql
stable
security definer
set search_path = ''
as $$
  select i.trace_id, i.inicio, i.duracao_ms, i.canal, i.app, i.agente, i.status,
         i.tokens_total, i.custo_usd, i.chamadas_llm, i.erro_assinatura,
         a.overall,
         i.atributos ->> 'http_status'
    from public.obs_interacoes i
    left join lateral (
      select overall from public.obs_avaliacoes
       where trace_id = i.trace_id and overall is not null
       order by avaliada_em desc limit 1
    ) a on true
   where i.inicio >= p_desde and i.inicio < coalesce(p_ate, now())
     and (p_app is null or i.app = p_app)
     and (p_agente is null or i.agente = p_agente)
     and (p_canal is null or i.canal = p_canal)
     and (not p_so_erros or i.status <> 'ok')
     and (p_duracao_acima is null or i.duracao_ms >= p_duracao_acima)
     and (p_custo_acima is null or i.custo_usd >= p_custo_acima)
     and (p_judge_abaixo is null or (a.overall is not null and a.overall < p_judge_abaixo))
     and (p_prompt_versao is null or p_prompt_versao = any (i.prompt_versoes))
     and (p_modelo is null or exists (
           select 1 from public.obs_llm_chamadas c
            where c.trace_id = i.trace_id and c.modelo = p_modelo))
     and (p_ferramenta is null or exists (
           select 1 from public.obs_spans s
            where s.trace_id = i.trace_id and s.tipo = 'tool'
              and coalesce(s.atributos ->> 'ferramenta', s.nome) = p_ferramenta))
   order by i.inicio desc
   limit least(greatest(p_limite, 1), 500);
$$;

-- A interação aberta: a timeline inteira num objeto só, para a tela não fazer
-- cinco idas ao banco para desenhar uma tela.
create or replace function public.obs_trace(p_trace_id text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'interacao', (
      select to_jsonb(i) from public.obs_interacoes i where i.trace_id = p_trace_id
    ),
    'spans', coalesce((
      select jsonb_agg(to_jsonb(s) order by s.inicio)
        from public.obs_spans s where s.trace_id = p_trace_id
    ), '[]'::jsonb),
    'llm', coalesce((
      select jsonb_agg(to_jsonb(c) order by c.criado_em)
        from public.obs_llm_chamadas c where c.trace_id = p_trace_id
    ), '[]'::jsonb),
    'avaliacoes', coalesce((
      select jsonb_agg(to_jsonb(a) order by a.avaliada_em)
        from public.obs_avaliacoes a where a.trace_id = p_trace_id
    ), '[]'::jsonb),
    'erro', (
      select to_jsonb(e) from public.obs_erros e
       where e.assinatura = (
         select erro_assinatura from public.obs_interacoes where trace_id = p_trace_id
       )
    )
  );
$$;

-- ----------------------------------------------------------------- qualidade
-- A tela de qualidade e a pergunta "por que estamos perdendo pontos?", que é
-- a contagem das sinalizações — não uma interpretação de texto.
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
  with janela as (
    select * from public.obs_avaliacoes
     where avaliada_em >= p_desde and avaliada_em < coalesce(p_ate, now())
       and (p_app is null or app = p_app)
       and (p_agente is null or agente = p_agente)
       and (p_prompt_id is null or prompt_id = p_prompt_id)
  )
  select jsonb_build_object(
    'avaliacoes', (select count(*) from janela),
    'judge', (select count(*) from janela where origem = 'judge'),
    'regra', (select count(*) from janela where origem = 'regra'),
    'dimensoes', (
      select jsonb_build_object(
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
               'app', app, 'avaliada_em', avaliada_em, 'sinalizacoes', sinalizacoes)
             order by overall)
        from (select * from janela where overall is not null
               order by overall limit 20) p
    ), '[]'::jsonb)
  );
$$;

-- ------------------------------------------------------- comparação de prompt
-- "A v18 melhorou ou piorou?" — uma linha por versão, com o que a versão
-- custou e o que ela entregou, lado a lado.
create or replace function public.obs_comparar_prompt(p_prompt_id text)
returns table (
  versao text,
  publicada_em timestamptz,
  commit text,
  versao_anterior text,
  avaliacoes bigint,
  naturalness numeric,
  correctness numeric,
  context_usage numeric,
  verbosity numeric,
  tone_fit numeric,
  tool_grounding numeric,
  safety numeric,
  overall numeric,
  chamadas bigint,
  duracao_media integer,
  custo_usd numeric
)
language sql
stable
security definer
set search_path = ''
as $$
  select v.versao, v.publicada_em, v.commit, v.versao_anterior,
         coalesce(a.total, 0),
         a.naturalness, a.correctness, a.context_usage, a.verbosity,
         a.tone_fit, a.tool_grounding, a.safety, a.overall,
         coalesce(c.chamadas, 0), c.duracao_media, coalesce(c.custo_usd, 0)
    from public.obs_prompt_versoes v
    left join lateral (
      select count(*) as total,
             round(avg(naturalness)::numeric, 2) as naturalness,
             round(avg(correctness)::numeric, 2) as correctness,
             round(avg(context_usage)::numeric, 2) as context_usage,
             round(avg(verbosity)::numeric, 2) as verbosity,
             round(avg(tone_fit)::numeric, 2) as tone_fit,
             round(avg(tool_grounding)::numeric, 2) as tool_grounding,
             round(avg(safety)::numeric, 2) as safety,
             round(avg(overall)::numeric, 1) as overall
        from public.obs_avaliacoes
       where prompt_id = v.prompt_id and prompt_versao = v.versao
    ) a on true
    left join lateral (
      select count(*) as chamadas,
             round(avg(duracao_ms))::integer as duracao_media,
             sum(custo_usd) as custo_usd
        from public.obs_llm_chamadas
       where prompt_id = v.prompt_id and prompt_versao = v.versao
    ) c on true
   where v.prompt_id = p_prompt_id
   order by v.publicada_em desc;
$$;

-- ------------------------------------------------------------------ segurança
revoke all on function public.obs_panorama(timestamptz, timestamptz) from public, anon, authenticated;
revoke all on function public.obs_por_dimensao(text, timestamptz, timestamptz) from public, anon, authenticated;
revoke all on function public.obs_endpoints(timestamptz, timestamptz, integer) from public, anon, authenticated;
revoke all on function public.obs_ferramentas(timestamptz, timestamptz) from public, anon, authenticated;
revoke all on function public.obs_modelos(timestamptz, timestamptz) from public, anon, authenticated;
revoke all on function public.obs_custos(timestamptz, text, timestamptz) from public, anon, authenticated;
revoke all on function public.obs_traces(timestamptz, timestamptz, text, text, text, text, text, text, boolean, integer, integer, numeric, integer) from public, anon, authenticated;
revoke all on function public.obs_trace(text) from public, anon, authenticated;
revoke all on function public.obs_qualidade(timestamptz, timestamptz, text, text, text) from public, anon, authenticated;
revoke all on function public.obs_comparar_prompt(text) from public, anon, authenticated;

commit;
