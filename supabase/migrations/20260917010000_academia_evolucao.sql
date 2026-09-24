-- A Academia deixa de ser só a ficha de treino.
--
-- Duas coisas novas entram no mesmo dia da pessoa: o **peso** anotado e as
-- **fotos de evolução**. As duas são pessoais como o resto do app — RLS
-- forçado, nada para `anon` nem `authenticated` — e a foto é mais do que
-- pessoal: o bucket é privado, o arquivo nunca ganha URL pública e o caminho
-- começa pelo dono, de modo que uma chave vazada de leitura continua não
-- servindo para varrer a pasta de ninguém.
--
-- A linha do tempo que junta treino, peso e foto não é uma tabela: ela é a
-- leitura das três no mesmo `GET /treino/home`, montada no cliente. Guardar
-- uma quarta tabela com o que já está dito nas outras seria inventar um dado
-- que pode divergir do que ele resume.

begin;

create table public.pesos_treino (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  data_medicao date not null,
  peso_kg numeric(5,2) not null check (peso_kg between 20 and 400),
  observacao text check (observacao is null or char_length(observacao) <= 2000),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (usuario_id, data_medicao)
);

create index pesos_treino_usuario_idx
  on public.pesos_treino (usuario_id, data_medicao desc, id);

alter table public.pesos_treino enable row level security;
alter table public.pesos_treino force row level security;
revoke all on public.pesos_treino from anon, authenticated;

create trigger pesos_treino_atualizado_em
before update on public.pesos_treino
for each row execute function public.definir_atualizado_em();

create table public.fotos_treino (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  data_foto date not null,
  caminho_storage text not null unique
    check (char_length(caminho_storage) between 1 and 500),
  mime text not null check (mime in ('image/jpeg', 'image/png', 'image/webp')),
  bytes integer check (bytes is null or bytes > 0),
  angulo text not null default 'frente'
    check (angulo in ('frente', 'lado', 'costas', 'livre')),
  observacao text check (observacao is null or char_length(observacao) <= 2000),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create index fotos_treino_usuario_idx
  on public.fotos_treino (usuario_id, data_foto desc, criado_em desc, id);

alter table public.fotos_treino enable row level security;
alter table public.fotos_treino force row level security;
revoke all on public.fotos_treino from anon, authenticated;

create trigger fotos_treino_atualizado_em
before update on public.fotos_treino
for each row execute function public.definir_atualizado_em();

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'treino-fotos',
  'treino-fotos',
  false,
  16777216,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Apagar a linha apaga o arquivo. Sem isto, excluir a conta (ou uma foto)
-- deixaria a imagem no bucket para sempre: o registro some, o corpo fica.
create or replace function public.remover_arquivo_foto_treino()
returns trigger
language plpgsql
security definer
set search_path = public, storage
as $$
begin
  delete from storage.objects
  where bucket_id = 'treino-fotos' and name = old.caminho_storage;
  return old;
end;
$$;

create trigger fotos_treino_remover_arquivo
after delete on public.fotos_treino
for each row execute function public.remover_arquivo_foto_treino();

commit;
