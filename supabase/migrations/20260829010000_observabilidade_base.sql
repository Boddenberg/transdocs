-- As tabelas da observabilidade do hub (fase 1 da ADR 0008).
--
-- Cinco tabelas e nenhuma tecnologia nova: a escala projetada — ~2.000
-- interações/dia, 8 spans e 4 chamadas de modelo cada — cabe folgada em
-- Postgres com índice, e o que precisa ser rápido (a tela inicial) sai de
-- rollup, não de um banco diferente.
--
-- O que **não** existe aqui é a parte importante: não há coluna para o texto
-- do prompt, para a mensagem da pessoa nem para `usuario_id`. O que identifica
-- alguém é `usuario_hash`, um HMAC com segredo que não está no banco. A tela
-- de traces é ferramenta de depuração, e o schema é onde isso deixa de ser
-- promessa e vira estrutura.
--
-- Nenhuma tabela referencia `auth.users`: apagar uma conta não pode apagar o
-- histórico de custo do mês, e o hash já é anônimo o bastante para ficar.

begin;

-- ------------------------------------------------------------------ interações
create table public.obs_interacoes (
  trace_id text primary key check (trace_id ~ '^[0-9a-f]{32}$'),
  inicio timestamptz not null,
  fim timestamptz not null,
  duracao_ms integer not null check (duracao_ms >= 0),
  canal text not null check (char_length(canal) between 1 and 40),
  status text not null check (status in ('ok', 'erro', 'parcial')),
  app text check (app is null or char_length(app) <= 40),
  agente text check (agente is null or char_length(agente) <= 60),
  usuario_hash text check (usuario_hash is null or usuario_hash ~ '^[0-9a-f]{16}$'),
  ambito text check (ambito is null or ambito in ('pessoal', 'casal')),
  erro_assinatura text,
  tokens_total integer not null default 0 check (tokens_total >= 0),
  custo_usd numeric(12, 6) not null default 0 check (custo_usd >= 0),
  chamadas_llm smallint not null default 0 check (chamadas_llm >= 0),
  prompt_versoes text[] not null default '{}',
  ambiente text not null default 'local',
  versao_app text not null default '',
  atributos jsonb not null default '{}'::jsonb,
  criado_em timestamptz not null default now()
);

-- A tela inicial pergunta sempre a mesma coisa: as últimas 24h, por app.
create index obs_interacoes_janela_idx
  on public.obs_interacoes (inicio desc, app, agente);
create index obs_interacoes_erro_idx
  on public.obs_interacoes (status, inicio desc)
  where status <> 'ok';
-- "Quanto gastamos hoje" e "qual agente está mais lento" leem daqui.
create index obs_interacoes_custo_idx
  on public.obs_interacoes (inicio desc, custo_usd desc);

-- ---------------------------------------------------------------------- spans
create table public.obs_spans (
  span_id text not null check (span_id ~ '^[0-9a-f]{16}$'),
  trace_id text not null check (trace_id ~ '^[0-9a-f]{32}$'),
  span_pai_id text check (span_pai_id is null or span_pai_id ~ '^[0-9a-f]{16}$'),
  nome text not null check (char_length(nome) between 1 and 120),
  tipo text not null check (
    tipo in ('http', 'router', 'memoria', 'agente', 'llm', 'tool',
             'voz', 'whatsapp', 'db', 'externa', 'judge')
  ),
  inicio timestamptz not null,
  fim timestamptz not null,
  duracao_ms integer not null check (duracao_ms >= 0),
  status text not null default 'ok' check (status in ('ok', 'erro', 'timeout')),
  atributos jsonb not null default '{}'::jsonb,
  criado_em timestamptz not null default now(),
  primary key (trace_id, span_id)
);

-- Abrir uma interação é ler todos os spans dela na ordem: este índice é a
-- timeline inteira em uma varredura.
create index obs_spans_timeline_idx on public.obs_spans (trace_id, inicio);
-- "Qual tool está dando timeout" e "qual agente está mais lento".
create index obs_spans_tipo_idx on public.obs_spans (tipo, inicio desc, duracao_ms desc);

-- Sem FK para `obs_interacoes`: os spans chegam **antes** do resumo da
-- interação (ela só fecha no fim), e uma FK recusaria o lote inteiro. A
-- integridade aqui é eventual de propósito — perder o vínculo de um span é
-- barato, perder o lote não é.

-- --------------------------------------------------------------- chamadas LLM
create table public.obs_llm_chamadas (
  id uuid primary key default gen_random_uuid(),
  trace_id text not null check (trace_id ~ '^[0-9a-f]{32}$'),
  span_id text check (span_id is null or span_id ~ '^[0-9a-f]{16}$'),
  operacao text not null check (char_length(operacao) between 1 and 80),
  modelo text not null check (char_length(modelo) between 1 and 80),
  duracao_ms integer not null check (duracao_ms >= 0),
  app text,
  agente text,
  prompt_id text,
  prompt_versao text,
  tokens_entrada integer check (tokens_entrada is null or tokens_entrada >= 0),
  tokens_saida integer check (tokens_saida is null or tokens_saida >= 0),
  tokens_total integer check (tokens_total is null or tokens_total >= 0),
  custo_usd numeric(12, 6) check (custo_usd is null or custo_usd >= 0),
  tentativas smallint not null default 1 check (tentativas between 1 and 10),
  houve_reescrita boolean not null default false,
  tamanho_historico smallint check (tamanho_historico is null or tamanho_historico >= 0),
  qtd_memorias smallint check (qtd_memorias is null or qtd_memorias >= 0),
  tool_calls smallint check (tool_calls is null or tool_calls >= 0),
  erro text,
  criado_em timestamptz not null default now()
);

create index obs_llm_trace_idx on public.obs_llm_chamadas (trace_id);
-- "Qual modelo está sendo mais usado" e "quanto custa cada agente".
create index obs_llm_custo_idx
  on public.obs_llm_chamadas (criado_em desc, modelo, agente);
-- Comparar v17 × v18 sem varrer a tabela — mesmo motivo do índice que a Têmis
-- já criou em `decisoes_ocorrencias_casa`.
create index obs_llm_versao_idx
  on public.obs_llm_chamadas (prompt_versao, criado_em desc)
  where prompt_versao is not null;

-- --------------------------------------------------------------------- erros
-- Uma linha por **assinatura**, não por ocorrência: "12x Timeout WhatsApp" é
-- uma linha que contou até doze. Guardar as doze só encheria a tela com a
-- mesma informação, e a última ocorrência é a que importa para depurar.
create table public.obs_erros (
  assinatura text primary key check (char_length(assinatura) between 8 and 64),
  tipo text not null,
  mensagem_redigida text not null,
  primeira_ocorrencia timestamptz not null,
  ultima_ocorrencia timestamptz not null,
  frequencia integer not null default 1 check (frequencia > 0),
  app text,
  agente text,
  endpoint text,
  ferramenta text,
  modelo text,
  prompt_versao text,
  exemplo_trace_id text,
  stack_redigido text
);

create index obs_erros_recentes_idx
  on public.obs_erros (ultima_ocorrencia desc, frequencia desc);

-- O escritor manda uma linha por ocorrência; o agrupamento acontece aqui, para
-- que ele continue sendo um `insert` em lote e nada mais. Sem esta função, o
-- worker precisaria ler antes de escrever — uma ida a mais ao banco por erro.
create or replace function public.obs_registrar_erro(p_erro jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.obs_erros (
    assinatura, tipo, mensagem_redigida, primeira_ocorrencia,
    ultima_ocorrencia, frequencia, app, agente, endpoint, ferramenta,
    modelo, prompt_versao, exemplo_trace_id, stack_redigido
  )
  values (
    p_erro ->> 'assinatura',
    p_erro ->> 'tipo',
    p_erro ->> 'mensagem_redigida',
    (p_erro ->> 'ocorrido_em')::timestamptz,
    (p_erro ->> 'ocorrido_em')::timestamptz,
    1,
    p_erro ->> 'app',
    p_erro ->> 'agente',
    p_erro ->> 'endpoint',
    p_erro ->> 'ferramenta',
    p_erro ->> 'modelo',
    p_erro ->> 'prompt_versao',
    p_erro ->> 'trace_id',
    p_erro ->> 'stack_redigido'
  )
  on conflict (assinatura) do update
     set frequencia = public.obs_erros.frequencia + 1,
         ultima_ocorrencia = greatest(
           public.obs_erros.ultima_ocorrencia,
           (p_erro ->> 'ocorrido_em')::timestamptz
         ),
         -- O exemplo aponta para a ocorrência mais recente: é a que ainda tem
         -- spans dentro da retenção para abrir junto.
         exemplo_trace_id = coalesce(p_erro ->> 'trace_id',
                                     public.obs_erros.exemplo_trace_id),
         stack_redigido = coalesce(p_erro ->> 'stack_redigido',
                                   public.obs_erros.stack_redigido);
end;
$$;

-- --------------------------------------------------------------------- saúde
-- A observabilidade da observabilidade. Sem isto, a tela responde "zero erros
-- hoje" quando a verdade é "não recebi nada hoje".
create table public.obs_saude (
  hora timestamptz primary key,
  eventos_recebidos integer not null default 0,
  eventos_perdidos integer not null default 0,
  falhas_persistencia integer not null default 0,
  fila_maxima integer not null default 0,
  tempo_processamento_ms integer not null default 0,
  erros_judge integer not null default 0,
  modelos_sem_preco text[] not null default '{}'
);

-- ------------------------------------------------------------------ segurança
-- Mesma trava das outras 112 migrations: nada aqui é legível por `anon` nem por
-- `authenticated`. A leitura passa pelo backend, com a service role, e o app de
-- observabilidade decide quem vê o quê.
alter table public.obs_interacoes enable row level security;
alter table public.obs_interacoes force row level security;
revoke all on public.obs_interacoes from anon, authenticated;

alter table public.obs_spans enable row level security;
alter table public.obs_spans force row level security;
revoke all on public.obs_spans from anon, authenticated;

alter table public.obs_llm_chamadas enable row level security;
alter table public.obs_llm_chamadas force row level security;
revoke all on public.obs_llm_chamadas from anon, authenticated;

alter table public.obs_erros enable row level security;
alter table public.obs_erros force row level security;
revoke all on public.obs_erros from anon, authenticated;

alter table public.obs_saude enable row level security;
alter table public.obs_saude force row level security;
revoke all on public.obs_saude from anon, authenticated;

revoke all on function public.obs_registrar_erro(jsonb) from public, anon, authenticated;

-- ------------------------------------------------------------------ retenção
-- Retenção por tabela, não uma só para tudo: span é volumoso e envelhece
-- rápido; custo precisa fechar o mês. Roda pelo backend (fase 3), mas a função
-- nasce junto com as tabelas para que a promessa de retenção não fique
-- dependendo de alguém lembrar dela depois.
create or replace function public.obs_expurgar()
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.obs_spans where inicio < now() - interval '30 days';
  delete from public.obs_llm_chamadas where criado_em < now() - interval '90 days';
  delete from public.obs_interacoes where inicio < now() - interval '90 days';
  delete from public.obs_erros where ultima_ocorrencia < now() - interval '180 days';
  delete from public.obs_saude where hora < now() - interval '180 days';
$$;

revoke all on function public.obs_expurgar() from public, anon, authenticated;

commit;
