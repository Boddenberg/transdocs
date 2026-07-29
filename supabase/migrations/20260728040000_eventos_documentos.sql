begin;

-- Cuidados que a propria leitura do documento descobre. A tabela e paralela
-- ao documento: nenhuma linha ou arquivo existente e regravado. `validade`
-- continua sendo a projecao compativel para clientes antigos.
create table if not exists public.eventos_documento (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  documento_id uuid not null
    references public.documentos_financeiros(id) on delete cascade,
  chave text not null check (char_length(chave) between 1 and 80),
  tipo text not null check (tipo in (
    'validade', 'renovacao', 'reajuste', 'garantia', 'parcela', 'obrigacao'
  )),
  titulo text not null check (char_length(titulo) between 1 and 100),
  descricao text check (
    descricao is null or char_length(descricao) between 1 and 300
  ),
  data date not null,
  recorrencia text not null default 'nenhuma'
    check (recorrencia in ('nenhuma', 'mensal', 'anual')),
  confianca numeric(3,2) not null default 0.80
    check (confianca between 0 and 1),
  estado text not null default 'ativo'
    check (estado in ('ativo', 'concluido', 'cancelado')),
  origem text not null default 'ia' check (origem in ('ia', 'pessoa', 'validade')),
  adiado_ate date,
  concluido_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (documento_id, chave)
);

create index if not exists eventos_documento_usuario_data_idx
  on public.eventos_documento (usuario_id, estado, data);
create index if not exists eventos_documento_documento_idx
  on public.eventos_documento (documento_id, data);

drop trigger if exists eventos_documento_atualizado_em
  on public.eventos_documento;
create trigger eventos_documento_atualizado_em
before update on public.eventos_documento
for each row execute function public.definir_atualizado_em();

alter table public.eventos_documento enable row level security;
alter table public.eventos_documento force row level security;

drop policy if exists eventos_documento_do_proprio_usuario
  on public.eventos_documento;
create policy eventos_documento_do_proprio_usuario
  on public.eventos_documento
for all to authenticated
using ((select auth.uid()) = usuario_id)
with check (
  (select auth.uid()) = usuario_id
  and exists (
    select 1
    from public.documentos_financeiros documento
    where documento.id = documento_id
      and documento.usuario_id = (select auth.uid())
  )
);

revoke all on public.eventos_documento from anon;
grant select, insert, update, delete on public.eventos_documento to authenticated;

-- Livro-caixa dos alertas ja emitidos. A chave composta impede que um restart,
-- duas instancias da API ou dois sinos abertos dupliquem o mesmo aviso.
create table if not exists public.eventos_documento_avisos (
  evento_id uuid not null
    references public.eventos_documento(id) on delete cascade,
  marco_dias integer not null check (marco_dias in (0, 1, 7, 30, 60)),
  criado_em timestamptz not null default now(),
  primary key (evento_id, marco_dias)
);

alter table public.eventos_documento_avisos enable row level security;
alter table public.eventos_documento_avisos force row level security;

drop policy if exists eventos_documento_avisos_do_proprio_usuario
  on public.eventos_documento_avisos;
create policy eventos_documento_avisos_do_proprio_usuario
  on public.eventos_documento_avisos
for select to authenticated
using (
  exists (
    select 1 from public.eventos_documento evento
    where evento.id = evento_id
      and evento.usuario_id = (select auth.uid())
  )
);

revoke all on public.eventos_documento_avisos from anon;
grant select on public.eventos_documento_avisos to authenticated;

-- O sino passa a entender um aviso de prazo sem ganhar uma acao complexa. Ao
-- clicar, a pessoa abre a ficha; resolver e adiar vivem junto do documento.
alter table public.notificacoes drop constraint if exists notificacoes_tipo_check;
alter table public.notificacoes add constraint notificacoes_tipo_check
  check (tipo in (
    'desejo_pendente', 'desejo_aceito', 'desejo_recusado',
    'divisao_pendente', 'divisao_aceita', 'divisao_recusada',
    'compartilhamento_pendente', 'compartilhamento_aceito', 'compartilhamento_recusado',
    'documento_pendente', 'documento_aceito', 'documento_recusado',
    'nota_consumo_pendente', 'nota_consumo_aceito', 'nota_consumo_recusado',
    'documento_prazo'
  ));

alter table public.notificacoes
  drop constraint if exists notificacoes_entidade_tipo_check;
alter table public.notificacoes add constraint notificacoes_entidade_tipo_check
  check (entidade_tipo is null or entidade_tipo in (
    'desejo_casal', 'divisao_casal', 'compartilhamento_casal',
    'documento_casal', 'nota_consumo_casal', 'evento_documento'
  ));

-- Chamado pela leitura do sino. Calcula apenas o proximo marco aplicavel:
-- quem volta ao app com 25 dias recebe "30 dias", nao quatro avisos atrasados.
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

revoke all on function public.sincronizar_notificacoes_eventos_documento(uuid, date)
  from public, anon, authenticated;
grant execute on function public.sincronizar_notificacoes_eventos_documento(uuid, date)
  to service_role;

commit;
