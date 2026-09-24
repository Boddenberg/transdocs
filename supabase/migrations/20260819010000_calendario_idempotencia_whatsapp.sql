begin;

alter table public.eventos_calendario
  add column if not exists chave_idempotencia text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.eventos_calendario'::regclass
      and conname = 'eventos_calendario_chave_idempotencia_check'
  ) then
    alter table public.eventos_calendario
      add constraint eventos_calendario_chave_idempotencia_check
      check (
        chave_idempotencia is null
        or char_length(chave_idempotencia) between 8 and 200
      );
  end if;
end
$$;

create unique index if not exists eventos_calendario_vinculo_idempotencia_idx
  on public.eventos_calendario (vinculo_id, chave_idempotencia)
  where chave_idempotencia is not null;

comment on column public.eventos_calendario.chave_idempotencia is
  'Identifica a mensagem de origem para impedir eventos duplicados em retries de webhook.';

commit;
