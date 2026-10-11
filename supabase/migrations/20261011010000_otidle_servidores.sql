-- Os servidores do OT Idle: o de testes (o que já existia) e o beta, depois o
-- oficial. Como os mundos do Tibia, a conta entra em todos e cada servidor tem
-- os seus personagens: a lista, o nome único, o teto de personagens por conta e
-- o entrar só olham o servidor que pediu (o servidor de jogo manda o nome dele
-- em `X-OtIdle-Servidor`; sem o cabeçalho, o de testes).
--
-- Os personagens e as caçadas medidas de antes ficam no de testes.

begin;

alter table public.otidle_personagens
  add column servidor text not null default 'teste'
  check (servidor ~ '^[a-z][a-z0-9-]{1,19}$');

-- O nome passa a ser único dentro do servidor.
drop index public.otidle_personagens_nome_idx;
create unique index otidle_personagens_nome_idx
  on public.otidle_personagens (servidor, lower(nome));

drop index public.otidle_personagens_conta_idx;
create index otidle_personagens_conta_idx
  on public.otidle_personagens (conta_id, servidor, criado_em);

alter table public.otidle_cacadas
  add column servidor text not null default 'teste'
  check (servidor ~ '^[a-z][a-z0-9-]{1,19}$');

create index otidle_cacadas_servidor_idx on public.otidle_cacadas (servidor, inicio desc);

-- Entrar pelo servidor: o personagem de outro servidor não existe para quem pede.
-- A versão de dois argumentos fica até o backend novo estar no ar.
create or replace function public.otidle_entrar(p_conta uuid, p_personagem uuid, p_servidor text)
returns table (salvo jsonb, entrada integer)
language sql
as $$
  update public.otidle_personagens as p
     set entrada = p.entrada + 1
   where p.id = p_personagem and p.conta_id = p_conta and p.servidor = p_servidor
  returning p.salvo, p.entrada;
$$;

revoke all on function public.otidle_entrar(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.otidle_entrar(uuid, uuid, text) to service_role;

commit;
