-- Caixa de saída do Finanças para a ponte local do WhatsApp.
--
-- O backend grava a mensagem final nesta tabela. A ponte não lê registros da
-- Casa, perfis ou qualquer outra tabela: chama somente a função abaixo e
-- repassa o campo `mensagem` sem interpretar seu conteúdo.

create table public.mensagens_whatsapp_casa (
  id uuid primary key default gen_random_uuid(),
  registro_id uuid not null unique
    references public.registros_atividades_casa(id) on delete cascade,
  vinculo_id uuid not null
    references public.vinculos_casal(id) on delete cascade,
  mensagem text not null
    check (char_length(mensagem) between 1 and 4096),
  criada_em timestamptz not null default now()
);

create index mensagens_whatsapp_casa_cursor_idx
  on public.mensagens_whatsapp_casa (vinculo_id, criada_em, id);

alter table public.mensagens_whatsapp_casa enable row level security;
alter table public.mensagens_whatsapp_casa force row level security;

revoke all on public.mensagens_whatsapp_casa from anon, authenticated;

create or replace function public.remover_mensagem_whatsapp_casa_excluida()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.excluida_em is null and new.excluida_em is not null then
    delete from public.mensagens_whatsapp_casa
     where registro_id = new.id;
  end if;
  return new;
end;
$$;

revoke all on function public.remover_mensagem_whatsapp_casa_excluida()
  from public, anon, authenticated;

create trigger remover_mensagem_whatsapp_casa_ao_excluir_registro
after update of excluida_em on public.registros_atividades_casa
for each row execute function public.remover_mensagem_whatsapp_casa_excluida();

create or replace function public.ler_mensagens_whatsapp_casa(
  p_chave text,
  p_depois_de timestamptz,
  p_depois_de_id uuid default null,
  p_limite integer default 100
)
returns table (
  id uuid,
  mensagem text,
  criada_em timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_vinculo_id uuid;
begin
  if p_chave is null
    or left(p_chave, 9) <> 'casa_wpp_'
    or char_length(p_chave) < 40
  then
    raise insufficient_privilege using message =
      'Chave da ponte inválida ou revogada.';
  end if;

  select ponte.vinculo_id
    into v_vinculo_id
    from public.pontes_whatsapp_casa as ponte
   where ponte.chave_hash =
         pg_catalog.encode(extensions.digest(p_chave, 'sha256'), 'hex')
     and ponte.revogada_em is null
   limit 1;

  if v_vinculo_id is null then
    raise insufficient_privilege using message =
      'Chave da ponte inválida ou revogada.';
  end if;

  return query
  select fila.id, fila.mensagem, fila.criada_em
    from public.mensagens_whatsapp_casa as fila
   where fila.vinculo_id = v_vinculo_id
     and (
       fila.criada_em > p_depois_de
       or (
         fila.criada_em = p_depois_de
         and (p_depois_de_id is null or fila.id > p_depois_de_id)
       )
     )
   order by fila.criada_em, fila.id
   limit least(greatest(coalesce(p_limite, 100), 1), 500);
end;
$$;

revoke all on function public.ler_mensagens_whatsapp_casa(
  text,
  timestamptz,
  uuid,
  integer
) from public, authenticated;
grant execute on function public.ler_mensagens_whatsapp_casa(
  text,
  timestamptz,
  uuid,
  integer
) to anon;
