-- As contas do OT Idle, o jogo idle que se vende (`projetos/ot-idle`).
--
-- Como no companion, a conta não é do Supabase Auth: este projeto é
-- compartilhado com o FiNanças e com o transdocs, e um jogador com JWT do
-- GoTrue chegaria ao PostgREST com papel `authenticated` — e ao hub. Quem
-- joga cria e-mail e senha aqui, e o backend é o único que lê e grava.
--
-- **O personagem mora no servidor.** O save inteiro vai em `salvo` (o mesmo
-- JSON que o jogo guardava no navegador); `level` e `ficha` são a parte que a
-- lista de personagens mostra, para ela não carregar o save de ninguém.
--
-- **Um lugar por vez.** Cada vez que alguém entra com o personagem,
-- `otidle_entrar` soma um em `entrada` e devolve o número. O jogo só grava com
-- o número que recebeu: a aba ou o computador que ficou para trás leva um 409
-- e para, em vez de sobrescrever o progresso de quem entrou depois.
--
-- **O nome é do servidor inteiro**, sem diferença de maiúscula: como num
-- MMORPG, dois jogadores não têm o mesmo personagem.
--
-- Tudo com RLS forçado e nada para `anon` nem `authenticated`.

begin;

create table public.otidle_contas (
  id uuid primary key default gen_random_uuid(),
  email text not null check (email = lower(email) and char_length(email) between 5 and 254),
  senha_hash text not null,
  bloqueada_em timestamptz,
  criada_em timestamptz not null default now(),
  vista_em timestamptz
);

create unique index otidle_contas_email_idx on public.otidle_contas (email);

-- O token não mora aqui, só o hash dele.
create table public.otidle_sessoes (
  id uuid primary key default gen_random_uuid(),
  conta_id uuid not null references public.otidle_contas(id) on delete cascade,
  token_hash text not null unique,
  criada_em timestamptz not null default now(),
  vista_em timestamptz not null default now(),
  encerrada_em timestamptz,
  motivo_fim text check (motivo_fim is null or motivo_fim in ('saiu', 'bloqueada'))
);

create index otidle_sessoes_abertas_idx
  on public.otidle_sessoes (conta_id) where encerrada_em is null;

create table public.otidle_personagens (
  id uuid primary key default gen_random_uuid(),
  conta_id uuid not null references public.otidle_contas(id) on delete cascade,
  nome text not null check (char_length(nome) between 3 and 20),
  vocacao text not null check (vocacao in ('cavaleiro', 'paladino', 'feiticeiro', 'druida')),
  level integer not null default 1 check (level between 1 and 100000),
  ficha jsonb not null default '{}'::jsonb,
  salvo jsonb not null,
  entrada integer not null default 0,
  criado_em timestamptz not null default now(),
  salvo_em timestamptz not null default now()
);

create unique index otidle_personagens_nome_idx on public.otidle_personagens (lower(nome));
create index otidle_personagens_conta_idx on public.otidle_personagens (conta_id, criado_em);

alter table public.otidle_contas enable row level security;
alter table public.otidle_contas force row level security;
alter table public.otidle_sessoes enable row level security;
alter table public.otidle_sessoes force row level security;
alter table public.otidle_personagens enable row level security;
alter table public.otidle_personagens force row level security;

revoke all on public.otidle_contas, public.otidle_sessoes, public.otidle_personagens
  from anon, authenticated;

-- Entrar com o personagem: o número da entrada sobe numa linha só, e quem
-- tinha o número anterior perde o direito de gravar. Sem linha (o personagem
-- não existe ou é de outra conta), não devolve nada.
create or replace function public.otidle_entrar(p_conta uuid, p_personagem uuid)
returns table (salvo jsonb, entrada integer)
language sql
as $$
  update public.otidle_personagens as p
     set entrada = p.entrada + 1
   where p.id = p_personagem and p.conta_id = p_conta
  returning p.salvo, p.entrada;
$$;

revoke all on function public.otidle_entrar(uuid, uuid) from public, anon, authenticated;
grant execute on function public.otidle_entrar(uuid, uuid) to service_role;

commit;
