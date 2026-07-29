begin;

-- O quinto app do hub usa o vínculo ativo do casal como residência. Todas as
-- configurações e execuções pertencem ao vínculo; `usuario_id` identifica quem
-- criou cada linha e mantém o contrato do reset global.
create table public.configuracoes_atividades_casa (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  vinculo_id uuid not null unique
    references public.vinculos_casal(id) on delete cascade,
  percentual_esperado_criador numeric(5, 2) not null default 50
    check (percentual_esperado_criador between 0 and 100),
  limite_equilibrado numeric(5, 2) not null default 5,
  limite_concentracao_leve numeric(5, 2) not null default 15,
  limite_concentracao_relevante numeric(5, 2) not null default 25,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  check (
    limite_equilibrado >= 0
    and limite_concentracao_leve > limite_equilibrado
    and limite_concentracao_relevante > limite_concentracao_leve
    and limite_concentracao_relevante <= 100
  )
);

create table public.categorias_atividades_casa (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  vinculo_id uuid not null references public.vinculos_casal(id) on delete cascade,
  nome text not null check (char_length(nome) between 1 and 80),
  slug text not null check (slug ~ '^[a-z0-9-]+$'),
  cor text not null default '#2f7d69'
    check (cor ~ '^#[0-9a-fA-F]{6}$'),
  icone text,
  ordem integer not null default 0 check (ordem >= 0),
  status text not null default 'ativa' check (status in ('ativa', 'arquivada')),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (vinculo_id, slug)
);

create table public.ambientes_atividades_casa (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  vinculo_id uuid not null references public.vinculos_casal(id) on delete cascade,
  nome text not null check (char_length(nome) between 1 and 80),
  slug text not null check (slug ~ '^[a-z0-9-]+$'),
  ordem integer not null default 0 check (ordem >= 0),
  status text not null default 'ativo' check (status in ('ativo', 'arquivado')),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (vinculo_id, slug)
);

create table public.catalogo_atividades_casa (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  vinculo_id uuid not null references public.vinculos_casal(id) on delete cascade,
  categoria_id uuid not null
    references public.categorias_atividades_casa(id) on delete restrict,
  nome text not null check (char_length(nome) between 1 and 120),
  slug text not null check (slug ~ '^[a-z0-9-]+$'),
  peso_base numeric(8, 2) not null check (peso_base > 0 and peso_base <= 999),
  usa_ambiente boolean not null default false,
  usa_dimensao boolean not null default false,
  usa_quantidade boolean not null default false,
  favorita boolean not null default false,
  ordem integer not null default 0 check (ordem >= 0),
  status text not null default 'ativa' check (status in ('ativa', 'arquivada')),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (vinculo_id, slug)
);

create table public.ambientes_catalogo_atividades_casa (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  atividade_id uuid not null
    references public.catalogo_atividades_casa(id) on delete cascade,
  ambiente_id uuid not null
    references public.ambientes_atividades_casa(id) on delete cascade,
  criado_em timestamptz not null default now(),
  unique (atividade_id, ambiente_id)
);

create table public.capturas_atividades_casa (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  vinculo_id uuid not null references public.vinculos_casal(id) on delete cascade,
  caminho_foto text not null unique,
  foto_mime text not null check (foto_mime in ('image/jpeg', 'image/webp')),
  hash_foto text not null check (hash_foto ~ '^[a-f0-9]{64}$'),
  origem text not null default 'camera_web' check (origem = 'camera_web'),
  estado text not null default 'pendente'
    check (estado in ('pendente', 'utilizada', 'cancelada')),
  capturada_em timestamptz not null default now(),
  expira_em timestamptz not null default (now() + interval '30 minutes'),
  utilizada_em timestamptz,
  cancelada_em timestamptz,
  criado_em timestamptz not null default now(),
  unique (vinculo_id, hash_foto),
  check (estado <> 'utilizada' or utilizada_em is not null),
  check (estado <> 'cancelada' or cancelada_em is not null)
);

create table public.registros_atividades_casa (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  vinculo_id uuid not null references public.vinculos_casal(id) on delete cascade,
  captura_id uuid not null unique
    references public.capturas_atividades_casa(id) on delete restrict,
  atividade_id uuid not null
    references public.catalogo_atividades_casa(id) on delete restrict,
  categoria_id uuid not null
    references public.categorias_atividades_casa(id) on delete restrict,
  ambiente_id uuid references public.ambientes_atividades_casa(id) on delete restrict,
  atividade_nome text not null,
  categoria_nome text not null,
  ambiente_nome text,
  peso_base numeric(8, 2) not null check (peso_base > 0),
  usa_ambiente boolean not null,
  usa_dimensao boolean not null,
  usa_quantidade boolean not null,
  dimensao text check (
    dimensao is null or dimensao in ('pequena', 'normal', 'grande', 'excepcional')
  ),
  multiplicador numeric(5, 2) not null check (multiplicador > 0),
  quantidade integer not null check (quantidade between 1 and 100),
  pontuacao_total numeric(12, 2) not null check (pontuacao_total > 0),
  compartilhada boolean not null default false,
  observacao text check (observacao is null or char_length(observacao) <= 1000),
  capturada_em timestamptz not null,
  salva_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  excluida_em timestamptz,
  excluida_por uuid references auth.users(id) on delete set null,
  justificativa_exclusao text
    check (
      justificativa_exclusao is null
      or char_length(justificativa_exclusao) <= 500
    ),
  check ((ambiente_id is null) = (ambiente_nome is null)),
  check ((excluida_em is null) = (excluida_por is null))
);

create table public.participantes_registros_atividades_casa (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  vinculo_id uuid not null references public.vinculos_casal(id) on delete cascade,
  registro_id uuid not null
    references public.registros_atividades_casa(id) on delete cascade,
  percentual numeric(5, 2) not null check (percentual > 0 and percentual <= 100),
  pontos numeric(12, 2) not null check (pontos > 0),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (registro_id, usuario_id)
);

create table public.auditoria_registros_atividades_casa (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  vinculo_id uuid not null references public.vinculos_casal(id) on delete cascade,
  registro_id uuid references public.registros_atividades_casa(id) on delete set null,
  evento text not null check (evento in ('edicao', 'exclusao')),
  dados_anteriores jsonb not null,
  dados_novos jsonb,
  justificativa text check (
    justificativa is null or char_length(justificativa) <= 500
  ),
  criado_em timestamptz not null default now()
);

create index categorias_atividades_casa_vinculo_idx
  on public.categorias_atividades_casa (vinculo_id, status, ordem);
create index ambientes_atividades_casa_vinculo_idx
  on public.ambientes_atividades_casa (vinculo_id, status, ordem);
create index catalogo_atividades_casa_busca_idx
  on public.catalogo_atividades_casa
  (vinculo_id, status, favorita desc, ordem, nome);
create index capturas_atividades_casa_pendentes_idx
  on public.capturas_atividades_casa (vinculo_id, expira_em)
  where estado = 'pendente';
create index registros_atividades_casa_periodo_idx
  on public.registros_atividades_casa (vinculo_id, capturada_em desc)
  where excluida_em is null;
create index registros_atividades_casa_categoria_idx
  on public.registros_atividades_casa (vinculo_id, categoria_id, capturada_em desc)
  where excluida_em is null;
create index participantes_registros_casa_periodo_idx
  on public.participantes_registros_atividades_casa (vinculo_id, usuario_id);
create index auditoria_registros_casa_registro_idx
  on public.auditoria_registros_atividades_casa
  (vinculo_id, registro_id, criado_em desc);

do $$
declare
  tabela text;
begin
  foreach tabela in array array[
    'configuracoes_atividades_casa',
    'categorias_atividades_casa',
    'ambientes_atividades_casa',
    'catalogo_atividades_casa',
    'participantes_registros_atividades_casa'
  ]
  loop
    execute format(
      'create trigger %I_atualizado_em before update on public.%I '
      'for each row execute function public.definir_atualizado_em()',
      tabela,
      tabela
    );
  end loop;
end
$$;

create or replace function public.eh_membro_atividades_casa(alvo uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.vinculos_casal v
     where v.id = alvo
       and v.status = 'ativo'
       and (select auth.uid()) in (v.criador_id, v.parceiro_id)
  );
$$;

revoke all on function public.eh_membro_atividades_casa(uuid) from public;
grant execute on function public.eh_membro_atividades_casa(uuid) to authenticated;

do $$
declare
  tabela text;
begin
  foreach tabela in array array[
    'configuracoes_atividades_casa',
    'categorias_atividades_casa',
    'ambientes_atividades_casa',
    'catalogo_atividades_casa',
    'capturas_atividades_casa',
    'registros_atividades_casa',
    'participantes_registros_atividades_casa',
    'auditoria_registros_atividades_casa'
  ]
  loop
    execute format('alter table public.%I enable row level security', tabela);
    execute format('alter table public.%I force row level security', tabela);
    execute format(
      'create policy %I_membros on public.%I for all to authenticated '
      'using (public.eh_membro_atividades_casa(vinculo_id)) '
      'with check (public.eh_membro_atividades_casa(vinculo_id))',
      tabela,
      tabela
    );
    execute format('revoke all on public.%I from anon', tabela);
    -- O navegador usa o Supabase somente para autenticação. Toda mutação passa
    -- pela API, que valida residência, captura atual e snapshots históricos.
    execute format('grant select on public.%I to authenticated', tabela);
  end loop;
end
$$;

alter table public.ambientes_catalogo_atividades_casa enable row level security;
alter table public.ambientes_catalogo_atividades_casa force row level security;
create policy ambientes_catalogo_atividades_casa_membros
on public.ambientes_catalogo_atividades_casa
for all to authenticated
using (
  exists (
    select 1
      from public.catalogo_atividades_casa a
     where a.id = atividade_id
       and public.eh_membro_atividades_casa(a.vinculo_id)
  )
)
with check (
  exists (
    select 1
      from public.catalogo_atividades_casa a
     where a.id = atividade_id
       and public.eh_membro_atividades_casa(a.vinculo_id)
  )
);
revoke all on public.ambientes_catalogo_atividades_casa from anon;
grant select on public.ambientes_catalogo_atividades_casa to authenticated;

-- Auditoria é anexada somente pela API e nunca é alterada pelo navegador.
revoke insert, update, delete
  on public.auditoria_registros_atividades_casa from authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'atividades-casa',
  'atividades-casa',
  false,
  10485760,
  array['image/jpeg', 'image/webp']
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

commit;
