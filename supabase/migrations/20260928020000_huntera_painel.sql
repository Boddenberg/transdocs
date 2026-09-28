-- O Huntera ganha a primeira tabela: a última foto da Grade, para o celular.
--
-- A Grade (o programa do computador, `projetos/grade-idle`) continua sendo
-- quem lê o jogo e faz todas as contas; o histórico das caçadas segue no disco
-- dela. O que passa a morar aqui é só o **último retrato** do que ela mostra —
-- o time, cada personagem, os drops em foco e o resumo do bestiário — para a
-- porta Huntera do telefone mostrar a mesma coisa com o computador longe.
--
-- Uma linha por pessoa, sobrescrita a cada envio: não é histórico, e guardar
-- uma fila de retratos seria inventar um segundo registro das caçadas que
-- pode divergir do da Grade. O conteúdo é um `jsonb` opaco, com teto de
-- tamanho no backend, porque o formato é o da tela e muda junto com ela.
--
-- Pessoal como o resto: RLS forçado e nada para `anon` nem `authenticated`.
-- Quem lê e grava é o backend, com a sessão de quem joga.

begin;

create table public.huntera_painel (
  usuario_id uuid primary key references auth.users(id) on delete cascade,
  painel jsonb not null,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

alter table public.huntera_painel enable row level security;
alter table public.huntera_painel force row level security;
revoke all on public.huntera_painel from anon, authenticated;

create trigger huntera_painel_atualizado_em
before update on public.huntera_painel
for each row execute function public.definir_atualizado_em();

commit;
