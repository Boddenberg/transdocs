-- As caçadas do OT Idle medidas uma a uma (o servidor de testes).
--
-- O servidor de jogo grava uma linha quando a caçada fecha (online ou a de
-- fora, a offline): quanto rendeu, como o personagem entrou (level, skills,
-- equipamento, árvore, prey, bestiário…) e o que ele ganhou de progresso no
-- caminho. É o material para entender o que precisa ser refeito no balanço.
--
-- **Uma linha por caçada, nunca por minuto.** A queda de 20/09/2026 foi
-- telemetria duplicada enchendo o disco: aqui o `id` nasce no servidor de
-- jogo e o insert ignora o repetido, então reenviar um lote não duplica nada.
-- O backend apaga o que passou de 180 dias.
--
-- Sem chave estrangeira para o personagem: excluir o personagem não apaga a
-- medida (o `nome` e a `vocacao` ficam na linha).
--
-- Tudo com RLS forçado e nada para `anon` nem `authenticated`.

begin;

create table public.otidle_cacadas (
  id uuid primary key,
  personagem_id uuid,
  conta_id uuid,
  nome text not null check (char_length(nome) between 1 and 40),
  vocacao text not null check (char_length(vocacao) between 1 and 20),
  level integer not null check (level between 1 and 100000),
  cacada text not null check (char_length(cacada) between 1 and 60),
  -- cacada, boss, arena, invasao, sandbox
  tipo text not null check (char_length(tipo) between 1 and 20),
  dificuldade text check (dificuldade is null or char_length(dificuldade) <= 20),
  origem text not null check (origem in ('online', 'offline')),
  grupo smallint not null default 1 check (grupo between 1 and 8),
  versao text not null default '' check (char_length(versao) <= 60),
  inicio timestamptz not null,
  duracao_ms integer not null check (duracao_ms >= 0),
  exp bigint not null default 0,
  lucro bigint not null default 0,
  mortes smallint not null default 0 check (mortes >= 0),
  dados jsonb not null default '{}'::jsonb,
  criado_em timestamptz not null default now()
);

create index otidle_cacadas_inicio_idx on public.otidle_cacadas (inicio desc);
create index otidle_cacadas_cacada_idx on public.otidle_cacadas (cacada, inicio desc);
create index otidle_cacadas_personagem_idx on public.otidle_cacadas (personagem_id, inicio desc);

alter table public.otidle_cacadas enable row level security;
alter table public.otidle_cacadas force row level security;

revoke all on public.otidle_cacadas from anon, authenticated;

commit;
