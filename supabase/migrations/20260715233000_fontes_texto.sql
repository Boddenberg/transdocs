begin;

alter table public.preenchimentos
  add column if not exists fontes_texto jsonb not null default '[]'::jsonb;

alter table public.preenchimentos
  drop constraint if exists preenchimentos_fontes_texto_check;

alter table public.preenchimentos
  add constraint preenchimentos_fontes_texto_check
  check (
    jsonb_typeof(fontes_texto) = 'array'
    and octet_length(fontes_texto::text) <= 60000
  );

commit;
