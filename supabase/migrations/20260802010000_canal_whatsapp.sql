-- O canal de conversa do agente unico no WhatsApp.
--
-- A ponte local ja entregava os resumos da Casa e nunca trazia nada de volta.
-- Este arquivo abre o caminho de entrada — e ele e **aditivo**: nenhuma tabela
-- existente e alterada, nenhuma coluna some, e a caixa da Casa continua exatamente
-- onde estava. Broadcast agendado para o grupo e conversa reativa 1:1 sao coisas
-- diferentes; misturar as duas agora custaria mais do que separa-las depois.
--
-- **A fronteira.** A ponte enxerga tres coisas, e nada alem: a fila de entrada
-- (por onde ela empurra o que chegou), a caixa de saida (de onde ela tira o que
-- entregar) e a confirmacao. Ela nao le perfil, nao le documento, nao le
-- movimentacao. Tudo passa por funcoes `security definer` com colunas fixas.
--
-- **A identidade.** A chave da ponte identifica um processo local, nunca uma
-- pessoa. Quem diz de quem e uma mensagem e o numero de telefone, e um numero so
-- vale depois de pareado a partir de uma sessao web autenticada — e o pareamento
-- prova as duas pontas: quem tem a sessao e quem tem o aparelho.

begin;

-- ------------------------------------------------------------- a credencial
--
-- Mesmo desenho de `pontes_whatsapp_casa`: a chave bruta nunca entra no banco,
-- so o SHA-256 e um prefixo para a pessoa reconhecer qual e.
--
-- E uma credencial **separada** da chave da Casa, de proposito: aquela le resumo
-- de faxina, esta alcanca dinheiro e documentos. Revogar uma nao pode obrigar a
-- revogar a outra, e a mais perigosa precisa poder ser queimada sozinha.
create table if not exists public.pontes_whatsapp (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  rotulo text not null default 'Ponte local'
    check (char_length(rotulo) between 1 and 60),
  chave_hash text not null unique check (chave_hash ~ '^[0-9a-f]{64}$'),
  prefixo text not null check (char_length(prefixo) between 8 and 24),
  criada_em timestamptz not null default now(),
  revogada_em timestamptz,
  -- Quando a ponte falou pela ultima vez. E a diferenca, na tela, entre "no ar"
  -- e "o computador de casa desligou".
  ultima_vista_em timestamptz
);

create unique index if not exists pontes_whatsapp_ativa_idx
  on public.pontes_whatsapp (usuario_id) where revogada_em is null;

alter table public.pontes_whatsapp enable row level security;
alter table public.pontes_whatsapp force row level security;
revoke all on public.pontes_whatsapp from anon, authenticated;

-- -------------------------------------------------------------- a identidade
--
-- De quem e este numero. `ponte_id` e a contencao: uma chave vazada nao alcanca
-- quem pareou noutra ponte.
create table if not exists public.identidades_whatsapp (
  id uuid primary key default gen_random_uuid(),
  ponte_id uuid not null references public.pontes_whatsapp(id) on delete cascade,
  usuario_id uuid not null references auth.users(id) on delete cascade,
  -- E.164 sem o '+'. Validacao de forma, nao de existencia.
  telefone text not null check (telefone ~ '^[1-9][0-9]{7,14}$'),
  -- Coluna gerada para o backend nunca fatiar a string na mao ao mostrar
  -- "+55 11 ....-8888". O numero inteiro nunca sai em log nem em resposta.
  ultimos_digitos text generated always as (right(telefone, 4)) stored,
  nome_no_whatsapp text
    check (nome_no_whatsapp is null or char_length(nome_no_whatsapp) between 1 and 80),
  pareada_em timestamptz not null default now(),
  revogada_em timestamptz,
  ultima_mensagem_em timestamptz
);

create unique index if not exists identidades_whatsapp_ativa_idx
  on public.identidades_whatsapp (ponte_id, telefone) where revogada_em is null;
create index if not exists identidades_whatsapp_usuario_idx
  on public.identidades_whatsapp (usuario_id, pareada_em desc);

alter table public.identidades_whatsapp enable row level security;
alter table public.identidades_whatsapp force row level security;
revoke all on public.identidades_whatsapp from anon, authenticated;

-- ------------------------------------------------------------- o pareamento
--
-- O codigo tambem vai hasheado: e uma credencial de vida curta, e uma copia do
-- banco nao pode entregar um pareamento pendente.
create table if not exists public.pareamentos_whatsapp (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  ponte_id uuid not null references public.pontes_whatsapp(id) on delete cascade,
  codigo_hash text not null unique check (codigo_hash ~ '^[0-9a-f]{64}$'),
  criado_em timestamptz not null default now(),
  expira_em timestamptz not null,
  usado_em timestamptz,
  telefone_usado text
);

create index if not exists pareamentos_whatsapp_abertos_idx
  on public.pareamentos_whatsapp (ponte_id, expira_em) where usado_em is null;

alter table public.pareamentos_whatsapp enable row level security;
alter table public.pareamentos_whatsapp force row level security;
revoke all on public.pareamentos_whatsapp from anon, authenticated;

-- --------------------------------------------------------- a fila de entrada
--
-- O indice unico em (ponte_id, wa_id) e a idempotencia **de verdade** — nao uma
-- checagem em Python que perde a corrida. O WhatsApp reentrega, a ponte
-- reinicia, e sem isto "gastei 40 no posto" viraria duas capturas.
create table if not exists public.recebidas_whatsapp (
  id uuid primary key default gen_random_uuid(),
  ponte_id uuid not null references public.pontes_whatsapp(id) on delete cascade,
  wa_id text not null check (char_length(wa_id) between 1 and 120),
  telefone text not null check (telefone ~ '^[1-9][0-9]{7,14}$'),
  identidade_id uuid references public.identidades_whatsapp(id) on delete set null,
  texto text not null check (char_length(texto) between 1 and 4000),
  status text not null default 'recebida'
    check (status in ('recebida', 'processando', 'respondida', 'ignorada', 'falha')),
  motivo text check (motivo is null or char_length(motivo) <= 200),
  tentativas integer not null default 0,
  recebida_em timestamptz not null default now(),
  processada_em timestamptz
);

create unique index if not exists recebidas_whatsapp_wa_idx
  on public.recebidas_whatsapp (ponte_id, wa_id);
-- A varredura do pulso: o que ficou preso quando o processo morreu no meio.
create index if not exists recebidas_whatsapp_presas_idx
  on public.recebidas_whatsapp (recebida_em)
  where status in ('recebida', 'processando');
create index if not exists recebidas_whatsapp_limite_idx
  on public.recebidas_whatsapp (identidade_id, recebida_em desc);

alter table public.recebidas_whatsapp enable row level security;
alter table public.recebidas_whatsapp force row level security;
revoke all on public.recebidas_whatsapp from anon, authenticated;

-- ---------------------------------------------------------- a caixa de saida
create table if not exists public.caixa_whatsapp (
  id uuid primary key default gen_random_uuid(),
  ponte_id uuid not null references public.pontes_whatsapp(id) on delete cascade,
  identidade_id uuid not null
    references public.identidades_whatsapp(id) on delete cascade,
  -- A mensagem que esta resposta responde. Com o indice unico abaixo, e o que
  -- garante "uma pergunta, uma resposta" mesmo se o processamento rodar duas
  -- vezes: a segunda tentativa esbarra no banco, e nao numa trava em memoria
  -- (que nao atravessaria dois workers).
  responde_a uuid references public.recebidas_whatsapp(id) on delete set null,
  telefone text not null check (telefone ~ '^[1-9][0-9]{7,14}$'),
  mensagem text not null check (char_length(mensagem) between 1 and 4096),
  status text not null default 'pendente'
    check (status in ('pendente', 'entregue', 'descartada')),
  tentativas integer not null default 0,
  erro text check (erro is null or char_length(erro) <= 500),
  criada_em timestamptz not null default now(),
  entregue_em timestamptz
);

create unique index if not exists caixa_whatsapp_resposta_idx
  on public.caixa_whatsapp (responde_a) where responde_a is not null;
create index if not exists caixa_whatsapp_pendentes_idx
  on public.caixa_whatsapp (ponte_id, criada_em, id) where status = 'pendente';

alter table public.caixa_whatsapp enable row level security;
alter table public.caixa_whatsapp force row level security;
revoke all on public.caixa_whatsapp from anon, authenticated;

-- ---------------------------------------------------------------- os anexos
--
-- Separados da mensagem porque um PDF em base64 na propria linha pesaria a
-- leitura que a ponte faz a cada poll.
--
-- O tradeoff, dito em voz alta: base64 no banco e o que mantem a ponte com uma
-- porta so — ela nao ganha acesso ao Storage nem precisa saber assinar URL. E a
-- mesma escolha ja feita em `mensagens_whatsapp_casa.imagem_base64`, e ela custa
-- banco. Se o volume incomodar, a alternativa e dar leitura do Storage a ponte —
-- e ai ela deixa de ser burra.
create table if not exists public.anexos_caixa_whatsapp (
  id uuid primary key default gen_random_uuid(),
  mensagem_id uuid not null references public.caixa_whatsapp(id) on delete cascade,
  ordem smallint not null default 0,
  nome text not null check (char_length(nome) between 1 and 160),
  mime text not null check (char_length(mime) between 3 and 100),
  -- 16 MB em bytes -> ~21,8 MB em base64.
  conteudo_base64 text not null check (char_length(conteudo_base64) <= 22000000),
  criado_em timestamptz not null default now()
);

create index if not exists anexos_caixa_whatsapp_mensagem_idx
  on public.anexos_caixa_whatsapp (mensagem_id, ordem);

alter table public.anexos_caixa_whatsapp enable row level security;
alter table public.anexos_caixa_whatsapp force row level security;
revoke all on public.anexos_caixa_whatsapp from anon, authenticated;

-- ------------------------------------------------------------- a conversa
--
-- Sem `escopo_atual`: quem escolhe a area e o agente unico, a cada mensagem. No
-- WhatsApp nao ha tela, entao nao ha "onde a pessoa esta".
create table if not exists public.conversas_whatsapp (
  id uuid primary key default gen_random_uuid(),
  identidade_id uuid not null unique
    references public.identidades_whatsapp(id) on delete cascade,
  -- O `Assunto` do agente, serializado. E literalmente RespostaGlobal.assunto.
  assunto jsonb,
  atualizada_em timestamptz not null default now()
);

alter table public.conversas_whatsapp enable row level security;
alter table public.conversas_whatsapp force row level security;
revoke all on public.conversas_whatsapp from anon, authenticated;

create table if not exists public.mensagens_conversa_whatsapp (
  id uuid primary key default gen_random_uuid(),
  conversa_id uuid not null
    references public.conversas_whatsapp(id) on delete cascade,
  autor text not null check (autor in ('usuario', 'assistente')),
  texto text not null check (char_length(texto) between 1 and 4000),
  criada_em timestamptz not null default now()
);

create index if not exists mensagens_conversa_whatsapp_fio_idx
  on public.mensagens_conversa_whatsapp (conversa_id, criada_em desc);

alter table public.mensagens_conversa_whatsapp enable row level security;
alter table public.mensagens_conversa_whatsapp force row level security;
revoke all on public.mensagens_conversa_whatsapp from anon, authenticated;

-- --------------------------------------------------------------- a credencial
--
-- Duas funcoes da ponte precisam da mesma pergunta respondida — "de quem e esta
-- chave?" — e ela e a unica fronteira de seguranca deste arquivo. Fica escrita
-- uma vez, como ja e no arquivo da Casa.
create or replace function public.ponte_da_chave_whatsapp(p_chave text)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_ponte_id uuid;
begin
  if p_chave is null
    or left(p_chave, 4) <> 'wpp_'
    or char_length(p_chave) < 36
  then
    raise insufficient_privilege using message =
      'Chave da ponte inválida ou revogada.';
  end if;

  select ponte.id
    into v_ponte_id
    from public.pontes_whatsapp as ponte
   where ponte.chave_hash =
         pg_catalog.encode(extensions.digest(p_chave, 'sha256'), 'hex')
     and ponte.revogada_em is null
   limit 1;

  if v_ponte_id is null then
    raise insufficient_privilege using message =
      'Chave da ponte inválida ou revogada.';
  end if;

  return v_ponte_id;
end;
$$;

revoke all on function public.ponte_da_chave_whatsapp(text)
  from public, anon, authenticated;

-- ------------------------------------------------------------------ a leitura
--
-- Mesma forma da caixa da Casa, com duas diferencas: aqui a resposta tem
-- destinatario (o `telefone`), e os anexos vem agregados da tabela filha.
create or replace function public.ler_caixa_whatsapp(
  p_chave text,
  p_depois_de timestamptz,
  p_depois_de_id uuid default null,
  p_limite integer default 50
)
returns table (
  id uuid,
  telefone text,
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

-- --------------------------------------------------------- estado da entrega
--
-- Sucesso encerra a linha; falha conta a tentativa e guarda o motivo, e a
-- mensagem e reoferecida na leitura seguinte. Na quinta ela e descartada — uma
-- resposta envenenada nao pode segurar a fila inteira atras dela.
create or replace function public.confirmar_caixa_whatsapp(
  p_chave text,
  p_id uuid,
  p_entregue boolean,
  p_erro text default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ponte_id uuid;
  v_status text;
begin
  v_ponte_id := public.ponte_da_chave_whatsapp(p_chave);

  if p_entregue then
    update public.caixa_whatsapp as fila
       set status = 'entregue',
           entregue_em = now(),
           erro = null
     where fila.id = p_id
       and fila.ponte_id = v_ponte_id
       and fila.status = 'pendente'
    returning fila.status into v_status;

    return coalesce(v_status, 'desconhecida');
  end if;

  update public.caixa_whatsapp as fila
     set tentativas = fila.tentativas + 1,
         erro = left(coalesce(p_erro, 'falha sem descricao'), 500),
         status = case
           when fila.tentativas + 1 >= 5 then 'descartada'
           else fila.status
         end
   where fila.id = p_id
     and fila.ponte_id = v_ponte_id
     and fila.status = 'pendente'
  returning fila.status into v_status;

  return coalesce(v_status, 'desconhecida');
end;
$$;

revoke all on function public.confirmar_caixa_whatsapp(text, uuid, boolean, text)
  from public, authenticated;
grant execute on function public.confirmar_caixa_whatsapp(text, uuid, boolean, text)
  to anon;

commit;
