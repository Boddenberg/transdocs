begin;

-- Documentos do casal --------------------------------------------------------
--
-- Um documento continua pertencendo a quem o enviou, mas agora pode ser levado
-- ao espaco do casal — o financiamento que e "meu e do Victor", por exemplo.
-- O fluxo espelha o das compras compartilhadas: o dono propoe, o parceiro
-- recebe uma notificacao, consegue BAIXAR o arquivo para conferir e so entao
-- aceita. So depois do aceite o documento aparece para os dois.
--
-- `compartilhado_casal` marca o documento ja aceito no espaco do casal. NULL
-- nunca acontece: o default false preserva todos os documentos existentes como
-- privados, exatamente como estavam.
alter table public.documentos_financeiros
  add column if not exists compartilhado_casal boolean not null default false;

create index if not exists documentos_casal_idx
  on public.documentos_financeiros (usuario_id)
  where compartilhado_casal;

-- Solicitacoes de compartilhamento de documento: uma pessoa pede para levar um
-- documento ao casal e o parceiro aceita ou recusa. Enquanto pendente o
-- documento NAO e do casal (`documentos_financeiros.compartilhado_casal` segue
-- false); o aceite e que marca o documento. `nome_documento`/`tipo_documento`
-- sao um retrato para a notificacao e o hub mostrarem o pedido sem depender do
-- RLS da conta de quem enviou.
create table if not exists public.compartilhamentos_documentos_casal (
  id uuid primary key default gen_random_uuid(),
  vinculo_id uuid not null references public.vinculos_casal(id) on delete cascade,
  documento_id uuid not null
    references public.documentos_financeiros(id) on delete cascade,
  usuario_id uuid not null references auth.users(id) on delete cascade, -- dono do documento
  nome_documento text not null check (char_length(nome_documento) between 1 and 255),
  tipo_documento text not null,
  status text not null default 'pendente'
    check (status in ('pendente', 'aceito', 'recusado')),
  proposto_por uuid not null references auth.users(id) on delete cascade,
  respondida_por uuid references auth.users(id) on delete set null,
  respondida_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

-- Um pedido aberto por documento: sem isso, dois cliques criariam duas
-- pendencias para o mesmo arquivo.
create unique index if not exists compartilhamentos_documentos_pendente_idx
  on public.compartilhamentos_documentos_casal (vinculo_id, documento_id)
  where status = 'pendente';

create index if not exists compartilhamentos_documentos_vinculo_status_idx
  on public.compartilhamentos_documentos_casal (vinculo_id, status, criado_em desc);

drop trigger if exists compartilhamentos_documentos_casal_atualizado_em
  on public.compartilhamentos_documentos_casal;
create trigger compartilhamentos_documentos_casal_atualizado_em
before update on public.compartilhamentos_documentos_casal
for each row execute function public.definir_atualizado_em();

alter table public.compartilhamentos_documentos_casal enable row level security;
alter table public.compartilhamentos_documentos_casal force row level security;

drop policy if exists compartilhamentos_documentos_casal_dos_membros
  on public.compartilhamentos_documentos_casal;
create policy compartilhamentos_documentos_casal_dos_membros
  on public.compartilhamentos_documentos_casal
for all to authenticated
using (
  exists (
    select 1 from public.vinculos_casal v
    where v.id = vinculo_id
      and v.status = 'ativo'
      and (select auth.uid()) in (v.criador_id, v.parceiro_id)
  )
)
with check (
  exists (
    select 1 from public.vinculos_casal v
    where v.id = vinculo_id
      and v.status = 'ativo'
      and (select auth.uid()) in (v.criador_id, v.parceiro_id)
  )
);

revoke all on public.compartilhamentos_documentos_casal from anon;
grant select, insert, update, delete
  on public.compartilhamentos_documentos_casal to authenticated;

-- A central de notificacoes passa a carregar tambem o aceite de documentos.
alter table public.notificacoes drop constraint if exists notificacoes_tipo_check;
alter table public.notificacoes add constraint notificacoes_tipo_check
  check (tipo in (
    'desejo_pendente', 'desejo_aceito', 'desejo_recusado',
    'divisao_pendente', 'divisao_aceita', 'divisao_recusada',
    'compartilhamento_pendente', 'compartilhamento_aceito', 'compartilhamento_recusado',
    'documento_pendente', 'documento_aceito', 'documento_recusado'
  ));

alter table public.notificacoes drop constraint if exists notificacoes_acao_check;
alter table public.notificacoes add constraint notificacoes_acao_check
  check (acao is null or acao in (
    'aprovar_desejo', 'reenviar_desejo', 'aprovar_divisao',
    'aprovar_compartilhamento', 'aprovar_documento'
  ));

alter table public.notificacoes drop constraint if exists notificacoes_entidade_tipo_check;
alter table public.notificacoes add constraint notificacoes_entidade_tipo_check
  check (entidade_tipo is null or entidade_tipo in (
    'desejo_casal', 'divisao_casal', 'compartilhamento_casal', 'documento_casal'
  ));

-- RAG do casal ---------------------------------------------------------------
--
-- Um documento do casal e conhecimento dos dois: o agente de cada um deve poder
-- consultar tambem os documentos que o parceiro ja compartilhou. A busca ganha
-- um `p_parceiro` opcional; os chunks do parceiro so entram quando o documento
-- de origem esta `compartilhado_casal`. Sem parceiro (ou sem documento aceito)
-- a funcao responde exatamente como antes: so os proprios trechos.
drop function if exists public.match_documento_chunks(vector, uuid, integer, uuid);

create or replace function public.match_documento_chunks(
  consulta vector(1536),
  p_usuario uuid,
  limite integer default 6,
  p_documento uuid default null,
  p_parceiro uuid default null
)
returns table (
  id uuid,
  documento_id uuid,
  ordem integer,
  pagina integer,
  conteudo text,
  distancia double precision
)
language sql
stable
as $$
  select
    c.id,
    c.documento_id,
    c.ordem,
    c.pagina,
    c.conteudo,
    (c.embedding <=> consulta) as distancia
  from public.documento_chunks c
  where (
      c.usuario_id = p_usuario
      or (
        p_parceiro is not null
        and c.usuario_id = p_parceiro
        and exists (
          select 1 from public.documentos_financeiros d
          where d.id = c.documento_id and d.compartilhado_casal
        )
      )
    )
    and (p_documento is null or c.documento_id = p_documento)
  order by c.embedding <=> consulta
  limit greatest(limite, 1);
$$;

revoke all on function
  public.match_documento_chunks(vector, uuid, integer, uuid, uuid) from anon;
grant execute on function
  public.match_documento_chunks(vector, uuid, integer, uuid, uuid)
  to authenticated, service_role;

commit;
