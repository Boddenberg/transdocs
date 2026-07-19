begin;

-- Lista de desejos do casal: itens que os dois querem comprar, guardados no
-- espaco compartilhado (o vinculo) e nao na conta de uma pessoa so. Um desejo
-- vira 'ativo' quando ganha um preco; so os ativos entram na analise da IA,
-- porque sem valor estimado nao da para dizer qual mes suporta a compra.
create table if not exists public.desejos_casal (
  id uuid primary key default gen_random_uuid(),
  vinculo_id uuid not null references public.vinculos_casal(id) on delete cascade,
  criado_por uuid not null references auth.users(id) on delete cascade,
  titulo text not null check (char_length(titulo) between 1 and 120),
  descricao text check (descricao is null or char_length(descricao) <= 2000),
  valor_estimado numeric(14, 2) check (valor_estimado is null or valor_estimado >= 0),
  foto_caminho text unique,
  foto_mime text check (foto_mime is null or foto_mime in (
    'image/jpeg', 'image/png', 'image/webp'
  )),
  status text not null default 'rascunho' check (status in (
    'rascunho', 'ativo', 'comprado', 'arquivado'
  )),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  -- Um desejo sem preco nao pode ser analisado; fica em rascunho ate ganhar um.
  check (status <> 'ativo' or valor_estimado is not null),
  check ((foto_caminho is null) = (foto_mime is null))
);

create index if not exists desejos_casal_vinculo_idx
  on public.desejos_casal (vinculo_id, status, criado_em desc);

drop trigger if exists desejos_casal_atualizado_em on public.desejos_casal;
create trigger desejos_casal_atualizado_em
before update on public.desejos_casal
for each row execute function public.definir_atualizado_em();

-- Recomendacao da IA para um desejo: melhor mes, melhor dia e o porque.
-- Nenhum valor monetario e persistido aqui - a justificativa e qualitativa,
-- para nao expor dado financeiro privado de nenhum dos dois integrantes.
create table if not exists public.recomendacoes_desejos_casal (
  id uuid primary key default gen_random_uuid(),
  desejo_id uuid not null unique references public.desejos_casal(id) on delete cascade,
  mes_recomendado date not null,
  dia_recomendado integer not null check (dia_recomendado between 1 and 31),
  justificativa text not null check (char_length(justificativa) between 1 and 4000),
  -- Carimbo do retrato financeiro e do desejo que geraram esta recomendacao.
  -- Serve para avisar o casal quando os dados mudaram desde a ultima analise.
  assinatura_dados text not null check (assinatura_dados ~ '^[a-f0-9]{64}$'),
  modelo_ia text,
  tokens_entrada integer check (tokens_entrada is null or tokens_entrada >= 0),
  tokens_saida integer check (tokens_saida is null or tokens_saida >= 0),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  check (extract(day from mes_recomendado) = 1)
);

drop trigger if exists recomendacoes_desejos_casal_atualizado_em
  on public.recomendacoes_desejos_casal;
create trigger recomendacoes_desejos_casal_atualizado_em
before update on public.recomendacoes_desejos_casal
for each row execute function public.definir_atualizado_em();

alter table public.desejos_casal enable row level security;
alter table public.desejos_casal force row level security;
alter table public.recomendacoes_desejos_casal enable row level security;
alter table public.recomendacoes_desejos_casal force row level security;

-- Os dois integrantes do vinculo administram qualquer desejo do espaco.
drop policy if exists desejos_casal_dos_membros on public.desejos_casal;
create policy desejos_casal_dos_membros on public.desejos_casal
for all to authenticated
using (
  exists (
    select 1 from public.vinculos_casal v
    where v.id = vinculo_id
      and v.status = 'ativo'
      and (select auth.uid()) in (v.criador_id, v.parceiro_id)
  )
)
with check (
  exists (
    select 1 from public.vinculos_casal v
    where v.id = vinculo_id
      and v.status = 'ativo'
      and (select auth.uid()) in (v.criador_id, v.parceiro_id)
  )
);

-- A recomendacao e produzida pela API (service role) e so lida pelos membros.
drop policy if exists recomendacoes_desejos_casal_dos_membros
  on public.recomendacoes_desejos_casal;
create policy recomendacoes_desejos_casal_dos_membros
on public.recomendacoes_desejos_casal
for select to authenticated
using (
  exists (
    select 1
    from public.desejos_casal d
    join public.vinculos_casal v on v.id = d.vinculo_id
    where d.id = desejo_id
      and v.status = 'ativo'
      and (select auth.uid()) in (v.criador_id, v.parceiro_id)
  )
);

revoke all on public.desejos_casal from anon;
revoke all on public.recomendacoes_desejos_casal from anon;
grant select, insert, update, delete on public.desejos_casal to authenticated;
grant select on public.recomendacoes_desejos_casal to authenticated;

-- Bucket privado das fotos dos desejos. O caminho e {vinculo_id}/{uuid}.ext:
-- a foto pertence ao casal, nao a quem cadastrou. Sem policy para
-- `authenticated` de proposito - o navegador nunca fala com o Storage; a API
-- (service role) grava e devolve uma URL assinada de curta duracao.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'desejos-casal',
  'desejos-casal',
  false,
  10485760,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

commit;
