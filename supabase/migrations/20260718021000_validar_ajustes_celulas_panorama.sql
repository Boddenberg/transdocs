begin;

create or replace function public.validar_ajuste_celula_panorama()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.fonte_chave not like new.grupo || ':%' then
    raise exception 'A fonte nao pertence ao grupo informado.';
  end if;
  if new.conta_id is not null and not exists (
    select 1 from public.contas
    where id = new.conta_id and usuario_id = new.usuario_id
  ) then
    raise exception 'Conta da celula nao pertence ao usuario.';
  end if;
  if new.divida_id is not null and not exists (
    select 1 from public.dividas
    where id = new.divida_id and usuario_id = new.usuario_id
  ) then
    raise exception 'Divida da celula nao pertence ao usuario.';
  end if;
  if new.categoria_id is not null and not exists (
    select 1 from public.categorias
    where id = new.categoria_id and usuario_id = new.usuario_id
  ) then
    raise exception 'Categoria da celula nao pertence ao usuario.';
  end if;
  return new;
end;
$$;

drop trigger if exists ajustes_celulas_panorama_validar_fonte
  on public.ajustes_celulas_panorama;
create trigger ajustes_celulas_panorama_validar_fonte
before insert or update on public.ajustes_celulas_panorama
for each row execute function public.validar_ajuste_celula_panorama();

commit;
