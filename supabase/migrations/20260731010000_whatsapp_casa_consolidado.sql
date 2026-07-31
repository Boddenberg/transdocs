-- O WhatsApp da Casa deixa de ser um log e vira acompanhamento.
--
-- Antes, cada atividade marcada virava uma mensagem. Dez tarefas numa manhã de
-- sábado viravam dez avisos, e a conversa ficava ilegível justamente no dia em
-- que mais se cuidou da casa. Agora existem quatro mensagens, e nenhuma delas é
-- um registro solto:
--
--   bloco             — o que foi feito de enfiada, depois que a pessoa parou;
--   resumo_diario     — como foi o dia que fechou;
--   panorama_semanal  — a semana inteira;
--   panorama_mensal   — o mês inteiro.
--
-- **O que muda de responsabilidade.** O texto sai do SQL e volta para o Python,
-- porque agora ele é escrito pela IA a partir de números que o backend calcula —
-- e porque a mensagem leva junto uma imagem, que nenhuma função de banco sabe
-- desenhar. O que fica aqui é o que só o banco garante: que uma atividade
-- pertence a um bloco só, que um período gera uma mensagem só, e que a ponte
-- continua enxergando exclusivamente a caixa de saída.
--
-- **Quem bate o relógio.** Continua sendo a ponte, mas de outro jeito: em vez de
-- a leitura da caixa montar o panorama em SQL, a ponte passa a bater um pulso no
-- backend antes de ler. Ver `app/modulos/casa/aplicacao/whatsapp/despacho.py`.

begin;

-- ---------------------------------------------------------------- configuração
--
-- Uma linha por residência. Tudo aqui é ajustável pela tela da Casa; os
-- defaults são o combinado inicial do casal.
create table if not exists public.configuracoes_whatsapp_casa (
  vinculo_id uuid primary key
    references public.vinculos_casal(id) on delete cascade,
  fuso text not null default 'America/Sao_Paulo'
    check (char_length(fuso) between 3 and 64),

  -- Registros em sequência.
  bloco_ativo boolean not null default true,
  bloco_espera_minutos integer not null default 20
    check (bloco_espera_minutos between 1 and 240),
  bloco_minimo_atividades integer not null default 1
    check (bloco_minimo_atividades between 1 and 50),

  resumo_diario_ativo boolean not null default true,
  resumo_diario_hora time not null default '08:00',

  panorama_semanal_ativo boolean not null default true,
  -- 1 = segunda ... 7 = domingo (ISO). O panorama cobre a semana fechada
  -- imediatamente anterior ao dia de envio.
  panorama_semanal_dia integer not null default 1
    check (panorama_semanal_dia between 1 and 7),
  panorama_semanal_hora time not null default '09:00',

  panorama_mensal_ativo boolean not null default true,
  -- Até 28 para o mês de fevereiro não engolir o envio.
  panorama_mensal_dia integer not null default 1
    check (panorama_mensal_dia between 1 and 28),
  panorama_mensal_hora time not null default '09:00',

  enviar_imagem boolean not null default true,

  -- P, M e G não são um segundo sistema de pontos: são faixas de leitura sobre
  -- a pontuação que a atividade já tem. Uma tarefa até `limite_pequena` pontos é
  -- P, até `limite_media` é M, acima disso é G.
  limite_pequena numeric(6, 2) not null default 2
    check (limite_pequena > 0),
  limite_media numeric(6, 2) not null default 4
    check (limite_media > 0),

  atualizada_em timestamptz not null default now(),

  constraint configuracoes_whatsapp_casa_faixas_check
    check (limite_pequena < limite_media)
);

alter table public.configuracoes_whatsapp_casa enable row level security;
alter table public.configuracoes_whatsapp_casa force row level security;
revoke all on public.configuracoes_whatsapp_casa from anon, authenticated;

-- --------------------------------------------------------------------- blocos
--
-- Um bloco é uma janela de espera: abre no primeiro registro, é empurrada por
-- cada novo registro e só fecha quando a pessoa para. O índice parcial garante
-- **um bloco aberto por residência** — é ele que impede duas mensagens partindo
-- a mesma faxina ao meio.
create table if not exists public.blocos_whatsapp_casa (
  id uuid primary key default gen_random_uuid(),
  vinculo_id uuid not null
    references public.vinculos_casal(id) on delete cascade,
  aberto_em timestamptz not null default now(),
  ultimo_em timestamptz not null default now(),
  fechado_em timestamptz
);

create unique index if not exists blocos_whatsapp_casa_aberto_idx
  on public.blocos_whatsapp_casa (vinculo_id)
  where fechado_em is null;

create index if not exists blocos_whatsapp_casa_espera_idx
  on public.blocos_whatsapp_casa (ultimo_em)
  where fechado_em is null;

alter table public.blocos_whatsapp_casa enable row level security;
alter table public.blocos_whatsapp_casa force row level security;
revoke all on public.blocos_whatsapp_casa from anon, authenticated;

-- Cada atividade em um bloco só, e a chave primária é quem garante isso: uma
-- atividade já contada não volta a aparecer em outra mensagem de bloco. Ela
-- continua entrando nos resumos diário, semanal e mensal — lá o recorte é o
-- período, não o agrupamento.
create table if not exists public.registros_bloco_whatsapp_casa (
  registro_id uuid primary key
    references public.registros_atividades_casa(id) on delete cascade,
  bloco_id uuid not null
    references public.blocos_whatsapp_casa(id) on delete cascade,
  vinculo_id uuid not null
    references public.vinculos_casal(id) on delete cascade,
  entrou_em timestamptz not null default now()
);

create index if not exists registros_bloco_whatsapp_casa_bloco_idx
  on public.registros_bloco_whatsapp_casa (bloco_id);

alter table public.registros_bloco_whatsapp_casa enable row level security;
alter table public.registros_bloco_whatsapp_casa force row level security;
revoke all on public.registros_bloco_whatsapp_casa from anon, authenticated;

-- ------------------------------------------------------------ caixa de saída
--
-- A caixa deixa de guardar avisos de registro e passa a guardar mensagens
-- consolidadas, cada uma com sua arte e seu estado de entrega.
--
-- As linhas do formato antigo saem: são avisos de atividade e panoramas diários
-- já entregues, escritos num vocabulário que não existe mais. O resumo do dia
-- volta a ser montado (agora em Python) para os últimos sete dias, então nada do
-- que importa se perde.
delete from public.mensagens_whatsapp_casa
 where tipo in ('atividade', 'panorama_diario');

drop trigger if exists remover_mensagem_whatsapp_casa_ao_excluir_registro
  on public.registros_atividades_casa;
drop function if exists public.remover_mensagem_whatsapp_casa_excluida();
drop function if exists public.enfileirar_panorama_diario_casa(uuid, text);
drop function if exists public.montar_panorama_diario_casa(uuid, date, text);
drop function if exists public.pontos_em_texto_casa(numeric);
drop function if exists public.mes_em_portugues_casa(date);

drop index if exists public.mensagens_whatsapp_casa_registro_idx;
drop index if exists public.mensagens_whatsapp_casa_panorama_idx;

alter table public.mensagens_whatsapp_casa
  drop constraint if exists mensagens_whatsapp_casa_origem_check;
alter table public.mensagens_whatsapp_casa
  drop constraint if exists mensagens_whatsapp_casa_tipo_check;

alter table public.mensagens_whatsapp_casa
  drop column if exists registro_id;

alter table public.mensagens_whatsapp_casa
  add column if not exists bloco_id uuid
    references public.blocos_whatsapp_casa(id) on delete cascade,
  -- A arte viaja com a mensagem. Guardar o PNG em base64 na própria linha
  -- mantém a ponte com uma porta só: ela continua pedindo mensagens e
  -- entregando o que veio, sem ganhar acesso ao Storage nem saber assinar URL.
  add column if not exists imagem_base64 text
    check (imagem_base64 is null or char_length(imagem_base64) <= 4000000),
  add column if not exists imagem_nome text
    check (imagem_nome is null or char_length(imagem_nome) between 1 and 120),
  add column if not exists status text not null default 'pendente',
  add column if not exists tentativas integer not null default 0,
  add column if not exists erro text,
  add column if not exists entregue_em timestamptz;

alter table public.mensagens_whatsapp_casa
  alter column tipo drop default;

alter table public.mensagens_whatsapp_casa
  add constraint mensagens_whatsapp_casa_tipo_check
  check (tipo in (
    'bloco',
    'resumo_diario',
    'panorama_semanal',
    'panorama_mensal',
    'demonstracao'
  ));

alter table public.mensagens_whatsapp_casa
  add constraint mensagens_whatsapp_casa_status_check
  check (status in ('pendente', 'entregue', 'descartada'));

-- Mensagem de período carrega a data que a identifica (o dia, a segunda-feira da
-- semana, o primeiro dia do mês); mensagem de bloco carrega o bloco. A
-- demonstração não é nem uma coisa nem outra e pode repetir à vontade.
alter table public.mensagens_whatsapp_casa
  add constraint mensagens_whatsapp_casa_origem_check
  check (
    (tipo = 'bloco' and bloco_id is not null and referencia is null)
    or (
      tipo in ('resumo_diario', 'panorama_semanal', 'panorama_mensal')
      and bloco_id is null
      and referencia is not null
    )
    or (tipo = 'demonstracao' and bloco_id is null and referencia is null)
  );

create unique index if not exists mensagens_whatsapp_casa_periodo_idx
  on public.mensagens_whatsapp_casa (vinculo_id, tipo, referencia)
  where referencia is not null;

create unique index if not exists mensagens_whatsapp_casa_bloco_idx
  on public.mensagens_whatsapp_casa (bloco_id)
  where bloco_id is not null;

create index if not exists mensagens_whatsapp_casa_pendentes_idx
  on public.mensagens_whatsapp_casa (vinculo_id, criada_em, id)
  where status = 'pendente';

-- Registro apagado sai do bloco enquanto o bloco ainda está aberto. Depois de
-- fechado, a mensagem já foi escrita: mexer nela seria reescrever o passado.
create or replace function public.soltar_registro_do_bloco_casa()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.excluida_em is null and new.excluida_em is not null then
    delete from public.registros_bloco_whatsapp_casa as elo
     using public.blocos_whatsapp_casa as bloco
     where elo.registro_id = new.id
       and bloco.id = elo.bloco_id
       and bloco.fechado_em is null;
  end if;
  return new;
end;
$$;

revoke all on function public.soltar_registro_do_bloco_casa()
  from public, anon, authenticated;

create trigger soltar_registro_do_bloco_ao_excluir
after update of excluida_em on public.registros_atividades_casa
for each row execute function public.soltar_registro_do_bloco_casa();

-- --------------------------------------------------------------- a credencial
--
-- Duas funções da ponte precisam da mesma pergunta respondida — "de quem é esta
-- chave?" — e ela é a única fronteira de segurança deste arquivo. Fica escrita
-- uma vez.
create or replace function public.vinculo_da_ponte_whatsapp_casa(p_chave text)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_vinculo_id uuid;
begin
  if p_chave is null
    or left(p_chave, 9) <> 'casa_wpp_'
    or char_length(p_chave) < 40
  then
    raise insufficient_privilege using message =
      'Chave da ponte inválida ou revogada.';
  end if;

  select ponte.vinculo_id
    into v_vinculo_id
    from public.pontes_whatsapp_casa as ponte
   where ponte.chave_hash =
         pg_catalog.encode(extensions.digest(p_chave, 'sha256'), 'hex')
     and ponte.revogada_em is null
   limit 1;

  if v_vinculo_id is null then
    raise insufficient_privilege using message =
      'Chave da ponte inválida ou revogada.';
  end if;

  return v_vinculo_id;
end;
$$;

revoke all on function public.vinculo_da_ponte_whatsapp_casa(text)
  from public, anon, authenticated;

-- ---------------------------------------------------------------- a leitura
--
-- Mesma porta de sempre, com dois campos a mais: a arte e o nome do arquivo. O
-- que sumiu foi a montagem do panorama em SQL — quem fecha períodos agora é o
-- pulso do backend, e a ponte volta a fazer só o que sabe: pedir e entregar.
drop function if exists public.ler_mensagens_whatsapp_casa(
  text, timestamptz, uuid, integer
);

create function public.ler_mensagens_whatsapp_casa(
  p_chave text,
  p_depois_de timestamptz,
  p_depois_de_id uuid default null,
  p_limite integer default 100
)
returns table (
  id uuid,
  mensagem text,
  imagem_base64 text,
  imagem_nome text,
  criada_em timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_vinculo_id uuid;
begin
  v_vinculo_id := public.vinculo_da_ponte_whatsapp_casa(p_chave);

  return query
  select fila.id,
         fila.mensagem,
         fila.imagem_base64,
         fila.imagem_nome,
         fila.criada_em
    from public.mensagens_whatsapp_casa as fila
   where fila.vinculo_id = v_vinculo_id
     and fila.status = 'pendente'
     and (
       fila.criada_em > p_depois_de
       or (
         fila.criada_em = p_depois_de
         and (p_depois_de_id is null or fila.id > p_depois_de_id)
       )
     )
   order by fila.criada_em, fila.id
   limit least(greatest(coalesce(p_limite, 100), 1), 500);
end;
$$;

revoke all on function public.ler_mensagens_whatsapp_casa(
  text, timestamptz, uuid, integer
) from public, authenticated;
grant execute on function public.ler_mensagens_whatsapp_casa(
  text, timestamptz, uuid, integer
) to anon;

-- ------------------------------------------------------- estado da entrega
--
-- A ponte volta a falar depois de entregar. Sucesso encerra a linha; falha
-- conta a tentativa e guarda o motivo, e a mensagem é reoferecida na leitura
-- seguinte. Depois de `TENTATIVAS_MAXIMAS` ela é descartada — uma mensagem
-- envenenada não pode segurar a fila inteira atrás dela.
create or replace function public.confirmar_mensagem_whatsapp_casa(
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
  v_vinculo_id uuid;
  v_tentativas integer;
  v_status text;
begin
  v_vinculo_id := public.vinculo_da_ponte_whatsapp_casa(p_chave);

  if p_entregue then
    update public.mensagens_whatsapp_casa as fila
       set status = 'entregue',
           entregue_em = now(),
           erro = null
     where fila.id = p_id
       and fila.vinculo_id = v_vinculo_id
       and fila.status = 'pendente'
    returning fila.status into v_status;

    return coalesce(v_status, 'desconhecida');
  end if;

  update public.mensagens_whatsapp_casa as fila
     set tentativas = fila.tentativas + 1,
         erro = left(coalesce(p_erro, 'falha sem descricao'), 500),
         status = case
           when fila.tentativas + 1 >= 5 then 'descartada'
           else fila.status
         end
   where fila.id = p_id
     and fila.vinculo_id = v_vinculo_id
     and fila.status = 'pendente'
  returning fila.status, fila.tentativas into v_status, v_tentativas;

  return coalesce(v_status, 'desconhecida');
end;
$$;

revoke all on function public.confirmar_mensagem_whatsapp_casa(
  text, uuid, boolean, text
) from public, authenticated;
grant execute on function public.confirmar_mensagem_whatsapp_casa(
  text, uuid, boolean, text
) to anon;

commit;
