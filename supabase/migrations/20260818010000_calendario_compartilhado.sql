-- Calendário compartilhado do casal, lembretes determinísticos e entrega idempotente.
--
-- Datas de evento são `date`: um compromisso sem horário nunca atravessa UTC.
-- Horários, quando existem, são hora civil de America/Sao_Paulo. O backend
-- combina os dois somente ao calcular o instante de um lembrete.

begin;

create table public.eventos_calendario (
  id uuid primary key default gen_random_uuid(),
  vinculo_id uuid not null references public.vinculos_casal(id) on delete cascade,
  titulo text not null check (char_length(btrim(titulo)) between 1 and 160),
  descricao text check (descricao is null or char_length(descricao) <= 4000),
  data_evento date not null,
  hora_inicio time,
  hora_fim time,
  dia_inteiro boolean not null default true,
  local text check (local is null or char_length(local) <= 300),
  proprietario_tipo text not null default 'casal'
    check (proprietario_tipo in ('pessoa', 'casal')),
  proprietario_usuario_id uuid references auth.users(id) on delete restrict,
  criado_por uuid not null references auth.users(id) on delete restrict,
  capa_caminho text unique,
  capa_mime text check (capa_mime is null or capa_mime = 'image/webp'),
  regra_recorrencia jsonb check (
    regra_recorrencia is null or jsonb_typeof(regra_recorrencia) = 'object'
  ),
  origem text not null default 'manual'
    check (origem in ('manual', 'whatsapp', 'tarefas', 'financas', 'system')),
  fuso text not null default 'America/Sao_Paulo'
    check (char_length(fuso) between 3 and 64),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  excluido_em timestamptz,
  constraint eventos_calendario_proprietario_check check (
    (proprietario_tipo = 'casal' and proprietario_usuario_id is null)
    or (proprietario_tipo = 'pessoa' and proprietario_usuario_id is not null)
  ),
  constraint eventos_calendario_horario_check check (
    (hora_inicio is null and hora_fim is null)
    or (hora_inicio is not null and (hora_fim is null or hora_fim > hora_inicio))
  ),
  constraint eventos_calendario_dia_inteiro_check check (
    not dia_inteiro or (hora_inicio is null and hora_fim is null)
  )
);

create index eventos_calendario_mes_idx
  on public.eventos_calendario (vinculo_id, data_evento, id)
  where excluido_em is null;
create index eventos_calendario_proprietario_idx
  on public.eventos_calendario (vinculo_id, proprietario_usuario_id, data_evento)
  where excluido_em is null;

alter table public.eventos_calendario enable row level security;
alter table public.eventos_calendario force row level security;
revoke all on public.eventos_calendario from anon, authenticated;

create trigger eventos_calendario_atualizado_em
before update on public.eventos_calendario
for each row execute function public.definir_atualizado_em();

-- Cascades do vínculo também precisam recolher as capas privadas. Alterações
-- comuns continuam removendo o arquivo pelo backend; este gatilho fecha o caso
-- de reset/remoção direta sem deixar objetos órfãos no Storage.
create or replace function public.remover_capa_evento_calendario()
returns trigger
language plpgsql
security definer
set search_path = public, storage
as $$
begin
  if old.capa_caminho is not null then
    delete from storage.objects
    where bucket_id = 'capas-calendario' and name = old.capa_caminho;
  end if;
  return old;
end;
$$;

create trigger eventos_calendario_remover_capa
after delete on public.eventos_calendario
for each row execute function public.remover_capa_evento_calendario();

create table public.lembretes_eventos_calendario (
  id uuid primary key default gen_random_uuid(),
  evento_id uuid not null references public.eventos_calendario(id) on delete cascade,
  minutos_antes integer not null check (minutos_antes between 0 and 525600),
  criado_em timestamptz not null default now(),
  unique (evento_id, minutos_antes)
);

create index lembretes_eventos_calendario_evento_idx
  on public.lembretes_eventos_calendario (evento_id);

alter table public.lembretes_eventos_calendario enable row level security;
alter table public.lembretes_eventos_calendario force row level security;
revoke all on public.lembretes_eventos_calendario from anon, authenticated;

-- Uma linha representa uma ocorrência de um lembrete nos dois canais. Isso
-- preserva uma única redação natural para Home e WhatsApp sem duas chamadas à IA.
create table public.notificacoes_lembretes_calendario (
  id uuid primary key default gen_random_uuid(),
  evento_id uuid not null references public.eventos_calendario(id) on delete cascade,
  lembrete_id uuid references public.lembretes_eventos_calendario(id) on delete set null,
  data_ocorrencia date not null,
  agendado_para timestamptz not null,
  chave_notificacao text not null unique
    check (char_length(chave_notificacao) between 16 and 300),
  mensagem text check (mensagem is null or char_length(mensagem) between 1 and 4096),
  status text not null default 'agendada'
    check (status in ('agendada', 'reescrevendo', 'pronta', 'cancelada')),
  status_app text not null default 'pendente'
    check (status_app in ('pendente', 'nova', 'vista', 'dispensada', 'adiada', 'cancelada')),
  status_whatsapp text not null default 'pendente'
    check (status_whatsapp in ('pendente', 'enviando', 'enfileirada', 'aguardando_destino', 'falha', 'cancelada')),
  destino_whatsapp text check (
    destino_whatsapp is null or char_length(destino_whatsapp) between 1 and 120
  ),
  whatsapp_tentativas integer not null default 0,
  whatsapp_erro text check (whatsapp_erro is null or char_length(whatsapp_erro) <= 500),
  whatsapp_enfileirado_em timestamptz,
  reescrita_iniciada_em timestamptz,
  proxima_tentativa_reescrita_em timestamptz,
  reescrita_tentativas integer not null default 0,
  vista_em timestamptz,
  dispensada_em timestamptz,
  adiada_de uuid references public.notificacoes_lembretes_calendario(id) on delete set null,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create index notificacoes_lembretes_calendario_agenda_idx
  on public.notificacoes_lembretes_calendario (agendado_para, status)
  where status in ('agendada', 'reescrevendo', 'pronta');
create index notificacoes_lembretes_calendario_home_idx
  on public.notificacoes_lembretes_calendario (evento_id, criado_em desc)
  where status_app in ('nova', 'vista');
create index notificacoes_lembretes_calendario_whatsapp_idx
  on public.notificacoes_lembretes_calendario (agendado_para, status_whatsapp)
  where status_whatsapp in ('pendente', 'aguardando_destino', 'falha');

alter table public.notificacoes_lembretes_calendario enable row level security;
alter table public.notificacoes_lembretes_calendario force row level security;
revoke all on public.notificacoes_lembretes_calendario from anon, authenticated;

create trigger notificacoes_lembretes_calendario_atualizado_em
before update on public.notificacoes_lembretes_calendario
for each row execute function public.definir_atualizado_em();

-- A caixa já era idempotente para respostas a uma mensagem recebida. Lembretes
-- nascem sem `responde_a`, então ganham sua própria chave estável. Um processo
-- que cair depois do insert pode tentar de novo sem criar outro balão.
alter table public.caixa_whatsapp
  add column if not exists chave_idempotencia text
    check (chave_idempotencia is null or char_length(chave_idempotencia) between 8 and 300);
create unique index if not exists caixa_whatsapp_idempotencia_idx
  on public.caixa_whatsapp (chave_idempotencia)
  where chave_idempotencia is not null;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'capas-calendario',
  'capas-calendario',
  false,
  10485760,
  array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

commit;
