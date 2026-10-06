-- Os relatos de quem usa o produto (um erro, uma ideia), lidos no painel do
-- dono. Uma linha por relato, escrita só quando a pessoa manda — o painel não
-- grava nada para existir.
--
-- O índice de sessões vistas é o "quem está com o programa aberto agora": a
-- licença já toca `vista_em` a cada meia hora, e o painel só lê.

begin;

create table public.companion_relatos (
  id uuid primary key default gen_random_uuid(),
  conta_id uuid not null references public.companion_contas(id) on delete cascade,
  tipo text not null check (tipo in ('erro', 'ideia', 'outro')),
  texto text not null check (char_length(texto) between 3 and 2000),
  versao text check (versao is null or char_length(versao) <= 20),
  contexto jsonb not null default '{}'::jsonb check (pg_column_size(contexto) <= 4096),
  status text not null default 'novo' check (status in ('novo', 'visto', 'resolvido')),
  nota text check (nota is null or char_length(nota) <= 1000),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create index companion_relatos_status_idx on public.companion_relatos (status, criado_em desc);
create index companion_relatos_conta_idx on public.companion_relatos (conta_id, criado_em desc);

create index companion_sessoes_vistas_idx
  on public.companion_sessoes (vista_em desc) where encerrada_em is null;

alter table public.companion_relatos enable row level security;
alter table public.companion_relatos force row level security;

revoke all on public.companion_relatos from anon, authenticated;

commit;
