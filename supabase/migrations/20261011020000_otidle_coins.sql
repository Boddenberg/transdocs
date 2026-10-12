-- O dinheiro do OT Idle: o Pix das coins e para onde as coins dele foram.
--
-- O Pix é cobrado aqui no backend, na mesma conta do Mercado Pago do companion
-- (o Huntrack), e o servidor de jogo põe as coins na carteira dele (o armazém).
-- O armazém é de cada servidor e some quando o servidor recomeça (o beta vira o
-- oficial). Estas tabelas não somem: são o registro do que cada conta pagou, em
-- qual servidor, e de onde as coins de cada pagamento já caíram.
--
-- **otidle_pagamentos**: um Pix por pedido do jogo. A conta que pagou e o
-- personagem que abriu o Pix, o servidor, o pacote, as coins, o valor, a versão
-- dos termos aceita e a vida do pagamento no Mercado Pago.
--
-- **otidle_coins_entregas**: cada vez que as coins de um pagamento caíram numa
-- carteira. O `unique (pagamento_id, servidor)` é a regra inteira: um pagamento
-- rende as coins dele **uma vez em cada servidor que o honra** — no servidor
-- onde foi pago (`motivo = 'pix'`) e, no oficial, de novo, o que se pagou no
-- beta (`motivo = 'devolucao'`).
--
-- **otidle_coins_movimentos**: o extrato de cada carteira, linha a linha (Pix,
-- loja, transferência, mercado, equipe), como o servidor de jogo anotou. O `id`
-- nasce lá: o lote que volta depois de uma falha não duplica nada.
--
-- A conta que pagou não se apaga (`on delete restrict`): o dinheiro tem dono.
-- Tudo com RLS forçado e nada para `anon` nem `authenticated`.

begin;

create table public.otidle_pagamentos (
  -- a referência externa no Mercado Pago
  id uuid primary key,
  conta_id uuid not null references public.otidle_contas(id) on delete restrict,
  servidor text not null check (servidor ~ '^[a-z][a-z0-9-]{1,19}$'),
  -- o pedido no servidor de jogo (o mesmo pedido não abre dois Pix)
  pedido text not null check (char_length(pedido) between 1 and 80),
  -- quem abriu o Pix (o personagem pode sumir depois; o nome fica)
  personagem_id uuid,
  personagem_nome text not null check (char_length(personagem_nome) between 1 and 40),
  pacote text not null check (char_length(pacote) between 1 and 20),
  -- as coins do pacote (o que o valor compra) e o bônus de recarga que valia
  coins integer not null check (coins > 0),
  bonus integer not null default 0 check (bonus >= 0),
  valor_centavos integer not null check (valor_centavos > 0),
  -- a versão dos termos aceita no checkout
  termos text check (termos is null or char_length(termos) <= 20),
  provedor text not null default 'mercadopago' check (provedor in ('mercadopago')),
  provedor_id text,
  status text not null default 'pendente'
    check (status in ('pendente', 'aprovado', 'expirado', 'cancelado', 'recusado', 'estornado')),
  pix_copia_cola text,
  pix_qr_base64 text,
  expira_em timestamptz not null,
  aprovado_em timestamptz,
  -- devolvido pelo Mercado Pago depois de aprovado (estorno, contestação)
  estornado_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create unique index otidle_pagamentos_pedido_idx on public.otidle_pagamentos (servidor, pedido);
create unique index otidle_pagamentos_provedor_idx
  on public.otidle_pagamentos (provedor, provedor_id) where provedor_id is not null;
create index otidle_pagamentos_conta_idx on public.otidle_pagamentos (conta_id, criado_em desc);
create index otidle_pagamentos_servidor_idx on public.otidle_pagamentos (servidor, status, criado_em desc);

create trigger otidle_pagamentos_atualizado_em
before update on public.otidle_pagamentos
for each row execute function public.definir_atualizado_em();

create table public.otidle_coins_entregas (
  id bigint generated always as identity primary key,
  pagamento_id uuid not null references public.otidle_pagamentos(id) on delete restrict,
  conta_id uuid not null references public.otidle_contas(id) on delete restrict,
  -- a carteira de qual servidor recebeu
  servidor text not null check (servidor ~ '^[a-z][a-z0-9-]{1,19}$'),
  motivo text not null check (motivo in ('pix', 'devolucao')),
  coins integer not null check (coins > 0),
  -- a carteira depois do crédito, como o servidor de jogo viu
  saldo_depois integer,
  criado_em timestamptz not null default now(),
  unique (pagamento_id, servidor)
);

create index otidle_coins_entregas_conta_idx on public.otidle_coins_entregas (conta_id, criado_em desc);

create table public.otidle_coins_movimentos (
  id uuid primary key,
  servidor text not null check (servidor ~ '^[a-z][a-z0-9-]{1,19}$'),
  conta_id uuid not null,
  personagem_id uuid,
  personagem_nome text check (personagem_nome is null or char_length(personagem_nome) <= 40),
  tipo text not null check (char_length(tipo) between 1 and 20),
  -- positivo entra, negativo sai (0: premium ou troca de nome, sem coins)
  coins integer not null,
  -- a carteira depois do movimento
  saldo integer not null,
  texto text not null check (char_length(texto) <= 300),
  -- o pagamento, o pedido ou a oferta de onde veio, quando há
  referencia text check (referencia is null or char_length(referencia) <= 80),
  em timestamptz not null,
  criado_em timestamptz not null default now()
);

create index otidle_coins_movimentos_conta_idx on public.otidle_coins_movimentos (conta_id, em desc);
create index otidle_coins_movimentos_servidor_idx on public.otidle_coins_movimentos (servidor, em desc);

alter table public.otidle_pagamentos enable row level security;
alter table public.otidle_pagamentos force row level security;
alter table public.otidle_coins_entregas enable row level security;
alter table public.otidle_coins_entregas force row level security;
alter table public.otidle_coins_movimentos enable row level security;
alter table public.otidle_coins_movimentos force row level security;

revoke all on public.otidle_pagamentos, public.otidle_coins_entregas, public.otidle_coins_movimentos
  from public, anon, authenticated;

-- O que falta cair nas carteiras de `p_servidor`: os Pix aprovados nele e,
-- dos servidores de `p_origens` (o beta, para o oficial), os aprovados lá, que
-- ainda não têm entrega neste servidor. As coins de cada um: no Pix, as do
-- pacote mais o bônus de recarga que valia; na devolução, só as do pacote (o
-- que o dinheiro compra).
create or replace function public.otidle_coins_a_entregar(p_servidor text, p_origens text[])
returns table (
  pagamento_id uuid,
  conta_id uuid,
  motivo text,
  coins integer,
  valor_centavos integer,
  servidor_origem text,
  pedido text,
  personagem_nome text,
  aprovado_em timestamptz
)
language sql
stable
as $$
  select p.id,
         p.conta_id,
         case when p.servidor = p_servidor then 'pix' else 'devolucao' end,
         case when p.servidor = p_servidor then p.coins + p.bonus else p.coins end,
         p.valor_centavos,
         p.servidor,
         p.pedido,
         p.personagem_nome,
         p.aprovado_em
    from public.otidle_pagamentos as p
   where p.status = 'aprovado'
     and (p.servidor = p_servidor or p.servidor = any(p_origens))
     and not exists (
       select 1 from public.otidle_coins_entregas as e
        where e.pagamento_id = p.id and e.servidor = p_servidor
     )
   order by p.aprovado_em nulls last, p.criado_em
   limit 500;
$$;

revoke all on function public.otidle_coins_a_entregar(text, text[]) from public, anon, authenticated;
grant execute on function public.otidle_coins_a_entregar(text, text[]) to service_role;

commit;
