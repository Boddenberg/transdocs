-- As caçadas que o celular mediu, para a Grade guardar as mesmas.
--
-- O jogo aceita uma sessão por conta: abrir as contas no telefone derruba a
-- Grade, e o que se caça pelo telefone (dez minutos olhando, ou a caçada
-- inteira na rua) ficava só no telefone. O pedido foi que o computador e o
-- celular sejam independentes e marquem a mesma coisa.
--
-- Uma linha por pessoa, sobrescrita: as caçadas recentes que o **celular**
-- mediu (os últimos dias), que a Grade junta ao histórico dela pela regra de
-- sempre — a sessão do analisador de um personagem mora num registro só, e
-- fica a leitura mais nova. Não é um segundo histórico: o histórico continua
-- no disco da Grade e no aparelho; aqui passa só o que falta a um do outro, e
-- a linha não cresce com o tempo.
--
-- A Grade descobre que há novidade pela resposta do `PUT /huntera/painel`
-- que ela já faz; nenhuma consulta a mais no dia a dia.
--
-- Pessoal como as outras do Huntera: RLS forçado e nada para `anon` nem
-- `authenticated`. Quem lê e grava é o backend, com a sessão de quem joga.

begin;

create table public.huntera_celular (
  usuario_id uuid primary key references auth.users(id) on delete cascade,
  cacadas jsonb not null,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

alter table public.huntera_celular enable row level security;
alter table public.huntera_celular force row level security;
revoke all on public.huntera_celular from anon, authenticated;

create trigger huntera_celular_atualizado_em
before update on public.huntera_celular
for each row execute function public.definir_atualizado_em();

commit;
