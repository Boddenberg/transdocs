begin;

-- A gaveta mostra quando um arquivo é fonte de outro app --------------------
--
-- A referência real continua na tabela do app consumidor. A view só reúne
-- essas relações num contrato pequeno para Documentos poder dizer "usado por
-- Finanças" ou "usado por Culinária" sem manter uma segunda lista que ficaria
-- desatualizada.
create index if not exists capturas_ia_documento_idx
  on public.capturas_ia (documento_id)
  where documento_id is not null;

create index if not exists notas_consumo_documento_idx
  on public.notas_consumo (documento_id)
  where documento_id is not null;

create index if not exists receitas_culinaria_documento_idx
  on public.receitas_culinaria (documento_id)
  where documento_id is not null;

create or replace view public.usos_documentos_apps
with (security_invoker = true)
as
  select c.documento_id, c.usuario_id, 'financas'::text as app_id
    from public.capturas_ia c
   where c.documento_id is not null
  union
  select n.documento_id, n.usuario_id, 'financas'::text as app_id
    from public.notas_consumo n
   where n.documento_id is not null
  union
  select r.documento_id, r.usuario_id, 'culinaria'::text as app_id
    from public.receitas_culinaria r
   where r.documento_id is not null;

revoke all on public.usos_documentos_apps from anon;
grant select on public.usos_documentos_apps to authenticated, service_role;

-- A IA lê; a pessoa decide se ela também pode reorganizar -------------------
create table if not exists public.preferencias_documentos (
  usuario_id uuid primary key references auth.users(id) on delete cascade,
  exigir_aprovacao_refatoracao_ia boolean not null default true,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

drop trigger if exists preferencias_documentos_atualizado_em
  on public.preferencias_documentos;
create trigger preferencias_documentos_atualizado_em
before update on public.preferencias_documentos
for each row execute function public.definir_atualizado_em();

alter table public.preferencias_documentos enable row level security;
alter table public.preferencias_documentos force row level security;

drop policy if exists preferencias_documentos_do_usuario
  on public.preferencias_documentos;
create policy preferencias_documentos_do_usuario
on public.preferencias_documentos
for all to authenticated
using ((select auth.uid()) = usuario_id)
with check ((select auth.uid()) = usuario_id);

revoke all on public.preferencias_documentos from anon;
grant select, insert, update, delete on public.preferencias_documentos
  to authenticated;

-- O acervo anterior pode ter sido marcado como "arrumado pela IA" apenas
-- porque ganhou um nome no upload, embora tenha continuado solto em Outros.
-- Reabrimos uma única vez essa fila: o mutirão lê e propõe um lugar, sem
-- alterar nada até a pessoa aceitar.
update public.documentos_financeiros
   set organizacao = 'pendente'
 where categoria = 'outros'
   and pasta_id is null
   and organizacao = 'ia';

commit;
