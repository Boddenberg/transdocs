-- O grupo do casal no canal de conversa do WhatsApp.
--
-- O canal nasceu atendendo **uma pessoa por vez**, e o motivo estava escrito:
-- no grupo ha duas pessoas, "quanto eu gastei" nao tem sujeito, e responder ali
-- imprimiria o extrato de um para o outro. O risco continua exatamente o mesmo.
-- O que muda e a fechadura.
--
-- **No grupo, o sujeito e o vinculo do casal, e nao quem falou.** Quem falou
-- entra na voz da resposta e na autoria de um registro; para *ler*, ele nao
-- conta. E o catalogo de ferramentas do grupo e outro: o FiNancas nao declara
-- nenhuma, entao no grupo o financeiro nao e recusado — ele nao e alcancavel.
-- Essa parte vive no Python (`app/agente/registro.py::salas_do_casal`); o que
-- este arquivo faz e sustenta-la no banco.
--
-- **Aditivo do comeco ao fim.** Nenhuma tabela e recriada, nenhuma coluna sai.
-- As duas colunas que perdem o `not null` ganham no lugar um `check` mais forte
-- do que tinham: `num_nonnulls(...) = 1`, que diz "ou de uma pessoa, ou de um
-- grupo, e nunca das duas coisas". Reverter o deploy nao perde nada.
--
-- **A conversa do grupo e outra linha.** Isso nao e refinamento: o `Assunto` e
-- o que autoriza um anexo (`app/agente/ferramentas/entrega.py`), entao uma
-- memoria compartilhada entre o privado e o grupo seria, literalmente, o
-- vazamento que a decisao original evitava.

begin;

-- ------------------------------------------------------------------- o grupo
--
-- `vinculo_id` e nao `usuario_id`: e o vinculo que diz de quem e a conversa, e e
-- ele que morre junto se o casal desfizer o espaco. Um grupo sem casal nao tem
-- do que falar.
--
-- `autorizado_por` guarda quem ligou o grupo — serve ao suporte e a revogacao,
-- nunca a permissao: dentro do grupo, os dois lados do vinculo valem igual.
create table if not exists public.grupos_whatsapp (
  id uuid primary key default gen_random_uuid(),
  ponte_id uuid not null references public.pontes_whatsapp(id) on delete cascade,
  -- O jid do grupo sem o sufixo "@g.us": so os digitos que o Baileys entrega.
  wa_grupo_id text not null check (wa_grupo_id ~ '^[0-9-]{5,60}$'),
  vinculo_id uuid not null references public.vinculos_casal(id) on delete cascade,
  autorizado_por uuid not null references auth.users(id) on delete cascade,
  nome text check (nome is null or char_length(nome) between 1 and 80),
  autorizado_em timestamptz not null default now(),
  revogado_em timestamptz,
  ultima_mensagem_em timestamptz
);

-- Um grupo ativo por ponte. Reautorizar o mesmo grupo revoga o anterior antes
-- de inserir o novo — mesmo padrao de `pontes_whatsapp_ativa_idx`.
create unique index if not exists grupos_whatsapp_ativo_idx
  on public.grupos_whatsapp (ponte_id, wa_grupo_id) where revogado_em is null;

create index if not exists grupos_whatsapp_vinculo_idx
  on public.grupos_whatsapp (vinculo_id, autorizado_em desc);

alter table public.grupos_whatsapp enable row level security;
alter table public.grupos_whatsapp force row level security;
revoke all on public.grupos_whatsapp from anon, authenticated;

-- ------------------------------------------------------------- a autorizacao
--
-- O codigo do grupo reaproveita a tabela de pareamento inteira: expiracao, uso
-- unico e hash ja estao la e ja foram testados. O que muda e **onde ele vale**.
--
-- `alvo = 'numero'` e o que ja existia: um codigo enviado no privado por um
-- numero desconhecido. `alvo = 'grupo'` so vale enviado dentro de um grupo, por
-- uma identidade ja pareada — e, alem disso, pela mesma pessoa que o gerou. Essa
-- ultima condicao existe porque o codigo do grupo aparece na tela de todos os
-- participantes; sem ela, um terceiro copiaria o codigo e amarraria outro grupo
-- a este vinculo.
alter table public.pareamentos_whatsapp
  add column if not exists alvo text not null default 'numero';

alter table public.pareamentos_whatsapp
  drop constraint if exists pareamentos_whatsapp_alvo_chk;
alter table public.pareamentos_whatsapp
  add constraint pareamentos_whatsapp_alvo_chk
    check (alvo in ('numero', 'grupo'));

-- --------------------------------------------------------- a fila de entrada
--
-- `grupo_id` nulo quer dizer conversa direta, que e o caso de hoje e continua
-- sendo o caminho padrao.
alter table public.recebidas_whatsapp
  add column if not exists grupo_id uuid
    references public.grupos_whatsapp(id) on delete set null;

create index if not exists recebidas_whatsapp_grupo_idx
  on public.recebidas_whatsapp (grupo_id, recebida_em desc)
  where grupo_id is not null;

-- ---------------------------------------------------------- a caixa de saida
--
-- `destino_jid` existe porque `telefone` tem
-- `check (telefone ~ '^[1-9][0-9]{7,14}$')`, e um jid de grupo tem 18 digitos.
-- Afrouxar aquele check para caber o grupo enfraqueceria a validacao do caso
-- comum; uma coluna a mais carrega o destino ja pronto e nao mexe em nada.
--
-- Com ela, a ponte deixa de montar o endereco: ela envia para o `jid` que veio.
-- E uma peca de logica **saindo** da ponte, que e a direcao certa.
alter table public.caixa_whatsapp
  add column if not exists grupo_id uuid
    references public.grupos_whatsapp(id) on delete cascade;

alter table public.caixa_whatsapp
  add column if not exists destino_jid text;

alter table public.caixa_whatsapp
  drop constraint if exists caixa_whatsapp_destino_jid_chk;
alter table public.caixa_whatsapp
  add constraint caixa_whatsapp_destino_jid_chk
    check (destino_jid is null or char_length(destino_jid) between 5 and 80);

alter table public.caixa_whatsapp alter column identidade_id drop not null;

-- A trava que substitui o `not null`: uma resposta tem **um** destinatario.
-- Nem nenhum (uma mensagem sem dono ficaria na fila para sempre), nem dois
-- (nao ha como decidir para onde ela vai).
alter table public.caixa_whatsapp
  drop constraint if exists caixa_whatsapp_destinatario_chk;
alter table public.caixa_whatsapp
  add constraint caixa_whatsapp_destinatario_chk
    check (num_nonnulls(identidade_id, grupo_id) = 1);

-- ------------------------------------------------------------- a conversa
--
-- A unicidade em `identidade_id` era total e vira **parcial**, para caber a
-- linha do grupo, que nao tem identidade. As duas unicidades juntas mais o
-- `check` sao o que garante que o `assunto` do privado e o do grupo nunca
-- moram na mesma linha.
alter table public.conversas_whatsapp alter column identidade_id drop not null;

alter table public.conversas_whatsapp
  drop constraint if exists conversas_whatsapp_identidade_id_key;

create unique index if not exists conversas_whatsapp_identidade_idx
  on public.conversas_whatsapp (identidade_id) where identidade_id is not null;

alter table public.conversas_whatsapp
  add column if not exists grupo_id uuid
    references public.grupos_whatsapp(id) on delete cascade;

create unique index if not exists conversas_whatsapp_grupo_idx
  on public.conversas_whatsapp (grupo_id) where grupo_id is not null;

alter table public.conversas_whatsapp
  drop constraint if exists conversas_whatsapp_dono_chk;
alter table public.conversas_whatsapp
  add constraint conversas_whatsapp_dono_chk
    check (num_nonnulls(identidade_id, grupo_id) = 1);

-- ------------------------------------------------------------------ a leitura
--
-- A unica mudanca no contrato da ponte: uma coluna `jid` com o endereco pronto.
-- `telefone` **continua saindo**, para a ponte de hoje nao quebrar enquanto a
-- nova nao sobe — ela some numa migration posterior, depois que a ponte migrar.
--
-- O `drop` antes do `create` e obrigatorio: acrescentar uma coluna ao retorno
-- muda a assinatura, e `create or replace` recusa isso. O `grant` e refeito
-- logo abaixo, no mesmo commit — a ponte nao ve janela nenhuma.
drop function if exists public.ler_caixa_whatsapp(text, timestamptz, uuid, integer);

create function public.ler_caixa_whatsapp(
  p_chave text,
  p_depois_de timestamptz,
  p_depois_de_id uuid default null,
  p_limite integer default 50
)
returns table (
  id uuid,
  telefone text,
  jid text,
  mensagem text,
  anexos jsonb,
  criada_em timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ponte_id uuid;
begin
  v_ponte_id := public.ponte_da_chave_whatsapp(p_chave);

  return query
  select fila.id,
         fila.telefone,
         -- `coalesce` sem schema de proposito: ele e construcao sintatica do
         -- SQL, e nao funcao. `pg_catalog.coalesce(...)` e erro de sintaxe,
         -- mesmo com `search_path = ''` — que e justamente o motivo de o resto
         -- do arquivo qualificar tudo. Mesma escolha do arquivo do canal.
         coalesce(
           fila.destino_jid,
           fila.telefone || '@s.whatsapp.net'
         ) as jid,
         fila.mensagem,
         coalesce(
           (
             select pg_catalog.jsonb_agg(
                      pg_catalog.jsonb_build_object(
                        'nome', anexo.nome,
                        'mime', anexo.mime,
                        'conteudo_base64', anexo.conteudo_base64
                      )
                      order by anexo.ordem
                    )
               from public.anexos_caixa_whatsapp as anexo
              where anexo.mensagem_id = fila.id
           ),
           '[]'::jsonb
         ) as anexos,
         fila.criada_em
    from public.caixa_whatsapp as fila
   where fila.ponte_id = v_ponte_id
     and fila.status = 'pendente'
     and (
       fila.criada_em > p_depois_de
       or (
         fila.criada_em = p_depois_de
         and (p_depois_de_id is null or fila.id > p_depois_de_id)
       )
     )
   order by fila.criada_em, fila.id
   limit least(greatest(coalesce(p_limite, 50), 1), 200);
end;
$$;

revoke all on function public.ler_caixa_whatsapp(text, timestamptz, uuid, integer)
  from public, authenticated;
grant execute on function public.ler_caixa_whatsapp(text, timestamptz, uuid, integer)
  to anon;

commit;
