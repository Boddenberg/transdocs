begin;

create index if not exists documentos_financeiros_usuario_criado_idx
  on public.documentos_financeiros (usuario_id, criado_em desc);
create index if not exists documentos_financeiros_usuario_status_idx
  on public.documentos_financeiros (usuario_id, status, tipo);

commit;

