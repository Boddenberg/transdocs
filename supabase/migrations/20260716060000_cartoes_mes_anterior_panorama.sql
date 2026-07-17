begin;

alter table public.cartoes_credito
  add column if not exists usar_mes_anterior_no_panorama boolean not null default false;

comment on column public.cartoes_credito.usar_mes_anterior_no_panorama is
  'Mantem a competencia real da fatura e antecipa em um mes apenas seu impacto no Panorama mensal.';

update public.cartoes_credito as cartao
set usar_mes_anterior_no_panorama = true
from public.contas as conta
where conta.id = cartao.conta_id
  and lower(trim(conta.nome)) in ('cartão itaú uniclass', 'cartao itau uniclass');

commit;
