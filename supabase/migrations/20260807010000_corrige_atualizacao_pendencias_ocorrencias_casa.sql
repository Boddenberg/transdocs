begin;

-- Pendências e ocorrências seguem a nomenclatura feminina `atualizada_em`.
-- O gatilho genérico existente escreve em `atualizado_em` e, por isso, fazia
-- qualquer update falhar antes que as transações da Têmis pudessem terminar.
create or replace function public.definir_atualizada_em()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.atualizada_em = now();
  return new;
end;
$$;

drop trigger if exists pendencias_casa_atualizado_em
  on public.pendencias_casa;
drop trigger if exists pendencias_casa_atualizada_em
  on public.pendencias_casa;

create trigger pendencias_casa_atualizada_em
before update on public.pendencias_casa
for each row execute function public.definir_atualizada_em();

drop trigger if exists ocorrencias_casa_atualizado_em
  on public.ocorrencias_casa;
drop trigger if exists ocorrencias_casa_atualizada_em
  on public.ocorrencias_casa;

create trigger ocorrencias_casa_atualizada_em
before update on public.ocorrencias_casa
for each row execute function public.definir_atualizada_em();

commit;
