alter table public.capturas_ia
  drop constraint if exists capturas_ia_status_check;

alter table public.capturas_ia
  add constraint capturas_ia_status_check check (status in (
    'recebida', 'processando', 'aguardando_revisao', 'confirmando',
    'confirmada', 'descartada', 'erro'
  ));
