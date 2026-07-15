begin;

create extension if not exists unaccent with schema extensions;
create extension if not exists pg_trgm with schema extensions;

alter table public.documentos
  add column if not exists texto_busca text not null default '';

create or replace function public.normalizar_texto_busca(valor text)
returns text
language sql
immutable
security invoker
set search_path = ''
as $$
  with texto as (
    select lower(extensions.unaccent(coalesce(valor, ''))) as normalizado
  )
  select normalizado || ' ' || regexp_replace(normalizado, '[^[:alnum:]]+', '', 'g')
  from texto;
$$;

create or replace function public.preparar_texto_busca_documento()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  resultado_extracao text;
begin
  select e.resultado::text
    into resultado_extracao
    from public.extracoes_documentos e
   where e.documento_id = new.id;

  new.texto_busca = public.normalizar_texto_busca(
    new.nome_original || ' ' || coalesce(resultado_extracao, '')
  );
  return new;
end;
$$;

drop trigger if exists documentos_preparar_texto_busca on public.documentos;
create trigger documentos_preparar_texto_busca
before insert or update of nome_original on public.documentos
for each row execute function public.preparar_texto_busca_documento();

create or replace function public.sincronizar_texto_busca_extracao()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  documento_alvo uuid;
begin
  if tg_op = 'DELETE' then
    documento_alvo = old.documento_id;
  else
    documento_alvo = new.documento_id;
  end if;

  update public.documentos d
     set texto_busca = public.normalizar_texto_busca(
       d.nome_original || ' ' || coalesce(
         (
           select e.resultado::text
             from public.extracoes_documentos e
            where e.documento_id = documento_alvo
         ),
         ''
       )
     )
   where d.id = documento_alvo;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists extracoes_sincronizar_texto_busca on public.extracoes_documentos;
create trigger extracoes_sincronizar_texto_busca
after insert or update of resultado or delete on public.extracoes_documentos
for each row execute function public.sincronizar_texto_busca_extracao();

update public.documentos d
   set texto_busca = public.normalizar_texto_busca(
     d.nome_original || ' ' || coalesce(
       (
         select e.resultado::text
           from public.extracoes_documentos e
          where e.documento_id = d.id
       ),
       ''
     )
   );

create index if not exists documentos_texto_busca_trgm_idx
  on public.documentos using gin (texto_busca extensions.gin_trgm_ops);

commit;
