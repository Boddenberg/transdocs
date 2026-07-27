begin;

-- O Cofre: os acessos da casa, guardados fechados -----------------------------
--
-- A diferenca deste app para os outros tres cabe em uma frase: **o backend nao
-- sabe o que ele guarda**. Nenhuma coluna aqui embaixo tem senha, login, site
-- ou anotacao. Tem bytes.
--
-- Por que assim, e nao "cifrado no servidor":
--
--   1. este backend fala com o Supabase pela `service_role`, que passa por cima
--      de toda RLS. Uma rota nova que esqueca o filtro de `usuario_id` vaza a
--      tabela inteira — o que para uma receita e um susto e para a senha do
--      banco e outra coisa;
--   2. o mesmo processo que leria essas linhas e o que monta prompt e manda
--      para a OpenAI. Nao ha como prometer que um contexto futuro nao vai
--      varrer uma tabela a mais. Com o claro fora do servidor, nao ha promessa
--      a cumprir: nao existe o dado para vazar.
--
-- O desenho completo esta em `docs/COFRE.md`. Em uma respiracao:
--
--   identidade   um par de chaves ECDH P-256 por pessoa. A publica fica aqui em
--                claro (e para isso que ela serve); a privada nunca chega.
--   guarda       a chave privada embrulhada. Um guarda por jeito de destravar:
--                o dispositivo (chave nao-extraivel no IndexedDB do navegador),
--                o codigo de recuperacao, e — se a pessoa ligar — a senha
--                mestra. Todos embrulham a MESMA chave privada.
--   item         o acesso inteiro (titulo, login, senha, notas) num unico JSON
--                cifrado com uma DEK aleatoria. Nem o titulo fica em claro.
--   envelope     a DEK embrulhada para um destinatario, via ECDH efemero. Um
--                envelope para mim; dois quando o acesso e do casal.

-- A chave publica de cada pessoa ---------------------------------------------
--
-- E o que permite ao marido receber um acesso sem que ninguem no meio saiba o
-- que ele recebeu. `impressao` e o SHA-256 dela em hex: os dois comparam esses
-- caracteres na tela, uma vez, e sabem que ninguem trocou a chave no caminho.
create table if not exists public.cofre_identidades (
  usuario_id uuid primary key references auth.users(id) on delete cascade,
  -- SPKI em base64. ECDH P-256, o que o WebCrypto tem em todo navegador.
  chave_publica text not null,
  impressao text not null,
  criada_em timestamptz not null default now()
);

-- Os jeitos de destravar ------------------------------------------------------
--
-- A chave privada nao existe em claro em lugar nenhum: existe embrulhada, uma
-- vez por guarda. Destravar e desembrulhar por qualquer um deles.
--
--   dispositivo  o embrulho e feito por uma chave AES **nao-extraivel** que
--                mora no IndexedDB daquele navegador. O servidor tem o
--                embrulho e nao tem a chave; o navegador tem a chave e nao
--                consegue le-la (o WebCrypto usa, o JavaScript nao copia).
--                E o que faz o cofre abrir sem digitar nada.
--   recuperacao  PBKDF2 de um codigo aleatorio mostrado uma vez, na criacao.
--                E por ele que um dispositivo novo entra — e a unica saida se
--                o navegador for limpo.
--   senha        opcional, ligavel depois: uma senha mestra por cima. Como e
--                so mais um guarda, ligar nao remexe em nenhum item.
create table if not exists public.cofre_guardas (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  tipo text not null check (tipo in ('dispositivo', 'recuperacao', 'senha')),
  apelido text not null check (char_length(apelido) between 1 and 60),
  -- Sal e iteracoes so existem para os guardas derivados de algo digitado.
  sal text,
  iteracoes integer check (iteracoes is null or iteracoes >= 100000),
  nonce text not null,
  chave_privada_cifrada text not null,
  criado_em timestamptz not null default now(),
  usado_em timestamptz
);

-- Dispositivo a pessoa tem quantos quiser; dos outros dois, um so. Parcial
-- porque `unique` normal impediria o segundo navegador.
create unique index if not exists cofre_guardas_unico_idx
  on public.cofre_guardas (usuario_id, tipo)
  where tipo in ('recuperacao', 'senha');

create index if not exists cofre_guardas_usuario_idx
  on public.cofre_guardas (usuario_id, criado_em);

-- Os acessos ------------------------------------------------------------------
--
-- Um item e um blob e mais nada. `do_casal` fica em claro de proposito: e o
-- unico bit que a tela precisa saber antes de destravar, e ele nao conta o que
-- o acesso e — so que existe um envelope a mais.
create table if not exists public.cofre_itens (
  id uuid primary key default gen_random_uuid(),
  -- O dono. Quem compartilha continua sendo dono; o outro so recebe envelope.
  usuario_id uuid not null references auth.users(id) on delete cascade,
  -- AES-256-GCM do JSON inteiro, em base64.
  --
  -- O `check` nao prova que ha cifra aqui — base64 de texto tambem e base64.
  -- Ele prova que nao ha texto *cru*: "senha do wifi: casa1234" tem espaco e
  -- dois-pontos, e nao passa. E um para-choque contra a rota escrita com
  -- pressa, nao contra um atacante. Quem garante o resto e nao existir, em
  -- lugar nenhum do backend, codigo que saiba montar esse JSON.
  segredo_cifrado text not null
    check (segredo_cifrado ~ '^[A-Za-z0-9+/]+={0,2}$' and char_length(segredo_cifrado) >= 24),
  nonce text not null,
  do_casal boolean not null default false,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create index if not exists cofre_itens_usuario_idx
  on public.cofre_itens (usuario_id, atualizado_em desc);

-- A chave de cada item, embrulhada para quem pode abrir -----------------------
--
-- ECDH efemero (ECIES): quem cifra gera um par descartavel, faz o segredo
-- compartilhado com a chave publica do destinatario, deriva por HKDF e embrulha
-- a DEK. A chave efemera publica vem junto; a privada dela morre no navegador.
--
-- Tirar o envelope do parceiro tranca o acesso para ele daqui em diante — e nao
-- desfaz o que ele ja viu. A tela diz isso com todas as letras e oferece trocar
-- a senha, que e o unico jeito de tornar sem efeito o que ja foi lido.
create table if not exists public.cofre_envelopes (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.cofre_itens(id) on delete cascade,
  -- O destinatario. `usuario_id` e nao `destinatario_id` porque o reset de
  -- dados varre todas as tabelas dos apps por esta coluna.
  usuario_id uuid not null references auth.users(id) on delete cascade,
  chave_efemera text not null,
  nonce text not null,
  dek_cifrada text not null,
  criado_em timestamptz not null default now(),
  unique (item_id, usuario_id)
);

create index if not exists cofre_envelopes_usuario_idx
  on public.cofre_envelopes (usuario_id);

-- RLS ------------------------------------------------------------------------
--
-- O backend usa a service_role e passa por cima disto. Fica ligado do mesmo
-- jeito, pelo mesmo motivo que se tranca a porta de dentro: no dia em que uma
-- chave anon vazar ou alguem consultar pelo PostgREST direto, a regra ja esta
-- de pe. Aqui a redundancia e barata e o erro e caro.
alter table public.cofre_identidades enable row level security;
alter table public.cofre_identidades force row level security;
alter table public.cofre_guardas enable row level security;
alter table public.cofre_guardas force row level security;
alter table public.cofre_itens enable row level security;
alter table public.cofre_itens force row level security;
alter table public.cofre_envelopes enable row level security;
alter table public.cofre_envelopes force row level security;

drop policy if exists cofre_identidade_propria on public.cofre_identidades;
create policy cofre_identidade_propria on public.cofre_identidades
for all to authenticated
using ((select auth.uid()) = usuario_id)
with check ((select auth.uid()) = usuario_id);

drop policy if exists cofre_guardas_proprios on public.cofre_guardas;
create policy cofre_guardas_proprios on public.cofre_guardas
for all to authenticated
using ((select auth.uid()) = usuario_id)
with check ((select auth.uid()) = usuario_id);

-- Ler: o dono e quem tem envelope. Escrever: so o dono.
drop policy if exists cofre_itens_leitura on public.cofre_itens;
create policy cofre_itens_leitura on public.cofre_itens
for select to authenticated
using (
  (select auth.uid()) = usuario_id
  or exists (
    select 1 from public.cofre_envelopes envelope
     where envelope.item_id = cofre_itens.id
       and envelope.usuario_id = (select auth.uid())
  )
);

drop policy if exists cofre_itens_do_dono on public.cofre_itens;
create policy cofre_itens_do_dono on public.cofre_itens
for all to authenticated
using ((select auth.uid()) = usuario_id)
with check ((select auth.uid()) = usuario_id);

-- Um envelope se le sendo o destinatario; se escreve sendo o dono do item.
drop policy if exists cofre_envelopes_do_destinatario on public.cofre_envelopes;
create policy cofre_envelopes_do_destinatario on public.cofre_envelopes
for select to authenticated
using ((select auth.uid()) = usuario_id);

drop policy if exists cofre_envelopes_do_dono_do_item on public.cofre_envelopes;
create policy cofre_envelopes_do_dono_do_item on public.cofre_envelopes
for all to authenticated
using (
  exists (
    select 1 from public.cofre_itens item
     where item.id = cofre_envelopes.item_id
       and item.usuario_id = (select auth.uid())
  )
)
with check (
  exists (
    select 1 from public.cofre_itens item
     where item.id = cofre_envelopes.item_id
       and item.usuario_id = (select auth.uid())
  )
);

revoke all on public.cofre_identidades from anon;
revoke all on public.cofre_guardas from anon;
revoke all on public.cofre_itens from anon;
revoke all on public.cofre_envelopes from anon;

grant select, insert, update, delete on public.cofre_identidades to authenticated;
grant select, insert, update, delete on public.cofre_guardas to authenticated;
grant select, insert, update, delete on public.cofre_itens to authenticated;
grant select, insert, update, delete on public.cofre_envelopes to authenticated;

commit;
