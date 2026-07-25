-- Nome e setor amigaveis definidos pela revisao da lista de compras.
-- A descricao fiscal original continua imutavel em itens_consumo; este alias
-- e aplicado ao panorama do usuario, inclusive para compras futuras iguais.

begin;

create table if not exists public.aliases_produtos_consumo (
  usuario_id uuid not null references auth.users(id) on delete cascade,
  chave text not null check (char_length(chave) between 1 and 300),
  nome_exibicao text not null check (char_length(nome_exibicao) between 1 and 120),
  categoria text not null check (
    categoria in (
      'laticinios', 'limpeza', 'higiene', 'hortifruti', 'carnes', 'bebidas',
      'medicamentos', 'padaria', 'mercearia', 'congelados', 'pet', 'bebe', 'outros'
    )
  ),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  primary key (usuario_id, chave)
);

drop trigger if exists aliases_produtos_consumo_atualizado_em
  on public.aliases_produtos_consumo;
create trigger aliases_produtos_consumo_atualizado_em
before update on public.aliases_produtos_consumo
for each row execute function public.definir_atualizado_em();

alter table public.aliases_produtos_consumo enable row level security;
alter table public.aliases_produtos_consumo force row level security;

drop policy if exists aliases_produtos_consumo_do_usuario
  on public.aliases_produtos_consumo;
create policy aliases_produtos_consumo_do_usuario
on public.aliases_produtos_consumo
for all to authenticated
using ((select auth.uid()) = usuario_id)
with check ((select auth.uid()) = usuario_id);

revoke all on public.aliases_produtos_consumo from anon;
grant select, insert, update, delete
  on public.aliases_produtos_consumo to authenticated;

commit;
