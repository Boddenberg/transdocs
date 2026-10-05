-- O companion da Grade que se vende: contas, PCs, VIP, Pix, WhatsApp e versões.
--
-- A Grade pessoal (`projetos/grade-idle`) continua sem nada disto. O que nasce
-- aqui é o lado de cá da edição que vai para estranhos: quem compra cria uma
-- conta no site (não no Supabase Auth — este projeto é compartilhado com o
-- FiNanças e com o transdocs, e um cliente com JWT do GoTrue chegaria ao
-- PostgREST com papel `authenticated`), entra no programa e recebe uma licença
-- assinada que diz o plano dele.
--
-- **O VIP é um prazo, não um booleano.** `vip_ate` só anda para a frente, e só
-- por `companion_conceder`/`companion_iniciar_teste`, que somam horas a partir
-- do maior entre agora e o prazo atual — numa linha travada, para dois Pix
-- aprovados no mesmo segundo não virarem um só. Cada soma fica anotada em
-- `companion_concessoes`; o `unique` do `pagamento_id` é o que impede o mesmo
-- Pix (o webhook chega mais de uma vez) de render dois meses.
--
-- **O teste de 12 h é uma vez por conta e uma vez por computador.** Sem a
-- segunda trava, criar contas novas seria VIP de graça para sempre. O
-- computador é um hash do MachineGuid feito no programa; o GUID não sai de lá.
--
-- Tudo com RLS forçado e nada para `anon` nem `authenticated`: quem lê e
-- grava é o backend, com a service role.

begin;

create table public.companion_contas (
  id uuid primary key default gen_random_uuid(),
  email text not null check (email = lower(email) and char_length(email) between 5 and 254),
  nome text not null check (char_length(nome) between 1 and 60),
  senha_hash text not null,
  telefone text check (telefone is null or telefone ~ '^[1-9][0-9]{7,14}$'),
  telefone_verificado_em timestamptz,
  contato_id uuid references public.contatos_whatsapp(id) on delete set null,
  vip_ate timestamptz,
  teste_usado_em timestamptz,
  bloqueada_em timestamptz,
  criada_em timestamptz not null default now(),
  vista_em timestamptz
);

create unique index companion_contas_email_idx on public.companion_contas (email);

-- Uma sessão por aparelho de onde se entrou: o site (navegador) ou o programa.
-- O token não mora aqui, só o hash dele.
create table public.companion_sessoes (
  id uuid primary key default gen_random_uuid(),
  conta_id uuid not null references public.companion_contas(id) on delete cascade,
  token_hash text not null unique,
  origem text not null check (origem in ('site', 'app')),
  maquina text check (maquina is null or maquina ~ '^[0-9A-Z]{4}(-[0-9A-Z]{4}){3}$'),
  versao text check (versao is null or char_length(versao) <= 20),
  criada_em timestamptz not null default now(),
  vista_em timestamptz not null default now(),
  encerrada_em timestamptz,
  motivo_fim text check (motivo_fim is null or motivo_fim in ('saiu', 'outro_computador', 'bloqueada', 'senha_trocada'))
);

create index companion_sessoes_abertas_idx
  on public.companion_sessoes (conta_id, origem) where encerrada_em is null;

create table public.companion_maquinas (
  maquina text primary key check (maquina ~ '^[0-9A-Z]{4}(-[0-9A-Z]{4}){3}$'),
  primeira_conta uuid references public.companion_contas(id) on delete set null,
  teste_em timestamptz,
  criada_em timestamptz not null default now()
);

create table public.companion_pagamentos (
  id uuid primary key default gen_random_uuid(),
  conta_id uuid not null references public.companion_contas(id) on delete cascade,
  provedor text not null default 'mercadopago' check (provedor in ('mercadopago')),
  provedor_id text,
  valor_centavos integer not null check (valor_centavos > 0),
  dias integer not null check (dias between 1 and 366),
  status text not null default 'pendente'
    check (status in ('pendente', 'aprovado', 'expirado', 'cancelado', 'recusado')),
  pix_copia_cola text,
  pix_qr_base64 text,
  expira_em timestamptz,
  aprovado_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create unique index companion_pagamentos_provedor_idx
  on public.companion_pagamentos (provedor, provedor_id) where provedor_id is not null;
create index companion_pagamentos_conta_idx
  on public.companion_pagamentos (conta_id, criado_em desc);

create trigger companion_pagamentos_atualizado_em
before update on public.companion_pagamentos
for each row execute function public.definir_atualizado_em();

create table public.companion_concessoes (
  id uuid primary key default gen_random_uuid(),
  conta_id uuid not null references public.companion_contas(id) on delete cascade,
  motivo text not null check (motivo in ('teste', 'pagamento', 'cortesia', 'ajuste')),
  horas integer not null check (horas between -8784 and 8784),
  pagamento_id uuid unique references public.companion_pagamentos(id) on delete set null,
  vip_ate timestamptz,
  observacao text check (observacao is null or char_length(observacao) <= 200),
  criada_em timestamptz not null default now()
);

create index companion_concessoes_conta_idx
  on public.companion_concessoes (conta_id, criada_em desc);

-- O código que prova que o número é de quem está na conta. Hasheado, como o
-- do pareamento do FiNanças: uma cópia do banco não pode ligar um número.
create table public.companion_codigos_whatsapp (
  id uuid primary key default gen_random_uuid(),
  conta_id uuid not null references public.companion_contas(id) on delete cascade,
  telefone text not null check (telefone ~ '^[1-9][0-9]{7,14}$'),
  codigo_hash text not null,
  tentativas integer not null default 0,
  expira_em timestamptz not null,
  usado_em timestamptz,
  criado_em timestamptz not null default now()
);

create index companion_codigos_whatsapp_conta_idx
  on public.companion_codigos_whatsapp (conta_id, criado_em desc);
create index companion_codigos_whatsapp_telefone_idx
  on public.companion_codigos_whatsapp (telefone, criado_em desc);

-- As versões do programa: o atualizador lê a última publicada. O arquivo mora
-- fora daqui (o instalador passa de 100 MB); a linha guarda o endereço e o
-- sha512 que o atualizador confere.
create table public.companion_versoes (
  versao text primary key check (versao ~ '^[0-9]+\.[0-9]+\.[0-9]+$'),
  arquivo_url text not null check (arquivo_url ~ '^https://'),
  sha512 text not null,
  tamanho bigint not null check (tamanho > 0),
  notas text check (notas is null or char_length(notas) <= 2000),
  obrigatoria boolean not null default false,
  downloads integer not null default 0,
  publicada_em timestamptz,
  criada_em timestamptz not null default now()
);

alter table public.companion_contas enable row level security;
alter table public.companion_contas force row level security;
alter table public.companion_sessoes enable row level security;
alter table public.companion_sessoes force row level security;
alter table public.companion_maquinas enable row level security;
alter table public.companion_maquinas force row level security;
alter table public.companion_pagamentos enable row level security;
alter table public.companion_pagamentos force row level security;
alter table public.companion_concessoes enable row level security;
alter table public.companion_concessoes force row level security;
alter table public.companion_codigos_whatsapp enable row level security;
alter table public.companion_codigos_whatsapp force row level security;
alter table public.companion_versoes enable row level security;
alter table public.companion_versoes force row level security;

revoke all on public.companion_contas, public.companion_sessoes, public.companion_maquinas,
  public.companion_pagamentos, public.companion_concessoes, public.companion_codigos_whatsapp,
  public.companion_versoes
  from anon, authenticated;

-- Soma (ou tira) horas de VIP numa conta. Devolve o prazo novo, ou `null`
-- quando o pagamento já tinha rendido o dele.
create or replace function public.companion_conceder(
  p_conta uuid,
  p_horas integer,
  p_motivo text,
  p_pagamento uuid default null,
  p_observacao text default null
) returns timestamptz
language plpgsql
as $$
declare
  v_ate timestamptz;
begin
  if p_pagamento is not null then
    perform 1 from public.companion_concessoes where pagamento_id = p_pagamento;
    if found then
      return null;
    end if;
  end if;

  update public.companion_contas
     set vip_ate = greatest(coalesce(vip_ate, now()), now()) + make_interval(hours => p_horas)
   where id = p_conta
  returning vip_ate into v_ate;

  if v_ate is null then
    raise exception 'companion_conta_inexistente';
  end if;

  -- Dois webhooks do mesmo Pix ao mesmo tempo: os dois passam do `perform`,
  -- e o `unique` derruba o segundo inteiro — inclusive o update acima.
  insert into public.companion_concessoes (conta_id, motivo, horas, pagamento_id, vip_ate, observacao)
  values (p_conta, p_motivo, p_horas, p_pagamento, v_ate, p_observacao);

  return v_ate;
end;
$$;

-- O teste de VIP da primeira entrada pelo programa. `null` quando a conta ou o
-- computador já tiveram o deles.
create or replace function public.companion_iniciar_teste(
  p_conta uuid,
  p_maquina text,
  p_horas integer
) returns timestamptz
language plpgsql
as $$
declare
  v_ate timestamptz;
begin
  insert into public.companion_maquinas (maquina) values (p_maquina)
  on conflict (maquina) do nothing;

  perform 1 from public.companion_maquinas
   where maquina = p_maquina and teste_em is null
   for update;
  if not found then
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
   where maquina = p_maquina;

  insert into public.companion_concessoes (conta_id, motivo, horas, vip_ate)
  values (p_conta, 'teste', p_horas, v_ate);

  return v_ate;
end;
$$;

create or replace function public.companion_contar_download(p_versao text)
returns void
language sql
as $$
  update public.companion_versoes set downloads = downloads + 1 where versao = p_versao;
$$;

revoke all on function public.companion_conceder(uuid, integer, text, uuid, text) from public, anon, authenticated;
revoke all on function public.companion_iniciar_teste(uuid, text, integer) from public, anon, authenticated;
revoke all on function public.companion_contar_download(text) from public, anon, authenticated;
grant execute on function public.companion_conceder(uuid, integer, text, uuid, text) to service_role;
grant execute on function public.companion_iniciar_teste(uuid, text, integer) to service_role;
grant execute on function public.companion_contar_download(text) to service_role;

commit;
