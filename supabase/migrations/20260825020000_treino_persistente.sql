-- Fichas pessoais de academia, exercícios ordenados e histórico de execução.

begin;

create table public.treinos (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  rotulo text not null check (char_length(btrim(rotulo)) between 1 and 12),
  titulo text not null check (char_length(btrim(titulo)) between 1 and 140),
  foco text not null default 'geral'
    check (char_length(btrim(foco)) between 1 and 80),
  descricao text check (descricao is null or char_length(descricao) <= 2000),
  cor text not null default '#ff6b1a'
    check (cor ~ '^#[0-9a-fA-F]{6}$'),
  ordem smallint not null default 0 check (ordem between 0 and 1000),
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (id, usuario_id)
);

create index treinos_usuario_idx
  on public.treinos (usuario_id, ativo desc, ordem, criado_em, id);

alter table public.treinos enable row level security;
alter table public.treinos force row level security;
revoke all on public.treinos from anon, authenticated;

create trigger treinos_atualizado_em
before update on public.treinos
for each row execute function public.definir_atualizado_em();

create table public.exercicios_treino (
  id uuid primary key default gen_random_uuid(),
  treino_id uuid not null,
  usuario_id uuid not null references auth.users(id) on delete cascade,
  nome text not null check (char_length(btrim(nome)) between 1 and 160),
  series text not null default '3'
    check (char_length(btrim(series)) between 1 and 40),
  repeticoes text not null default '8-12'
    check (char_length(btrim(repeticoes)) between 1 and 80),
  intervalo text not null default '90 s'
    check (char_length(btrim(intervalo)) between 1 and 80),
  carga text check (carga is null or char_length(carga) <= 80),
  observacao text check (observacao is null or char_length(observacao) <= 2000),
  video_url text check (video_url is null or char_length(video_url) <= 500),
  poster_url text check (poster_url is null or char_length(poster_url) <= 500),
  ordem smallint not null default 0 check (ordem between 0 and 1000),
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (id, usuario_id),
  foreign key (treino_id, usuario_id)
    references public.treinos(id, usuario_id) on delete cascade
);

create index exercicios_treino_ficha_idx
  on public.exercicios_treino (treino_id, ativo desc, ordem, criado_em, id);
create index exercicios_treino_usuario_idx
  on public.exercicios_treino (usuario_id, treino_id, ordem, id);

alter table public.exercicios_treino enable row level security;
alter table public.exercicios_treino force row level security;
revoke all on public.exercicios_treino from anon, authenticated;

create trigger exercicios_treino_atualizado_em
before update on public.exercicios_treino
for each row execute function public.definir_atualizado_em();

create table public.execucoes_treino (
  id uuid primary key default gen_random_uuid(),
  treino_id uuid not null,
  usuario_id uuid not null references auth.users(id) on delete cascade,
  data_execucao date not null,
  concluida_em timestamptz not null default now(),
  duracao_minutos smallint
    check (duracao_minutos is null or duracao_minutos between 1 and 600),
  observacao text check (observacao is null or char_length(observacao) <= 2000),
  treino_rotulo_snapshot text not null
    check (char_length(btrim(treino_rotulo_snapshot)) between 1 and 12),
  treino_titulo_snapshot text not null
    check (char_length(btrim(treino_titulo_snapshot)) between 1 and 140),
  criado_em timestamptz not null default now(),
  unique (treino_id, usuario_id, data_execucao),
  foreign key (treino_id, usuario_id)
    references public.treinos(id, usuario_id) on delete restrict
);

create index execucoes_treino_historico_idx
  on public.execucoes_treino (usuario_id, data_execucao desc, concluida_em desc, id);

alter table public.execucoes_treino enable row level security;
alter table public.execucoes_treino force row level security;
revoke all on public.execucoes_treino from anon, authenticated;

commit;
