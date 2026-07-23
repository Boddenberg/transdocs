-- Amplia o limite de upload de 25 MB para 50 MB.
--
-- O tamanho e barrado em tres camadas: a config do backend (MAX_UPLOAD_BYTES),
-- o file_size_limit dos buckets no Storage e o check da tabela. Sem mexer nas
-- duas ultimas, o Storage/banco continuariam recusando arquivos acima de 25 MB.
-- 50 MB = 52428800 bytes.

begin;

alter table public.documentos_financeiros
  drop constraint if exists documentos_financeiros_tamanho_bytes_check;

alter table public.documentos_financeiros
  add constraint documentos_financeiros_tamanho_bytes_check
  check (tamanho_bytes > 0 and tamanho_bytes <= 52428800);

update storage.buckets
  set file_size_limit = 52428800
  where id in ('documentos-financeiros', 'audios-financeiros');

commit;
