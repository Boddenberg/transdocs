begin;

-- O clique confirma rapido; o trabalho sobrevive a timeout e redeploy ----------
create table if not exists public.trabalhos_organizacao_documentos (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  chave_idempotencia text not null
    check (char_length(chave_idempotencia) between 32 and 128),
  decisao jsonb not null,
  status text not null default 'pendente'
    check (status in ('pendente', 'processando', 'concluido', 'falhou')),
  total integer not null default 0 check (total >= 0),
  processados integer not null default 0
    check (processados >= 0 and processados <= total),
  resultado jsonb not null default
    '{"aplicados":0,"recusados":0,"pastas_criadas":0}'::jsonb,
  erro text,
  tentativas integer not null default 0 check (tentativas >= 0),
  disponivel_em timestamptz not null default now(),
  bloqueado_em timestamptz,
  worker_id text,
  concluido_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (usuario_id, chave_idempotencia)
);

create index if not exists trabalhos_organizacao_fila_idx
  on public.trabalhos_organizacao_documentos
    (status, disponivel_em, criado_em);

create index if not exists trabalhos_organizacao_usuario_idx
  on public.trabalhos_organizacao_documentos
    (usuario_id, criado_em desc);

drop trigger if exists trabalhos_organizacao_atualizado_em
  on public.trabalhos_organizacao_documentos;
create trigger trabalhos_organizacao_atualizado_em
before update on public.trabalhos_organizacao_documentos
for each row execute function public.definir_atualizado_em();

alter table public.trabalhos_organizacao_documentos enable row level security;
alter table public.trabalhos_organizacao_documentos force row level security;

-- A tabela nunca vai direto ao navegador. A API filtra usuario_id e usa a
-- service role; manter anon/authenticated sem privilegios reduz a superficie.
revoke all on public.trabalhos_organizacao_documentos from anon, authenticated;
grant select, insert, update, delete
  on public.trabalhos_organizacao_documentos to service_role;

-- Claim atomico com uma concessao de dez minutos. O lock curto serializa apenas
-- a escolha: depois do commit o worker processa fora do banco. Assim varias
-- replicas do Railway continuam tendo concorrencia GLOBAL igual a um.
create or replace function public.reivindicar_trabalho_organizacao_documentos(
  p_worker_id text
)
returns setof public.trabalhos_organizacao_documentos
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  lock table public.trabalhos_organizacao_documentos
    in share row exclusive mode;

  return query
  with candidato as (
    select t.id
      from public.trabalhos_organizacao_documentos t
     where (
       (t.status = 'pendente' and t.disponivel_em <= now())
       or (
         t.status = 'processando'
         and t.bloqueado_em < now() - interval '10 minutes'
       )
     )
       and not exists (
         select 1
           from public.trabalhos_organizacao_documentos ativo
          where ativo.status = 'processando'
            and ativo.bloqueado_em >= now() - interval '10 minutes'
       )
     order by
       case when t.status = 'processando' then 0 else 1 end,
       t.criado_em
     limit 1
     for update skip locked
  )
  update public.trabalhos_organizacao_documentos trabalho
     set status = 'processando',
         worker_id = p_worker_id,
         bloqueado_em = now(),
         tentativas = trabalho.tentativas + 1,
         erro = null
    from candidato
   where trabalho.id = candidato.id
  returning trabalho.*;
end;
$$;

revoke all on function
  public.reivindicar_trabalho_organizacao_documentos(text)
  from public, anon, authenticated;
grant execute on function
  public.reivindicar_trabalho_organizacao_documentos(text)
  to service_role;

commit;
