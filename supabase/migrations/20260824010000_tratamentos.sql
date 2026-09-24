-- Tratamentos pessoais: planos, rotinas, conclusões, ocorrências e aviso diário.
--
-- Saúde é dado pessoal por padrão. Nenhuma tabela depende do vínculo do casal;
-- o grupo do WhatsApp só é usado quando a própria pessoa escolhe esse destino.

begin;

create table public.tratamentos (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  nome text not null check (char_length(btrim(nome)) between 1 and 120),
  objetivo text check (objetivo is null or char_length(objetivo) <= 1000),
  cor text not null default '#4f7d68'
    check (cor ~ '^#[0-9a-fA-F]{6}$'),
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (id, usuario_id)
);

create index tratamentos_usuario_idx
  on public.tratamentos (usuario_id, ativo desc, criado_em, id);

alter table public.tratamentos enable row level security;
alter table public.tratamentos force row level security;
revoke all on public.tratamentos from anon, authenticated;

create trigger tratamentos_atualizado_em
before update on public.tratamentos
for each row execute function public.definir_atualizado_em();

create table public.rotinas_tratamentos (
  id uuid primary key default gen_random_uuid(),
  tratamento_id uuid not null,
  usuario_id uuid not null references auth.users(id) on delete cascade,
  nome text not null check (char_length(btrim(nome)) between 1 and 160),
  instrucoes text check (instrucoes is null or char_length(instrucoes) <= 2000),
  hora time not null,
  dias_semana smallint[] not null default array[0,1,2,3,4,5,6]::smallint[]
    check (
      cardinality(dias_semana) between 1 and 7
      and dias_semana <@ array[0,1,2,3,4,5,6]::smallint[]
    ),
  data_inicio date not null default current_date,
  data_fim date,
  whatsapp boolean not null default true,
  ordem smallint not null default 0 check (ordem between 0 and 1000),
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (id, usuario_id),
  foreign key (tratamento_id, usuario_id)
    references public.tratamentos(id, usuario_id) on delete cascade,
  check (data_fim is null or data_fim >= data_inicio)
);

create index rotinas_tratamentos_usuario_idx
  on public.rotinas_tratamentos (usuario_id, ativo desc, hora, ordem, id);
create index rotinas_tratamentos_plano_idx
  on public.rotinas_tratamentos (tratamento_id, ordem, hora, id);

alter table public.rotinas_tratamentos enable row level security;
alter table public.rotinas_tratamentos force row level security;
revoke all on public.rotinas_tratamentos from anon, authenticated;

create trigger rotinas_tratamentos_atualizado_em
before update on public.rotinas_tratamentos
for each row execute function public.definir_atualizado_em();

create table public.conclusoes_rotinas_tratamentos (
  id uuid primary key default gen_random_uuid(),
  rotina_id uuid not null,
  usuario_id uuid not null references auth.users(id) on delete cascade,
  data_execucao date not null,
  concluida_em timestamptz not null default now(),
  observacao text check (observacao is null or char_length(observacao) <= 1000),
  criado_em timestamptz not null default now(),
  unique (rotina_id, usuario_id, data_execucao),
  foreign key (rotina_id, usuario_id)
    references public.rotinas_tratamentos(id, usuario_id) on delete cascade
);

create index conclusoes_rotinas_tratamentos_mes_idx
  on public.conclusoes_rotinas_tratamentos (usuario_id, data_execucao desc, rotina_id);

alter table public.conclusoes_rotinas_tratamentos enable row level security;
alter table public.conclusoes_rotinas_tratamentos force row level security;
revoke all on public.conclusoes_rotinas_tratamentos from anon, authenticated;

create table public.ocorrencias_tratamentos (
  id uuid primary key default gen_random_uuid(),
  tratamento_id uuid,
  usuario_id uuid not null references auth.users(id) on delete cascade,
  tipo text not null default 'anotacao'
    check (tipo in ('receita', 'reacao', 'consulta', 'exame', 'anotacao')),
  titulo text not null check (char_length(btrim(titulo)) between 1 and 160),
  texto text check (texto is null or char_length(texto) <= 8000),
  data_ocorrencia date not null,
  hora_ocorrencia time,
  anexo_caminho text unique,
  anexo_nome text check (anexo_nome is null or char_length(anexo_nome) <= 180),
  anexo_mime text check (
    anexo_mime is null
    or anexo_mime in ('application/pdf', 'image/jpeg', 'image/png', 'image/webp')
  ),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  foreign key (tratamento_id, usuario_id)
    references public.tratamentos(id, usuario_id) on delete cascade
);

create index ocorrencias_tratamentos_mes_idx
  on public.ocorrencias_tratamentos (usuario_id, data_ocorrencia desc, id);
create index ocorrencias_tratamentos_plano_idx
  on public.ocorrencias_tratamentos (tratamento_id, data_ocorrencia desc, id);

alter table public.ocorrencias_tratamentos enable row level security;
alter table public.ocorrencias_tratamentos force row level security;
revoke all on public.ocorrencias_tratamentos from anon, authenticated;

create trigger ocorrencias_tratamentos_atualizado_em
before update on public.ocorrencias_tratamentos
for each row execute function public.definir_atualizado_em();

create table public.configuracoes_tratamentos (
  usuario_id uuid primary key references auth.users(id) on delete cascade,
  whatsapp_ativo boolean not null default false,
  horario_resumo time not null default '08:00',
  destino_whatsapp text not null default 'pessoa'
    check (destino_whatsapp in ('pessoa', 'grupo')),
  fuso text not null default 'America/Sao_Paulo'
    check (char_length(fuso) between 3 and 64),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

alter table public.configuracoes_tratamentos enable row level security;
alter table public.configuracoes_tratamentos force row level security;
revoke all on public.configuracoes_tratamentos from anon, authenticated;

create trigger configuracoes_tratamentos_atualizado_em
before update on public.configuracoes_tratamentos
for each row execute function public.definir_atualizado_em();

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'tratamentos-anexos',
  'tratamentos-anexos',
  false,
  16777216,
  array['application/pdf', 'image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.remover_anexo_ocorrencia_tratamento()
returns trigger
language plpgsql
security definer
set search_path = public, storage
as $$
begin
  if old.anexo_caminho is not null then
    delete from storage.objects
    where bucket_id = 'tratamentos-anexos' and name = old.anexo_caminho;
  end if;
  return old;
end;
$$;

create trigger ocorrencias_tratamentos_remover_anexo
after delete on public.ocorrencias_tratamentos
for each row execute function public.remover_anexo_ocorrencia_tratamento();

commit;

