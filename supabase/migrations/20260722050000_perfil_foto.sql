begin;

-- Foto de perfil do usuario. Guardada como caminho no Storage; a coluna nunca
-- carrega bytes, so o ponteiro e o mime, como nas fotos dos desejos.
alter table public.perfis
  add column if not exists foto_caminho text,
  add column if not exists foto_mime text;

-- Bucket privado das fotos de perfil. O caminho e {usuario_id}/{uuid}.ext.
-- Sem policy para `authenticated` de proposito: o navegador nunca fala com o
-- Storage; a API (service role) grava e devolve uma URL assinada de curta
-- duracao, igual ao bucket dos desejos.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'avatares-perfil',
  'avatares-perfil',
  false,
  10485760,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

commit;
