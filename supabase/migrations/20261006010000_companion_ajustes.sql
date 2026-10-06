-- O preço do VIP e o teste grátis do companion, mudados pelo Huntrack Admin
-- sem deploy. Uma linha só (id = 1); sem ela, o backend usa o que está no
-- ambiente (COMPANION_PRECO_CENTAVOS e COMPANION_HORAS_TESTE).
--
-- Começa em R$ 10,00 por 30 dias e 7 dias de teste.

begin;

create table public.companion_ajustes (
  id smallint primary key default 1 check (id = 1),
  preco_centavos integer not null check (preco_centavos between 100 and 100000),
  horas_de_teste integer not null check (horas_de_teste between 0 and 720),
  atualizado_em timestamptz not null default now(),
  atualizado_por text check (atualizado_por is null or char_length(atualizado_por) <= 254)
);

insert into public.companion_ajustes (id, preco_centavos, horas_de_teste)
values (1, 1000, 168);

alter table public.companion_ajustes enable row level security;
alter table public.companion_ajustes force row level security;

revoke all on public.companion_ajustes from anon, authenticated;

commit;
