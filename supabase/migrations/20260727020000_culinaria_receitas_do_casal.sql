begin;

-- Receitas passam a nascer pessoais. O coracao apenas propoe leva-las ao
-- espaco do casal; elas so ficam compartilhadas depois do aceite do par.
alter table public.receitas_culinaria
  add column if not exists compartilhada_casal boolean not null default false;

create index if not exists receitas_culinaria_casal_idx
  on public.receitas_culinaria (usuario_id, atualizado_em desc)
  where compartilhada_casal;

create table if not exists public.compartilhamentos_receitas_culinaria (
  id uuid primary key default gen_random_uuid(),
  vinculo_id uuid not null references public.vinculos_casal(id) on delete cascade,
  receita_id uuid not null
    references public.receitas_culinaria(id) on delete cascade,
  usuario_id uuid not null references auth.users(id) on delete cascade,
  titulo_receita text not null check (char_length(titulo_receita) between 1 and 200),
  status text not null default 'pendente'
    check (status in ('pendente', 'aceito', 'recusado')),
  proposto_por uuid not null references auth.users(id) on delete cascade,
  respondida_por uuid references auth.users(id) on delete set null,
  respondida_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create unique index if not exists compartilhamentos_receitas_pendente_idx
  on public.compartilhamentos_receitas_culinaria (vinculo_id, receita_id)
  where status = 'pendente';

create index if not exists compartilhamentos_receitas_vinculo_status_idx
  on public.compartilhamentos_receitas_culinaria
  (vinculo_id, status, criado_em desc);

drop trigger if exists compartilhamentos_receitas_culinaria_atualizado_em
  on public.compartilhamentos_receitas_culinaria;
create trigger compartilhamentos_receitas_culinaria_atualizado_em
before update on public.compartilhamentos_receitas_culinaria
for each row execute function public.definir_atualizado_em();

alter table public.compartilhamentos_receitas_culinaria enable row level security;
alter table public.compartilhamentos_receitas_culinaria force row level security;

drop policy if exists compartilhamentos_receitas_casal_dos_membros
  on public.compartilhamentos_receitas_culinaria;
create policy compartilhamentos_receitas_casal_dos_membros
  on public.compartilhamentos_receitas_culinaria
for all to authenticated
using (
  exists (
    select 1
      from public.vinculos_casal v
     where v.id = vinculo_id
       and v.status = 'ativo'
       and (select auth.uid()) in (v.criador_id, v.parceiro_id)
  )
)
with check (
  exists (
    select 1
      from public.vinculos_casal v
     where v.id = vinculo_id
       and v.status = 'ativo'
       and (select auth.uid()) in (v.criador_id, v.parceiro_id)
  )
);

revoke all on public.compartilhamentos_receitas_culinaria from anon;
grant select, insert, update, delete
  on public.compartilhamentos_receitas_culinaria to authenticated;

-- A policy antiga deixava todo o caderno do parceiro visivel. Agora a leitura
-- do parceiro exige aceite; escrita e remocao continuam exclusivas do dono.
drop policy if exists receitas_culinaria_do_casal on public.receitas_culinaria;

drop policy if exists receitas_culinaria_leitura on public.receitas_culinaria;
create policy receitas_culinaria_leitura on public.receitas_culinaria
for select to authenticated
using (
  (select auth.uid()) = usuario_id
  or (
    compartilhada_casal
    and public.e_do_casal_culinaria(usuario_id)
  )
);

drop policy if exists receitas_culinaria_insercao on public.receitas_culinaria;
create policy receitas_culinaria_insercao on public.receitas_culinaria
for insert to authenticated
with check ((select auth.uid()) = usuario_id);

drop policy if exists receitas_culinaria_atualizacao on public.receitas_culinaria;
create policy receitas_culinaria_atualizacao on public.receitas_culinaria
for update to authenticated
using ((select auth.uid()) = usuario_id)
with check ((select auth.uid()) = usuario_id);

drop policy if exists receitas_culinaria_remocao on public.receitas_culinaria;
create policy receitas_culinaria_remocao on public.receitas_culinaria
for delete to authenticated
using ((select auth.uid()) = usuario_id);

commit;
