begin;

-- A organizacao de um documento do casal pertence a cada gaveta -------------
--
-- O arquivo continua tendo um unico dono, mas a pasta em que ele aparece nao
-- pode ser herdada pela outra pessoa: os ids de `pastas_documentos` sao
-- privados e cada integrante do casal desenha a propria arvore. Esta projecao
-- guarda apenas a arrumacao de quem esta olhando. Sem linha, o documento
-- compartilhado nasce solto e pendente nessa gaveta.
create table if not exists public.organizacoes_documentos_pessoais (
  usuario_id uuid not null references auth.users(id) on delete cascade,
  documento_id uuid not null
    references public.documentos_financeiros(id) on delete cascade,
  nome_exibicao text
    check (nome_exibicao is null or char_length(nome_exibicao) between 1 and 200),
  categoria text not null default 'outros' check (categoria in (
    'identificacao', 'contratos', 'financeiro', 'moradia', 'veiculo',
    'viagens', 'saude', 'seguros', 'trabalho', 'estudos', 'outros'
  )),
  pasta_id uuid references public.pastas_documentos(id) on delete set null,
  organizacao text not null default 'pendente'
    check (organizacao in ('pendente', 'ia', 'pessoa')),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  primary key (usuario_id, documento_id)
);

create index if not exists organizacoes_documentos_pasta_idx
  on public.organizacoes_documentos_pessoais (usuario_id, pasta_id);

create index if not exists organizacoes_documentos_pendentes_idx
  on public.organizacoes_documentos_pessoais (usuario_id, criado_em desc)
  where organizacao = 'pendente';

drop trigger if exists organizacoes_documentos_pessoais_atualizado_em
  on public.organizacoes_documentos_pessoais;
create trigger organizacoes_documentos_pessoais_atualizado_em
before update on public.organizacoes_documentos_pessoais
for each row execute function public.definir_atualizado_em();

-- Se o arquivo volta a ser privado ou o casal e encerrado, a projecao deixa
-- de ter uma gaveta valida. Apagar agora evita pastas com contagem fantasma.
create or replace function public.limpar_organizacoes_de_documento_privado()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.compartilhado_casal and not new.compartilhado_casal then
    delete from public.organizacoes_documentos_pessoais
     where documento_id = new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists limpar_organizacoes_de_documento_privado
  on public.documentos_financeiros;
create trigger limpar_organizacoes_de_documento_privado
after update of compartilhado_casal on public.documentos_financeiros
for each row execute function public.limpar_organizacoes_de_documento_privado();

create or replace function public.limpar_organizacoes_ao_encerrar_casal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.status = 'ativo' and new.status <> 'ativo' then
    delete from public.organizacoes_documentos_pessoais
     where usuario_id in (new.criador_id, new.parceiro_id);
  end if;
  return new;
end;
$$;

drop trigger if exists limpar_organizacoes_ao_encerrar_casal
  on public.vinculos_casal;
create trigger limpar_organizacoes_ao_encerrar_casal
after update of status on public.vinculos_casal
for each row execute function public.limpar_organizacoes_ao_encerrar_casal();

alter table public.organizacoes_documentos_pessoais enable row level security;
alter table public.organizacoes_documentos_pessoais force row level security;

drop policy if exists organizacoes_documentos_pessoais_do_usuario
  on public.organizacoes_documentos_pessoais;
create policy organizacoes_documentos_pessoais_do_usuario
  on public.organizacoes_documentos_pessoais
for all to authenticated
using ((select auth.uid()) = usuario_id)
with check (
  (select auth.uid()) = usuario_id
  and exists (
    select 1
      from public.documentos_financeiros d
      join public.vinculos_casal v
        on v.status = 'ativo'
       and d.usuario_id in (v.criador_id, v.parceiro_id)
     where d.id = documento_id
       and d.compartilhado_casal
       and (select auth.uid()) in (v.criador_id, v.parceiro_id)
       and d.usuario_id <> (select auth.uid())
  )
);

revoke all on public.organizacoes_documentos_pessoais from anon;
grant select, insert, update, delete
  on public.organizacoes_documentos_pessoais to authenticated;

commit;
