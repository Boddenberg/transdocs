-- O panorama do dia na caixa de saída da Casa.
--
-- Toda atividade marcada já vira um aviso na hora. Faltava o fechamento: quando
-- vira o dia, o casal recebe o que foi feito ontem e como está o placar do mês.
--
-- **Por que este texto é montado aqui e não no backend.** O aviso de atividade é
-- escrito em Python porque existe um pedido HTTP acontecendo naquele instante. O
-- panorama não tem esse instante: ele acontece à meia-noite, e o backend não tem
-- agendador. Quem passa por aqui de tempos em tempos é a ponte, perguntando "tem
-- mensagem nova?" — então é essa pergunta que enfileira o panorama pendente,
-- antes de responder. A ponte continua sem saber o que é um registro da Casa:
-- pede mensagens e entrega texto, como sempre. O contrato que importa segue de
-- pé — quem entrega não interpreta.
--
-- O índice único por dia é a garantia de que o panorama de uma data entra uma
-- vez só, por mais vezes que a ponte pergunte.

begin;

-- A fila deixa de ser só de atividades: um panorama não tem registro de origem.
alter table public.mensagens_whatsapp_casa
  alter column registro_id drop not null;

alter table public.mensagens_whatsapp_casa
  add column if not exists tipo text not null default 'atividade'
    check (tipo in ('atividade', 'panorama_diario')),
  add column if not exists referencia date;

alter table public.mensagens_whatsapp_casa
  drop constraint if exists mensagens_whatsapp_casa_registro_id_key;

create unique index if not exists mensagens_whatsapp_casa_registro_idx
  on public.mensagens_whatsapp_casa (registro_id)
  where registro_id is not null;

create unique index if not exists mensagens_whatsapp_casa_panorama_idx
  on public.mensagens_whatsapp_casa (vinculo_id, referencia)
  where tipo = 'panorama_diario';

alter table public.mensagens_whatsapp_casa
  drop constraint if exists mensagens_whatsapp_casa_origem_check;
alter table public.mensagens_whatsapp_casa
  add constraint mensagens_whatsapp_casa_origem_check
  check (
    (tipo = 'atividade' and registro_id is not null and referencia is null)
    or (tipo = 'panorama_diario' and registro_id is null and referencia is not null)
  );

-- Número em português, do jeito que o resto do app escreve: 2,5 e não 2.50.
create or replace function public.pontos_em_texto_casa(p_valor numeric)
returns text
language sql
immutable
set search_path = ''
as $$
  select replace(trim(to_char(coalesce(p_valor, 0), 'FM999999990.99')), '.', ',');
$$;

revoke all on function public.pontos_em_texto_casa(numeric)
  from public, anon, authenticated;

-- `to_char(..., 'TMMonth')` depende do `lc_time` do servidor, que aqui é inglês.
-- O mês vai escrito à mão para a mensagem não chegar dizendo "July".
create or replace function public.mes_em_portugues_casa(p_dia date)
returns text
language sql
immutable
set search_path = ''
as $$
  select (array[
    'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
    'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'
  ])[extract(month from p_dia)::integer];
$$;

revoke all on function public.mes_em_portugues_casa(date)
  from public, anon, authenticated;

-- O texto do panorama.
--
-- Duas perguntas, nesta ordem: o que aconteceu no dia que fechou, e como está o
-- mês até agora. O placar usa `participantes_registros_atividades_casa`, que é
-- onde a divisão de uma atividade feita a quatro mãos já está resolvida — somar
-- `pontuacao_total` por autor daria a uma pessoa os pontos das duas.
--
-- Devolve `null` no dia em que ninguém registrou nada: silêncio é melhor
-- resposta que um panorama vazio todo santo dia.
create or replace function public.montar_panorama_diario_casa(
  p_vinculo_id uuid,
  p_dia date,
  p_fuso text default 'America/Sao_Paulo'
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_linhas text;
  v_total_dia numeric;
  v_quantidade integer;
  v_placar text;
  v_mes_inicio date := date_trunc('month', p_dia::timestamp)::date;
begin
  select coalesce(sum(registro.pontuacao_total), 0), count(*)
    into v_total_dia, v_quantidade
    from public.registros_atividades_casa as registro
   where registro.vinculo_id = p_vinculo_id
     and registro.excluida_em is null
     and (registro.capturada_em at time zone p_fuso)::date = p_dia;

  if v_quantidade = 0 then
    return null;
  end if;

  select string_agg(linha.texto, E'\n' order by linha.momento)
    into v_linhas
    from (
      select min(registro.capturada_em) as momento,
             '• ' || registro.atividade_nome
               || coalesce(' (' || registro.ambiente_nome || ')', '')
               || ' — ' || coalesce(perfil.nome, 'Pessoa da casa')
               as texto
        from public.registros_atividades_casa as registro
        left join public.perfis as perfil
          on perfil.usuario_id = registro.usuario_id
       where registro.vinculo_id = p_vinculo_id
         and registro.excluida_em is null
         and (registro.capturada_em at time zone p_fuso)::date = p_dia
       group by registro.atividade_nome, registro.ambiente_nome, perfil.nome
    ) as linha;

  select string_agg(
           '• ' || placar.nome || ': '
             || public.pontos_em_texto_casa(placar.pontos) || ' pts',
           E'\n' order by placar.pontos desc
         )
    into v_placar
    from (
      select coalesce(perfil.nome, 'Pessoa da casa') as nome,
             sum(participacao.pontos) as pontos
        from public.participantes_registros_atividades_casa as participacao
        join public.registros_atividades_casa as registro
          on registro.id = participacao.registro_id
        left join public.perfis as perfil
          on perfil.usuario_id = participacao.usuario_id
       where participacao.vinculo_id = p_vinculo_id
         and registro.excluida_em is null
         and (registro.capturada_em at time zone p_fuso)::date
             between v_mes_inicio and p_dia
       group by coalesce(perfil.nome, 'Pessoa da casa')
    ) as placar;

  return concat_ws(
    E'\n',
    '🏠 *Panorama de ' || to_char(p_dia, 'DD/MM') || '*',
    v_quantidade::text
      || case when v_quantidade = 1 then ' atividade' else ' atividades' end
      || ' · ' || public.pontos_em_texto_casa(v_total_dia) || ' pts no dia',
    '',
    v_linhas,
    '',
    '📊 *Placar de ' || public.mes_em_portugues_casa(p_dia) || '*',
    v_placar
  );
end;
$$;

revoke all on function public.montar_panorama_diario_casa(uuid, date, text)
  from public, anon, authenticated;

-- Enfileira o que ainda falta, sem repetir o que já foi.
--
-- Olha para trás no máximo uma semana: a ponte pode ter passado dias desligada,
-- e o casal merece o resumo dos dias em que cuidou da casa — mas não merece
-- receber um mês inteiro de uma vez ao religar o computador.
create or replace function public.enfileirar_panorama_diario_casa(
  p_vinculo_id uuid,
  p_fuso text default 'America/Sao_Paulo'
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hoje date := (timezone(p_fuso, now()))::date;
  v_dia date;
  v_mensagem text;
  v_enfileirados integer := 0;
begin
  for v_dia in
    select dia::date
      from generate_series(v_hoje - 7, v_hoje - 1, interval '1 day') as dia
  loop
    if exists (
      select 1
        from public.mensagens_whatsapp_casa as fila
       where fila.vinculo_id = p_vinculo_id
         and fila.tipo = 'panorama_diario'
         and fila.referencia = v_dia
    ) then
      continue;
    end if;

    v_mensagem := public.montar_panorama_diario_casa(p_vinculo_id, v_dia, p_fuso);
    if v_mensagem is null then
      continue;
    end if;

    insert into public.mensagens_whatsapp_casa (vinculo_id, tipo, referencia, mensagem)
    values (p_vinculo_id, 'panorama_diario', v_dia, v_mensagem)
    on conflict do nothing;

    v_enfileirados := v_enfileirados + 1;
  end loop;

  return v_enfileirados;
end;
$$;

revoke all on function public.enfileirar_panorama_diario_casa(uuid, text)
  from public, anon, authenticated;

-- A leitura da ponte passa a fechar o dia antes de responder.
create or replace function public.ler_mensagens_whatsapp_casa(
  p_chave text,
  p_depois_de timestamptz,
  p_depois_de_id uuid default null,
  p_limite integer default 100
)
returns table (
  id uuid,
  mensagem text,
  criada_em timestamptz
)
language plpgsql
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

  -- O fechamento do dia entra na fila aqui, na única batida de relógio que esta
  -- casa tem. Falhar a compor o panorama não pode calar as mensagens comuns.
  begin
    perform public.enfileirar_panorama_diario_casa(v_vinculo_id);
  exception
    when others then
      null;
  end;

  return query
  select fila.id, fila.mensagem, fila.criada_em
    from public.mensagens_whatsapp_casa as fila
   where fila.vinculo_id = v_vinculo_id
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
  text,
  timestamptz,
  uuid,
  integer
) from public, authenticated;
grant execute on function public.ler_mensagens_whatsapp_casa(
  text,
  timestamptz,
  uuid,
  integer
) to anon;

commit;
