begin;

-- Cada arquivo existente nasce como um documento logico independente. Somente
-- uma confirmacao curta junta dois registros como versoes do mesmo documento.
alter table public.documentos_financeiros
  add column if not exists documento_logico_id uuid not null default gen_random_uuid(),
  add column if not exists versao_numero integer not null default 1
    check (versao_numero >= 1),
  add column if not exists versao_atual boolean not null default true;

create index if not exists documentos_logicos_idx
  on public.documentos_financeiros (
    usuario_id, documento_logico_id, versao_numero desc
  );
create unique index if not exists documentos_logico_vigente_unico_idx
  on public.documentos_financeiros (usuario_id, documento_logico_id)
  where versao_atual;

-- O hash unico passa a considerar apenas a versao vigente. Uma versao
-- arquivada pode voltar como novo upload sem sobrescrever o original antigo.
drop index if exists public.documentos_hash_ativo_unico_idx;
create unique index documentos_hash_ativo_unico_idx
  on public.documentos_financeiros (usuario_id, hash_sha256)
  where excluido_em is null and versao_atual;

create table if not exists public.substituicoes_documentos (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  documento_novo_id uuid not null
    references public.documentos_financeiros(id) on delete cascade,
  documento_anterior_id uuid not null
    references public.documentos_financeiros(id) on delete cascade,
  confianca numeric(5,4) not null check (confianca between 0 and 1),
  comparacao jsonb not null default '[]'::jsonb,
  status text not null default 'pendente'
    check (status in ('pendente', 'aceita', 'recusada')),
  respondido_em timestamptz,
  criado_em timestamptz not null default now(),
  check (documento_novo_id <> documento_anterior_id)
);

create unique index if not exists substituicao_pendente_por_documento_idx
  on public.substituicoes_documentos (documento_novo_id)
  where status = 'pendente';
create index if not exists substituicoes_documentos_usuario_idx
  on public.substituicoes_documentos (usuario_id, status, criado_em desc);

alter table public.substituicoes_documentos enable row level security;
alter table public.substituicoes_documentos force row level security;
drop policy if exists substituicoes_do_proprio_usuario
  on public.substituicoes_documentos;
create policy substituicoes_do_proprio_usuario
  on public.substituicoes_documentos
  using (usuario_id = auth.uid())
  with check (usuario_id = auth.uid());
revoke all on public.substituicoes_documentos from anon;
grant select, insert, update, delete
  on public.substituicoes_documentos to authenticated;

create or replace function public.responder_substituicao_documento(
  p_usuario uuid,
  p_proposta uuid,
  p_aceita boolean
)
returns table (
  status text,
  documento_novo_id uuid,
  documento_anterior_id uuid
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  proposta public.substituicoes_documentos%rowtype;
  anterior public.documentos_financeiros%rowtype;
  nova public.documentos_financeiros%rowtype;
  proxima_versao integer;
begin
  -- Chamadas do backend usam a service role (auth.uid nulo). Se a funcao for
  -- chamada diretamente por um cliente autenticado, ele so pode agir sobre si.
  if auth.uid() is not null and auth.uid() <> p_usuario then
    raise exception 'usuario nao autorizado';
  end if;

  select * into proposta
  from public.substituicoes_documentos
  where id = p_proposta
    and usuario_id = p_usuario
  for update;

  if proposta.id is null then
    raise exception 'proposta de substituicao nao encontrada';
  end if;
  if proposta.status <> 'pendente' then
    raise exception 'proposta de substituicao ja respondida';
  end if;

  select * into anterior
  from public.documentos_financeiros
  where id = proposta.documento_anterior_id
    and usuario_id = p_usuario
    and excluido_em is null
    and versao_atual
  for update;
  select * into nova
  from public.documentos_financeiros
  where id = proposta.documento_novo_id
    and usuario_id = p_usuario
    and excluido_em is null
    and versao_atual
  for update;

  if anterior.id is null or nova.id is null then
    raise exception 'uma das versoes nao esta mais disponivel';
  end if;

  if p_aceita then
    select coalesce(max(documento.versao_numero), 0) + 1
      into proxima_versao
    from public.documentos_financeiros documento
    where documento.usuario_id = p_usuario
      and documento.documento_logico_id = anterior.documento_logico_id;

    update public.documentos_financeiros
    set versao_atual = false
    where usuario_id = p_usuario
      and documento_logico_id = anterior.documento_logico_id
      and versao_atual;

    update public.documentos_financeiros
    set documento_logico_id = anterior.documento_logico_id,
        versao_numero = proxima_versao,
        versao_atual = true
    where id = nova.id
      and usuario_id = p_usuario;

    update public.notificacoes notificacao
    set status = 'arquivada'
    where notificacao.entidade_tipo = 'evento_documento'
      and notificacao.entidade_id in (
        select evento.id::text
        from public.eventos_documento evento
        where evento.documento_id = anterior.id
      );

    insert into public.documentos_historico (
      usuario_id, documento_id, campo, valor_anterior, valor_novo, origem
    )
    values
      (
        p_usuario, anterior.id, 'substituicao',
        coalesce(anterior.nome_exibicao, anterior.nome_original),
        coalesce(nova.nome_exibicao, nova.nome_original),
        'pessoa'
      ),
      (
        p_usuario, nova.id, 'substituicao',
        coalesce(anterior.nome_exibicao, anterior.nome_original),
        coalesce(nova.nome_exibicao, nova.nome_original),
        'pessoa'
      );

    -- Duas novidades podem ter apontado para a mesma versao anterior. Quando
    -- uma e confirmada, as demais ficam obsoletas e nao voltam como perguntas
    -- impossiveis na proxima abertura.
    update public.substituicoes_documentos substituicao
    set status = 'recusada',
        respondido_em = now()
    where substituicao.usuario_id = p_usuario
      and substituicao.id <> proposta.id
      and substituicao.status = 'pendente'
      and (
        substituicao.documento_novo_id in (anterior.id, nova.id)
        or substituicao.documento_anterior_id in (anterior.id, nova.id)
      );
  end if;

  update public.substituicoes_documentos
  set status = case when p_aceita then 'aceita' else 'recusada' end,
      respondido_em = now()
  where id = proposta.id;

  return query
  select
    case when p_aceita then 'aceita' else 'recusada' end,
    proposta.documento_novo_id,
    proposta.documento_anterior_id;
end;
$$;

revoke all on function public.responder_substituicao_documento(uuid, uuid, boolean)
  from public;
grant execute
  on function public.responder_substituicao_documento(uuid, uuid, boolean)
  to authenticated;

-- Filas atrasadas nao podem recolocar uma versao arquivada no contexto da IA.
create or replace function public.impedir_chunk_de_documento_excluido()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if exists (
    select 1 from public.documentos_financeiros documento
    where documento.id = new.documento_id
      and (
        documento.excluido_em is not null
        or not documento.versao_atual
      )
  ) then
    raise exception 'documento oculto nao pode receber chunks';
  end if;
  return new;
end;
$$;

-- Apenas a versao vigente cria novos avisos.
create or replace function public.sincronizar_notificacoes_eventos_documento(
  p_usuario uuid,
  p_hoje date default current_date
)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  evento record;
  marco integer;
  dias integer;
  inseridos integer := 0;
begin
  if p_usuario is null then
    return 0;
  end if;

  for evento in
    select e.*
    from public.eventos_documento e
    join public.documentos_financeiros documento
      on documento.id = e.documento_id
     and documento.excluido_em is null
     and documento.versao_atual
    where e.usuario_id = p_usuario
      and e.estado = 'ativo'
      and (
        (e.adiado_ate is not null and e.adiado_ate <= p_hoje)
        or (e.adiado_ate is null and e.data <= p_hoje + 60)
      )
    order by coalesce(e.adiado_ate, e.data), e.id
  loop
    if evento.adiado_ate is not null then
      marco := 0;
    else
      dias := evento.data - p_hoje;
      marco := case
        when dias <= 1 then 1
        when dias <= 7 then 7
        when dias <= 30 then 30
        else 60
      end;
    end if;

    insert into public.eventos_documento_avisos (evento_id, marco_dias)
    values (evento.id, marco)
    on conflict do nothing;
    if found then
      insert into public.notificacoes (
        usuario_id, tipo, titulo, mensagem, entidade_tipo, entidade_id
      )
      values (
        evento.usuario_id,
        'documento_prazo',
        case
          when marco = 0 then 'Lembrete do documento'
          when evento.data < p_hoje then 'Prazo do documento passou'
          when marco = 1 then 'Prazo do documento e amanha'
          else 'Documento pede atencao'
        end,
        evento.titulo || ' · ' ||
          case
            when evento.data < p_hoje
              then 'venceu em ' || to_char(evento.data, 'DD/MM/YYYY')
            when evento.data = p_hoje
              then 'e para hoje'
            else 'em ' || to_char(evento.data, 'DD/MM/YYYY')
          end || '.',
        'evento_documento',
        evento.id
      );
      inseridos := inseridos + 1;
      if marco = 0 then
        update public.eventos_documento
        set adiado_ate = null
        where id = evento.id;
      end if;
    end if;
  end loop;
  return inseridos;
end;
$$;

commit;
