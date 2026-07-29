begin;

alter table public.documentos_financeiros
  add column if not exists protegido boolean not null default false,
  add column if not exists arquivo_ai boolean not null default true;

create index if not exists documentos_protegidos_usuario_idx
  on public.documentos_financeiros (usuario_id, criado_em desc)
  where protegido and excluido_em is null and versao_atual;

create table if not exists public.documentos_desafios_cofre (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  chave_privada_servidor text not null,
  desafio text not null,
  expira_em timestamptz not null default (now() + interval '5 minutes'),
  usado_em timestamptz,
  criado_em timestamptz not null default now()
);

create index if not exists documentos_desafios_usuario_idx
  on public.documentos_desafios_cofre (usuario_id, expira_em desc);

create table if not exists public.documentos_sessoes_protegidas (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  token_hash text not null unique
    check (token_hash ~ '^[0-9a-f]{64}$'),
  expira_em timestamptz not null,
  criado_em timestamptz not null default now()
);

create index if not exists documentos_sessoes_usuario_idx
  on public.documentos_sessoes_protegidas (usuario_id, expira_em desc);

create table if not exists public.documentos_acessos (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  documento_id uuid not null
    references public.documentos_financeiros(id) on delete cascade,
  acao text not null check (
    acao in (
      'protegido',
      'desprotegido',
      'preview',
      'download',
      'fonte_original',
      'compartilhamento_temporario_criado',
      'compartilhamento_temporario_aberto',
      'compartilhamento_temporario_revogado',
      'kit_exportado'
    )
  ),
  contexto jsonb not null default '{}'::jsonb,
  criado_em timestamptz not null default now()
);

create index if not exists documentos_acessos_documento_idx
  on public.documentos_acessos (documento_id, criado_em desc);

create table if not exists public.documentos_compartilhamentos_temporarios (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  documento_id uuid not null
    references public.documentos_financeiros(id) on delete cascade,
  token_hash text not null unique
    check (token_hash ~ '^[0-9a-f]{64}$'),
  expira_em timestamptz not null,
  max_aberturas integer not null default 10
    check (max_aberturas between 1 and 50),
  aberturas integer not null default 0
    check (aberturas >= 0),
  revogado_em timestamptz,
  criado_em timestamptz not null default now()
);

create index if not exists documentos_compartilhamentos_usuario_idx
  on public.documentos_compartilhamentos_temporarios
    (usuario_id, documento_id, criado_em desc);

-- Uma fila iniciada antes do clique em Proteger não pode recolocar texto
-- sensível no Arquivo AI depois que a pessoa já o retirou.
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
        or not documento.arquivo_ai
      )
  ) then
    raise exception 'documento fora do Arquivo AI nao pode receber texto';
  end if;
  return new;
end;
$$;

drop trigger if exists documento_texto_exige_documento_ativo
  on public.documento_textos;
create trigger documento_texto_exige_documento_ativo
before insert or update on public.documento_textos
for each row execute function public.impedir_chunk_de_documento_excluido();

-- O mesmo bloqueio já protege os chunks; recriar explicita a nova regra.
drop trigger if exists documento_chunk_exige_documento_ativo
  on public.documento_chunks;
create trigger documento_chunk_exige_documento_ativo
before insert or update on public.documento_chunks
for each row execute function public.impedir_chunk_de_documento_excluido();

-- Prazos continuam guardados, mas um documento protegido não deixa título
-- ou data aparecer no sino fora da sessão protegida.
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
     and not documento.protegido
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

alter table public.documentos_desafios_cofre enable row level security;
alter table public.documentos_desafios_cofre force row level security;
alter table public.documentos_sessoes_protegidas enable row level security;
alter table public.documentos_sessoes_protegidas force row level security;
alter table public.documentos_acessos enable row level security;
alter table public.documentos_acessos force row level security;
alter table public.documentos_compartilhamentos_temporarios enable row level security;
alter table public.documentos_compartilhamentos_temporarios force row level security;

revoke all on public.documentos_desafios_cofre from anon, authenticated;
revoke all on public.documentos_sessoes_protegidas from anon, authenticated;
revoke all on public.documentos_acessos from anon, authenticated;
revoke all on public.documentos_compartilhamentos_temporarios
  from anon, authenticated;

commit;
