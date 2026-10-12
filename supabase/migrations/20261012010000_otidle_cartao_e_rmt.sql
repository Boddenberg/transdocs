-- O cartão de crédito nas coins e o mercado em reais (RMT) do OT Idle.
--
-- **Cartão**: o pagamento das coins ganha a forma (`pix` ou `cartao`). O cartão
-- é uma preferência do Checkout Pro: a pessoa paga na página do Mercado Pago, e
-- o pagamento só existe depois (acha-se pela referência). Por isso o
-- `provedor_id` do cartão nasce vazio e o `checkout_url` guarda a página.
--
-- **RMT** (o mercado em reais, como o do Huntera): um jogador vende um item a
-- outro por dinheiro. O comprador paga (Pix ou cartão) na conta do Mercado Pago
-- do jogo; o item vai do anúncio para o depot dele; o vendedor ganha o valor
-- menos a taxa da casa num saldo em reais, retido alguns dias (o estorno e o MED
-- chegam nesse prazo) e sacado por Pix, pago pela equipe.
--
-- **otidle_rmt_recebedores**: para onde vai o saque de cada conta (a chave Pix
--   e o titular) e quando ela declarou ter 18 anos.
-- **otidle_rmt_vendas**: cada compra, de quem para quem, qual item, quanto, a
--   taxa, a vida do pagamento e quando o item chegou (`entregue_em`). O valor do
--   vendedor fica livre em `liberado_em`.
-- **otidle_rmt_saques**: cada pedido de saque e o que a equipe fez com ele.
--
-- O saldo do vendedor é a soma das vendas entregues e liberadas menos os saques
-- que não foram recusados; venda estornada não conta. Tudo com RLS forçado e
-- nada para `anon` nem `authenticated`, como o Pix das coins.

begin;

alter table public.otidle_pagamentos
  add column forma text not null default 'pix' check (forma in ('pix', 'cartao')),
  add column preferencia_id text,
  add column checkout_url text;

create table public.otidle_rmt_recebedores (
  conta_id uuid primary key references public.otidle_contas(id) on delete restrict,
  titular text not null check (char_length(titular) between 3 and 80),
  tipo_chave text not null check (tipo_chave in ('cpf', 'cnpj', 'email', 'telefone', 'aleatoria')),
  chave_pix text not null check (char_length(chave_pix) between 3 and 140),
  maior_de_idade_em timestamptz not null,
  termos text check (termos is null or char_length(termos) <= 20),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create trigger otidle_rmt_recebedores_atualizado_em
before update on public.otidle_rmt_recebedores
for each row execute function public.definir_atualizado_em();

create table public.otidle_rmt_vendas (
  -- a referência externa no Mercado Pago
  id uuid primary key,
  servidor text not null check (servidor ~ '^[a-z][a-z0-9-]{1,19}$'),
  -- o anúncio e o pedido no servidor de jogo (o mesmo pedido não cobra duas vezes)
  oferta text not null check (char_length(oferta) between 1 and 80),
  pedido text not null check (char_length(pedido) between 1 and 80),
  vendedor_conta_id uuid not null references public.otidle_contas(id) on delete restrict,
  vendedor_personagem_id uuid,
  vendedor_nome text not null check (char_length(vendedor_nome) between 1 and 40),
  comprador_conta_id uuid not null references public.otidle_contas(id) on delete restrict,
  comprador_personagem_id uuid,
  comprador_nome text not null check (char_length(comprador_nome) between 1 and 40),
  item text not null check (char_length(item) between 1 and 60),
  qtd integer not null check (qtd > 0),
  valor_centavos integer not null check (valor_centavos > 0),
  taxa_centavos integer not null check (taxa_centavos >= 0),
  liquido_centavos integer not null check (liquido_centavos >= 0),
  forma text not null check (forma in ('pix', 'cartao')),
  termos text check (termos is null or char_length(termos) <= 20),
  provedor text not null default 'mercadopago' check (provedor in ('mercadopago')),
  provedor_id text,
  preferencia_id text,
  status text not null default 'pendente'
    check (status in ('pendente', 'aprovado', 'expirado', 'cancelado', 'recusado', 'estornado')),
  pix_copia_cola text,
  pix_qr_base64 text,
  checkout_url text,
  expira_em timestamptz not null,
  aprovado_em timestamptz,
  estornado_em timestamptz,
  -- o item chegou ao depot de quem comprou
  entregue_em timestamptz,
  -- o valor do vendedor sai da retenção
  liberado_em timestamptz,
  -- o que deu errado depois de pago (o anúncio sumiu: o dinheiro volta)
  problema text check (problema is null or char_length(problema) <= 200),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  check (valor_centavos = taxa_centavos + liquido_centavos),
  check (vendedor_conta_id <> comprador_conta_id)
);

create unique index otidle_rmt_vendas_pedido_idx on public.otidle_rmt_vendas (servidor, pedido);
create unique index otidle_rmt_vendas_provedor_idx
  on public.otidle_rmt_vendas (provedor, provedor_id) where provedor_id is not null;
create index otidle_rmt_vendas_vendedor_idx on public.otidle_rmt_vendas (vendedor_conta_id, criado_em desc);
create index otidle_rmt_vendas_comprador_idx on public.otidle_rmt_vendas (comprador_conta_id, criado_em desc);
create index otidle_rmt_vendas_servidor_idx on public.otidle_rmt_vendas (servidor, status, criado_em desc);

create trigger otidle_rmt_vendas_atualizado_em
before update on public.otidle_rmt_vendas
for each row execute function public.definir_atualizado_em();

create table public.otidle_rmt_saques (
  id uuid primary key,
  conta_id uuid not null references public.otidle_contas(id) on delete restrict,
  valor_centavos integer not null check (valor_centavos > 0),
  -- a chave e o titular de quando pediu (trocar depois não muda este)
  titular text not null,
  tipo_chave text not null,
  chave_pix text not null,
  status text not null default 'pedido' check (status in ('pedido', 'pago', 'recusado')),
  -- o identificador do Pix que a equipe mandou, ou o motivo da recusa
  comprovante text check (comprovante is null or char_length(comprovante) <= 120),
  motivo text check (motivo is null or char_length(motivo) <= 200),
  pedido_em timestamptz not null default now(),
  resolvido_em timestamptz
);

create index otidle_rmt_saques_conta_idx on public.otidle_rmt_saques (conta_id, pedido_em desc);
create index otidle_rmt_saques_status_idx on public.otidle_rmt_saques (status, pedido_em);
-- um saque aberto por conta
create unique index otidle_rmt_saques_um_aberto_idx on public.otidle_rmt_saques (conta_id) where status = 'pedido';

alter table public.otidle_rmt_recebedores enable row level security;
alter table public.otidle_rmt_recebedores force row level security;
alter table public.otidle_rmt_vendas enable row level security;
alter table public.otidle_rmt_vendas force row level security;
alter table public.otidle_rmt_saques enable row level security;
alter table public.otidle_rmt_saques force row level security;

revoke all on public.otidle_rmt_recebedores, public.otidle_rmt_vendas, public.otidle_rmt_saques
  from public, anon, authenticated;

commit;
