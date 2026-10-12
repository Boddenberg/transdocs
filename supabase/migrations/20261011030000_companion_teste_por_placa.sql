-- O teste do VIP tambem e um por placa-mae.
--
-- Ate aqui o teste era um por conta e um por computador, e o computador era o
-- hash do MachineGuid do Windows: formatar ou trocar o MachineGuid no
-- registro dava um computador "novo" e, com outra conta, outro teste. O
-- programa passa a mandar tambem o hash do UUID da placa-mae (SMBIOS), que nao
-- muda com o Windows. Os dois codigos moram em `companion_maquinas` (sais
-- diferentes, nunca coincidem), e o teste so sai se nenhum dos dois ja teve o
-- dele. Sem placa (versao antiga, placa de enfeite) vale o computador, como
-- antes.

begin;

alter table public.companion_maquinas
  add column if not exists fonte text not null default 'windows'
  check (fonte in ('windows', 'placa'));

drop function if exists public.companion_iniciar_teste(uuid, text, integer);

create or replace function public.companion_iniciar_teste(
  p_conta uuid,
  p_maquina text,
  p_horas integer,
  p_placa text default null
) returns timestamptz
language plpgsql
as $$
declare
  v_ate timestamptz;
begin
  insert into public.companion_maquinas (maquina) values (p_maquina)
  on conflict (maquina) do nothing;
  if p_placa is not null then
    insert into public.companion_maquinas (maquina, fonte) values (p_placa, 'placa')
    on conflict (maquina) do nothing;
  end if;

  perform 1 from public.companion_maquinas
   where maquina in (p_maquina, p_placa)
   order by maquina
   for update;
  if exists (
    select 1 from public.companion_maquinas
     where maquina in (p_maquina, p_placa) and teste_em is not null
  ) then
    return null;
  end if;

  update public.companion_contas
     set teste_usado_em = now(),
         vip_ate = greatest(coalesce(vip_ate, now()), now()) + make_interval(hours => p_horas)
   where id = p_conta and teste_usado_em is null
  returning vip_ate into v_ate;
  if v_ate is null then
    return null;
  end if;

  update public.companion_maquinas
     set teste_em = now(), primeira_conta = p_conta
   where maquina in (p_maquina, p_placa);

  insert into public.companion_concessoes (conta_id, motivo, horas, vip_ate)
  values (p_conta, 'teste', p_horas, v_ate);

  return v_ate;
end;
$$;

revoke all on function public.companion_iniciar_teste(uuid, text, integer, text) from public, anon, authenticated;
grant execute on function public.companion_iniciar_teste(uuid, text, integer, text) to service_role;

commit;
