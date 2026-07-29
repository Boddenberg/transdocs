begin;

-- Leitura e planejamento sobrevivem à página, a timeout e a redeploy ----------
create table if not exists public.trabalhos_preparacao_documentos (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  chave_idempotencia text not null
    check (char_length(chave_idempotencia) between 32 and 128),
  documento_ids jsonb not null default '[]'::jsonb
    check (jsonb_typeof(documento_ids) = 'array'),
  status text not null default 'pendente'
    check (status in ('pendente', 'processando', 'concluido', 'falhou')),
  fase text not null default 'na_fila'
    check (fase in ('na_fila', 'lendo', 'organizando', 'pronto')),
  total integer not null default 0 check (total >= 0),
  processados integer not null default 0
    check (processados >= 0 and processados <= total),
  resultado jsonb not null default
    '{"preparados":0,"falhas":0,"chunks":0}'::jsonb,
  plano jsonb,
  erro text,
  tentativas integer not null default 0 check (tentativas >= 0),
  disponivel_em timestamptz not null default now(),
  bloqueado_em timestamptz,
  worker_id text,
  concluido_em timestamptz,
  revisado_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (usuario_id, chave_idempotencia)
);

create index if not exists trabalhos_preparacao_fila_idx
  on public.trabalhos_preparacao_documentos
    (status, disponivel_em, criado_em);

create index if not exists trabalhos_preparacao_usuario_idx
  on public.trabalhos_preparacao_documentos
    (usuario_id, criado_em desc);

drop trigger if exists trabalhos_preparacao_atualizado_em
  on public.trabalhos_preparacao_documentos;
create trigger trabalhos_preparacao_atualizado_em
before update on public.trabalhos_preparacao_documentos
for each row execute function public.definir_atualizado_em();

alter table public.trabalhos_preparacao_documentos enable row level security;
alter table public.trabalhos_preparacao_documentos force row level security;

revoke all on public.trabalhos_preparacao_documentos from anon, authenticated;
grant select, insert, update, delete
  on public.trabalhos_preparacao_documentos to service_role;

-- Uma leitura pesada por vez em todas as réplicas. A concessão de 30 minutos
-- cobre o teto atual de páginas; se o processo cair, outro retoma do último
-- documento cujo progresso já foi gravado.
create or replace function public.reivindicar_trabalho_preparacao_documentos(
  p_worker_id text
)
returns setof public.trabalhos_preparacao_documentos
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  lock table public.trabalhos_preparacao_documentos
    in share row exclusive mode;

  return query
  with candidato as (
    select t.id
      from public.trabalhos_preparacao_documentos t
     where (
       (t.status = 'pendente' and t.disponivel_em <= now())
       or (
         t.status = 'processando'
         and t.bloqueado_em < now() - interval '30 minutes'
       )
     )
       and not exists (
         select 1
           from public.trabalhos_preparacao_documentos ativo
          where ativo.status = 'processando'
            and ativo.bloqueado_em >= now() - interval '30 minutes'
       )
     order by
       case when t.status = 'processando' then 0 else 1 end,
       t.criado_em
     limit 1
     for update skip locked
  )
  update public.trabalhos_preparacao_documentos trabalho
     set status = 'processando',
         fase = case
           when trabalho.processados < trabalho.total then 'lendo'
           else 'organizando'
         end,
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
  public.reivindicar_trabalho_preparacao_documentos(text)
  from public, anon, authenticated;
grant execute on function
  public.reivindicar_trabalho_preparacao_documentos(text)
  to service_role;

commit;
