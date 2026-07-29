begin;

-- A exclusao agora tem duas fases. NULL preserva todo documento existente
-- exatamente como esta; preencher estas colunas apenas o esconde por 30 dias.
alter table public.documentos_financeiros
  add column if not exists excluido_em timestamptz,
  add column if not exists exclusao_definitiva_em timestamptz,
  add constraint documentos_exclusao_coerente_check check (
    (excluido_em is null and exclusao_definitiva_em is null)
    or (
      excluido_em is not null
      and exclusao_definitiva_em is not null
      and exclusao_definitiva_em >= excluido_em
    )
  );

create index if not exists documentos_lixeira_usuario_idx
  on public.documentos_financeiros (usuario_id, exclusao_definitiva_em)
  where excluido_em is not null;
create index if not exists documentos_ativos_usuario_idx
  on public.documentos_financeiros (usuario_id, criado_em desc)
  where excluido_em is null;

-- Reenviar o mesmo arquivo depois de manda-lo para a lixeira pode criar um
-- documento novo. O item da lixeira continua restauravel ate expirar.
alter table public.documentos_financeiros
  drop constraint if exists documentos_financeiros_usuario_id_hash_sha256_key;
create unique index if not exists documentos_hash_ativo_unico_idx
  on public.documentos_financeiros (usuario_id, hash_sha256)
  where excluido_em is null;

-- A trilha passa a incluir os gestos de confianca alem da organizacao.
alter table public.documentos_historico
  drop constraint if exists documentos_historico_campo_check;
alter table public.documentos_historico add constraint documentos_historico_campo_check
  check (campo in (
    'nome', 'pasta', 'categoria', 'download', 'compartilhamento',
    'substituicao', 'restauracao', 'exclusao'
  ));

alter table public.documentos_historico
  drop constraint if exists documentos_historico_origem_check;
alter table public.documentos_historico add constraint documentos_historico_origem_check
  check (origem in ('ia', 'pessoa', 'sistema'));

-- Mesmo que uma fila antiga termine depois do clique em Remover, ela nao pode
-- recolocar o arquivo excluido no contexto da IA.
create or replace function public.impedir_chunk_de_documento_excluido()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if exists (
    select 1 from public.documentos_financeiros documento
    where documento.id = new.documento_id
      and documento.excluido_em is not null
  ) then
    raise exception 'documento na lixeira nao pode receber chunks';
  end if;
  return new;
end;
$$;

drop trigger if exists documento_chunk_exige_documento_ativo
  on public.documento_chunks;
create trigger documento_chunk_exige_documento_ativo
before insert or update on public.documento_chunks
for each row execute function public.impedir_chunk_de_documento_excluido();

-- Alertas tambem deixam de enxergar imediatamente o que foi para a lixeira.
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
