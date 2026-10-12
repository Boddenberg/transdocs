-- Os avisos do OT Idle no grupo da equipe no WhatsApp.
--
-- O Filipe criou o grupo "Gestao OT IDLE" (12/10/2026) e pediu que o Quinteto
-- avisasse ali o pico de jogadores, a instabilidade, cada compra com o valor e
-- o resto do que a equipe precisa saber na hora, com um interruptor por tipo.
--
-- Uma linha so (`id = 'equipe'`): para onde vai e o que esta ligado. O vigia
-- mora no backend e bate no pulso da ponte; o Quinteto so liga e desliga.
--
-- O destino e um grupo, mas nao um `grupos_whatsapp`: grupo autorizado ali e
-- grupo em que o agente responde, e este e so de avisos. A caixa aceita um
-- destinatario por linha (identidade, grupo ou contato), entao o grupo entra
-- como o contato do app `quinteto` (o numero de quem liberou) com o
-- `destino_jid` do grupo, que a leitura da ponte ja prefere ao telefone.
--
-- Aditivo: uma tabela nova, sem tocar em nada que exista.

begin;

create table if not exists public.quinteto_avisos (
  id text primary key default 'equipe' check (id = 'equipe'),
  destino_jid text check (destino_jid is null or destino_jid ~ '^[0-9-]{5,60}@g\.us$'),
  contato_id uuid references public.contatos_whatsapp(id) on delete set null,
  -- { "<tipo>": false } desliga; o que nao esta aqui vale ligado
  ligados jsonb not null default '{}'::jsonb check (jsonb_typeof(ligados) = 'object'),
  atualizado_por text check (atualizado_por is null or char_length(atualizado_por) <= 120),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

drop trigger if exists quinteto_avisos_atualizado_em on public.quinteto_avisos;
create trigger quinteto_avisos_atualizado_em
before update on public.quinteto_avisos
for each row execute function public.definir_atualizado_em();

alter table public.quinteto_avisos enable row level security;
alter table public.quinteto_avisos force row level security;
revoke all on public.quinteto_avisos from public, anon, authenticated;

commit;
