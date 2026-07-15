begin;

alter table public.documentos
  add column if not exists somente_primeira_pagina boolean not null default false;

alter table public.documentos
  drop constraint if exists documentos_tamanho_bytes_check;

alter table public.documentos
  add constraint documentos_tamanho_bytes_check
  check (tamanho_bytes > 0 and tamanho_bytes <= 52428800);

alter table public.documentos
  drop constraint if exists documentos_usuario_id_hash_sha256_key;

drop index if exists public.documentos_usuario_hash_modo_idx;
create unique index documentos_usuario_hash_modo_idx
  on public.documentos (usuario_id, hash_sha256, somente_primeira_pagina);

update storage.buckets
set file_size_limit = 52428800
where id = 'documentos';

commit;
