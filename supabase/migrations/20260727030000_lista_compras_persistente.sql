-- Uma lista de compras ativa por casa, unindo rotina, receitas e itens manuais.
-- A descricao fiscal continua no FiNancas; aqui vivem apenas a intencao de
-- compra, suas origens e os nomes amigaveis aprendidos para esse contexto.

begin;

create table if not exists public.listas_compras_culinaria (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  vinculo_id uuid references public.vinculos_casal(id) on delete cascade,
  status text not null default 'ativa'
    check (status in ('ativa', 'concluida')),
  rotina_sincronizada_em timestamptz,
  concluida_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create unique index if not exists listas_compras_pessoal_ativa_idx
  on public.listas_compras_culinaria (usuario_id)
  where status = 'ativa' and vinculo_id is null;
create unique index if not exists listas_compras_casal_ativa_idx
  on public.listas_compras_culinaria (vinculo_id)
  where status = 'ativa' and vinculo_id is not null;
create index if not exists listas_compras_historico_idx
  on public.listas_compras_culinaria (usuario_id, criado_em desc);

drop trigger if exists listas_compras_culinaria_atualizado_em
  on public.listas_compras_culinaria;
create trigger listas_compras_culinaria_atualizado_em
before update on public.listas_compras_culinaria
for each row execute function public.definir_atualizado_em();

create table if not exists public.itens_lista_compras_culinaria (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  lista_id uuid not null
    references public.listas_compras_culinaria(id) on delete cascade,
  chave_canonica text not null
    check (char_length(chave_canonica) between 1 and 180),
  nome text not null check (char_length(nome) between 1 and 120),
  nome_original text,
  categoria text not null default 'outros'
    check (
      categoria in (
        'hortifruti', 'padaria', 'carnes', 'laticinios', 'congelados',
        'mercearia', 'bebidas', 'limpeza', 'higiene', 'bebe', 'pet',
        'medicamentos', 'outros'
      )
    ),
  quantidade text,
  marcado boolean not null default false,
  ajustado_manualmente boolean not null default false,
  ordem integer not null default 0 check (ordem >= 0),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (lista_id, chave_canonica)
);

create index if not exists itens_lista_compras_lista_idx
  on public.itens_lista_compras_culinaria (lista_id, categoria, ordem, criado_em);

drop trigger if exists itens_lista_compras_culinaria_atualizado_em
  on public.itens_lista_compras_culinaria;
create trigger itens_lista_compras_culinaria_atualizado_em
before update on public.itens_lista_compras_culinaria
for each row execute function public.definir_atualizado_em();

create table if not exists public.fontes_itens_lista_culinaria (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  item_id uuid not null
    references public.itens_lista_compras_culinaria(id) on delete cascade,
  tipo text not null check (tipo in ('rotina', 'receita', 'manual')),
  referencia_id text not null check (char_length(referencia_id) between 1 and 300),
  grupo_id text,
  rotulo text not null check (char_length(rotulo) between 1 and 200),
  quantidade text,
  criado_em timestamptz not null default now(),
  unique (item_id, tipo, referencia_id)
);

create index if not exists fontes_itens_lista_item_idx
  on public.fontes_itens_lista_culinaria (item_id);
create index if not exists fontes_itens_lista_grupo_idx
  on public.fontes_itens_lista_culinaria (tipo, grupo_id)
  where grupo_id is not null;

create table if not exists public.aliases_lista_compras_culinaria (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  vinculo_id uuid references public.vinculos_casal(id) on delete cascade,
  escopo_id uuid not null,
  origem_tipo text not null check (origem_tipo in ('rotina', 'receita', 'manual')),
  origem_chave text not null check (char_length(origem_chave) between 1 and 300),
  chave_canonica text not null check (char_length(chave_canonica) between 1 and 180),
  nome text not null check (char_length(nome) between 1 and 120),
  categoria text not null
    check (
      categoria in (
        'hortifruti', 'padaria', 'carnes', 'laticinios', 'congelados',
        'mercearia', 'bebidas', 'limpeza', 'higiene', 'bebe', 'pet',
        'medicamentos', 'outros'
      )
    ),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (escopo_id, origem_tipo, origem_chave)
);

create index if not exists aliases_lista_compras_usuario_idx
  on public.aliases_lista_compras_culinaria (usuario_id);
create index if not exists aliases_lista_compras_vinculo_idx
  on public.aliases_lista_compras_culinaria (vinculo_id)
  where vinculo_id is not null;

drop trigger if exists aliases_lista_compras_culinaria_atualizado_em
  on public.aliases_lista_compras_culinaria;
create trigger aliases_lista_compras_culinaria_atualizado_em
before update on public.aliases_lista_compras_culinaria
for each row execute function public.definir_atualizado_em();

alter table public.listas_compras_culinaria enable row level security;
alter table public.listas_compras_culinaria force row level security;
alter table public.itens_lista_compras_culinaria enable row level security;
alter table public.itens_lista_compras_culinaria force row level security;
alter table public.fontes_itens_lista_culinaria enable row level security;
alter table public.fontes_itens_lista_culinaria force row level security;
alter table public.aliases_lista_compras_culinaria enable row level security;
alter table public.aliases_lista_compras_culinaria force row level security;

drop policy if exists listas_compras_culinaria_dos_membros
  on public.listas_compras_culinaria;
create policy listas_compras_culinaria_dos_membros
on public.listas_compras_culinaria
for all to authenticated
using (
  (select auth.uid()) = usuario_id
  or (
    vinculo_id is not null
    and exists (
      select 1
        from public.vinculos_casal v
       where v.id = vinculo_id
         and v.status = 'ativo'
         and (select auth.uid()) in (v.criador_id, v.parceiro_id)
    )
  )
)
with check (
  (select auth.uid()) = usuario_id
  or (
    vinculo_id is not null
    and exists (
      select 1
        from public.vinculos_casal v
       where v.id = vinculo_id
         and v.status = 'ativo'
         and (select auth.uid()) in (v.criador_id, v.parceiro_id)
    )
  )
);

drop policy if exists itens_lista_compras_culinaria_dos_membros
  on public.itens_lista_compras_culinaria;
create policy itens_lista_compras_culinaria_dos_membros
on public.itens_lista_compras_culinaria
for all to authenticated
using (
  exists (
    select 1
      from public.listas_compras_culinaria l
     where l.id = lista_id
       and (
         l.usuario_id = (select auth.uid())
         or exists (
           select 1
             from public.vinculos_casal v
            where v.id = l.vinculo_id
              and v.status = 'ativo'
              and (select auth.uid()) in (v.criador_id, v.parceiro_id)
         )
       )
  )
)
with check (
  exists (
    select 1
      from public.listas_compras_culinaria l
     where l.id = lista_id
       and (
         l.usuario_id = (select auth.uid())
         or exists (
           select 1
             from public.vinculos_casal v
            where v.id = l.vinculo_id
              and v.status = 'ativo'
              and (select auth.uid()) in (v.criador_id, v.parceiro_id)
         )
       )
  )
);

drop policy if exists fontes_itens_lista_culinaria_dos_membros
  on public.fontes_itens_lista_culinaria;
create policy fontes_itens_lista_culinaria_dos_membros
on public.fontes_itens_lista_culinaria
for all to authenticated
using (
  exists (
    select 1
      from public.itens_lista_compras_culinaria i
      join public.listas_compras_culinaria l on l.id = i.lista_id
     where i.id = item_id
       and (
         l.usuario_id = (select auth.uid())
         or exists (
           select 1
             from public.vinculos_casal v
            where v.id = l.vinculo_id
              and v.status = 'ativo'
              and (select auth.uid()) in (v.criador_id, v.parceiro_id)
         )
       )
  )
)
with check (
  exists (
    select 1
      from public.itens_lista_compras_culinaria i
      join public.listas_compras_culinaria l on l.id = i.lista_id
     where i.id = item_id
       and (
         l.usuario_id = (select auth.uid())
         or exists (
           select 1
             from public.vinculos_casal v
            where v.id = l.vinculo_id
              and v.status = 'ativo'
              and (select auth.uid()) in (v.criador_id, v.parceiro_id)
         )
       )
  )
);

drop policy if exists aliases_lista_compras_culinaria_dos_membros
  on public.aliases_lista_compras_culinaria;
create policy aliases_lista_compras_culinaria_dos_membros
on public.aliases_lista_compras_culinaria
for all to authenticated
using (
  (select auth.uid()) = usuario_id
  or (
    vinculo_id is not null
    and exists (
      select 1
        from public.vinculos_casal v
       where v.id = vinculo_id
         and v.status = 'ativo'
         and (select auth.uid()) in (v.criador_id, v.parceiro_id)
    )
  )
)
with check (
  (select auth.uid()) = usuario_id
  or (
    vinculo_id is not null
    and exists (
      select 1
        from public.vinculos_casal v
       where v.id = vinculo_id
         and v.status = 'ativo'
         and (select auth.uid()) in (v.criador_id, v.parceiro_id)
    )
  )
);

revoke all on public.listas_compras_culinaria from anon;
revoke all on public.itens_lista_compras_culinaria from anon;
revoke all on public.fontes_itens_lista_culinaria from anon;
revoke all on public.aliases_lista_compras_culinaria from anon;
grant select, insert, update, delete on public.listas_compras_culinaria to authenticated;
grant select, insert, update, delete on public.itens_lista_compras_culinaria to authenticated;
grant select, insert, update, delete on public.fontes_itens_lista_culinaria to authenticated;
grant select, insert, update, delete on public.aliases_lista_compras_culinaria
  to authenticated;

commit;
