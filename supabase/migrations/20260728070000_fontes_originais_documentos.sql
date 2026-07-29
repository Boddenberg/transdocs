begin;

-- Uma conversao nunca substitui o que a pessoa entregou. O PDF e a versao de
-- leitura; cada foto ou arquivo-fonte continua guardado, em sua ordem original.
create table if not exists public.fontes_originais_documentos (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  documento_id uuid not null
    references public.documentos_financeiros(id) on delete cascade,
  nome_original text not null,
  tipo_mime text not null,
  tamanho_bytes bigint not null check (tamanho_bytes > 0),
  hash_sha256 text not null check (length(hash_sha256) = 64),
  caminho_storage text not null,
  ordem integer not null check (ordem >= 0),
  criado_em timestamptz not null default now(),
  unique (documento_id, ordem)
);

create index if not exists fontes_originais_usuario_documento_idx
  on public.fontes_originais_documentos (usuario_id, documento_id, ordem);

alter table public.fontes_originais_documentos enable row level security;
alter table public.fontes_originais_documentos force row level security;
drop policy if exists fontes_originais_do_proprio_usuario
  on public.fontes_originais_documentos;
create policy fontes_originais_do_proprio_usuario
  on public.fontes_originais_documentos
  using (usuario_id = auth.uid())
  with check (usuario_id = auth.uid());
revoke all on public.fontes_originais_documentos from anon;
grant select, insert, update, delete
  on public.fontes_originais_documentos to authenticated;

commit;
