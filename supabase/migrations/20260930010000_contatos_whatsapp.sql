-- Os numeros liberados para receber mensagem sem ter conta no FiNancas.
--
-- Ate aqui a caixa de saida so conhecia dois destinos: a identidade pareada de
-- quem tem conta, e o grupo do casal. O V-idle (o programa do Idle Hero, no
-- computador do Filipe e no de um amigo dele) manda os drops dos chefes para o
-- WhatsApp de quem joga — e o amigo nao tem conta aqui.
--
-- **Digitar o numero nao basta.** O programa roda no computador de outra
-- pessoa e a rota dele e aberta, entao quem decide para onde a ponte pode
-- escrever e esta tabela, preenchida por quem tem conta (`autorizado_por`). Um
-- numero fora dela e recusado antes de a mensagem existir. O texto tambem nao
-- vem pronto: o backend monta a frase a partir de campos curtos.
--
-- Aditivo do comeco ao fim: uma tabela nova, uma coluna nova e a trava do
-- destinatario reescrita com um destino a mais. Reverter o deploy nao perde
-- nada.

begin;

create table if not exists public.contatos_whatsapp (
  id uuid primary key default gen_random_uuid(),
  -- Qual programa pode escrever para este numero. Um numero liberado para os
  -- drops do Idle Hero nao vira destino de outra coisa.
  app text not null check (app ~ '^[a-z0-9_-]{2,40}$'),
  telefone text not null check (telefone ~ '^[1-9][0-9]{7,14}$'),
  nome text check (nome is null or char_length(nome) between 1 and 80),
  -- A ponte que entrega e a da casa de quem liberou.
  autorizado_por uuid not null references auth.users(id) on delete cascade,
  autorizado_em timestamptz not null default now(),
  revogado_em timestamptz
);

create unique index if not exists contatos_whatsapp_ativo_idx
  on public.contatos_whatsapp (app, telefone) where revogado_em is null;

alter table public.contatos_whatsapp enable row level security;
alter table public.contatos_whatsapp force row level security;
revoke all on public.contatos_whatsapp from anon, authenticated;

alter table public.caixa_whatsapp
  add column if not exists contato_id uuid
    references public.contatos_whatsapp(id) on delete cascade;

-- Continua sendo **um** destinatario: a pessoa, o grupo ou o contato.
alter table public.caixa_whatsapp
  drop constraint if exists caixa_whatsapp_destinatario_chk;
alter table public.caixa_whatsapp
  add constraint caixa_whatsapp_destinatario_chk
    check (num_nonnulls(identidade_id, grupo_id, contato_id) = 1);

commit;
