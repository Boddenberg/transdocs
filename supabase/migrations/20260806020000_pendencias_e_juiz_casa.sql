begin;

-- Pendências são fatos pontuais. Elas não participam do catálogo nem do
-- histórico de atividades recorrentes.
create table public.pendencias_casa (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  vinculo_id uuid not null references public.vinculos_casal(id) on delete cascade,
  ambiente_id uuid references public.ambientes_atividades_casa(id) on delete restrict,
  titulo text not null check (char_length(titulo) between 1 and 160),
  descricao text check (descricao is null or char_length(descricao) <= 2000),
  foto_caminho text unique,
  foto_mime text check (foto_mime is null or foto_mime = 'image/webp'),
  foto_hash text check (foto_hash is null or foto_hash ~ '^[a-f0-9]{64}$'),
  origem text not null check (origem in ('web', 'whatsapp')),
  wa_id text check (wa_id is null or char_length(wa_id) between 1 and 120),
  status text not null default 'aberta' check (status in ('aberta', 'resolvida')),
  complexidade text not null
    check (complexidade in ('simples', 'trabalhosa', 'complexa')),
  pontos_estimados smallint not null check (pontos_estimados between 0 and 100),
  proximo_lembrete_em date,
  ultimo_lembrete_em timestamptz,
  quantidade_lembretes integer not null default 0 check (quantidade_lembretes >= 0),
  lembrete_urgencia text not null default 'normal'
    check (lembrete_urgencia in ('baixa', 'normal', 'alta')),
  lembrete_motivo text
    check (lembrete_motivo is null or char_length(lembrete_motivo) <= 240),
  versao_decisao_ia text,
  resolvida_por uuid references auth.users(id) on delete set null,
  resolvida_em timestamptz,
  excluida_por uuid references auth.users(id) on delete set null,
  excluida_em timestamptz,
  criada_em timestamptz not null default now(),
  atualizada_em timestamptz not null default now(),
  check (
    (foto_caminho is null and foto_mime is null and foto_hash is null)
    or (foto_caminho is not null and foto_mime is not null and foto_hash is not null)
  ),
  check (
    (status = 'aberta' and resolvida_por is null and resolvida_em is null)
    or (status = 'resolvida' and resolvida_por is not null and resolvida_em is not null)
  ),
  check ((excluida_em is null) = (excluida_por is null))
);

create unique index pendencias_casa_wa_idx
  on public.pendencias_casa (vinculo_id, wa_id)
  where wa_id is not null;
create index pendencias_casa_abertas_ambiente_idx
  on public.pendencias_casa (vinculo_id, ambiente_id, criada_em)
  where status = 'aberta' and excluida_em is null;
create index pendencias_casa_lembrete_idx
  on public.pendencias_casa (proximo_lembrete_em, vinculo_id, criada_em)
  where status = 'aberta' and excluida_em is null and proximo_lembrete_em is not null;

create table public.eventos_pendencias_casa (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  vinculo_id uuid not null references public.vinculos_casal(id) on delete cascade,
  pendencia_id uuid not null references public.pendencias_casa(id) on delete cascade,
  evento text not null check (
    evento in ('criacao', 'edicao', 'lembrete', 'conclusao', 'reabertura', 'exclusao')
  ),
  chave_idempotencia text,
  dados jsonb not null default '{}'::jsonb,
  criado_em timestamptz not null default now()
);

create unique index eventos_pendencias_casa_idempotencia_idx
  on public.eventos_pendencias_casa
  (pendencia_id, evento, chave_idempotencia)
  where chave_idempotencia is not null;
create index eventos_pendencias_casa_historico_idx
  on public.eventos_pendencias_casa (vinculo_id, pendencia_id, criado_em);

-- O livro é anexo e imutável. Os pontos das atividades continuam na tabela de
-- participantes de registros; nenhuma linha antiga é migrada ou duplicada.
create table public.movimentos_pontos_casa (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  vinculo_id uuid not null references public.vinculos_casal(id) on delete cascade,
  pontos numeric(12, 2) not null check (pontos <> 0),
  origem text not null check (
    origem in ('conclusao_pendencia', 'reversao_pendencia', 'condenacao', 'estorno')
  ),
  referencia_id uuid not null,
  natureza text not null check (char_length(natureza) between 1 and 120),
  criado_por uuid not null references auth.users(id) on delete restrict,
  criado_em timestamptz not null default now(),
  unique (origem, referencia_id, usuario_id, natureza),
  check (
    (origem = 'conclusao_pendencia' and pontos > 0)
    or (origem = 'reversao_pendencia' and pontos < 0)
    or (origem = 'condenacao' and pontos < 0)
    or (origem = 'estorno' and pontos > 0)
  )
);

create index movimentos_pontos_casa_saldo_idx
  on public.movimentos_pontos_casa (vinculo_id, usuario_id, criado_em);

create table public.ocorrencias_casa (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  vinculo_id uuid not null references public.vinculos_casal(id) on delete cascade,
  acusador_id uuid not null references auth.users(id) on delete restrict,
  acusado_id uuid not null references auth.users(id) on delete restrict,
  relato text check (relato is null or char_length(relato) <= 4000),
  transcricao text check (transcricao is null or char_length(transcricao) <= 4000),
  foto_caminho text unique,
  foto_mime text check (foto_mime is null or foto_mime = 'image/webp'),
  foto_hash text check (foto_hash is null or foto_hash ~ '^[a-f0-9]{64}$'),
  descricao_foto text check (
    descricao_foto is null or char_length(descricao_foto) <= 1000
  ),
  origem text not null check (origem in ('web', 'whatsapp')),
  wa_id text check (wa_id is null or char_length(wa_id) between 1 and 120),
  estado text not null default 'julgada'
    check (estado in ('julgada', 'em_recurso', 'final')),
  chave_semantica text check (
    chave_semantica is null or char_length(chave_semantica) between 1 and 120
  ),
  decisao_atual_id uuid,
  excluida_em timestamptz,
  criada_em timestamptz not null default now(),
  atualizada_em timestamptz not null default now(),
  check (acusador_id <> acusado_id),
  check (coalesce(relato, transcricao, descricao_foto, foto_caminho) is not null),
  check (
    (foto_caminho is null and foto_mime is null and foto_hash is null)
    or (foto_caminho is not null and foto_mime is not null and foto_hash is not null)
  )
);

create unique index ocorrencias_casa_wa_idx
  on public.ocorrencias_casa (vinculo_id, wa_id)
  where wa_id is not null;
create index ocorrencias_casa_historico_idx
  on public.ocorrencias_casa (vinculo_id, criada_em desc)
  where excluida_em is null;

create table public.decisoes_ocorrencias_casa (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  vinculo_id uuid not null references public.vinculos_casal(id) on delete cascade,
  ocorrencia_id uuid not null references public.ocorrencias_casa(id) on delete cascade,
  tipo text not null check (tipo in ('inicial', 'recurso')),
  veredito text not null check (
    veredito in ('condenacao', 'advertencia', 'absolvicao', 'elementos_insuficientes')
  ),
  gravidade text not null check (
    gravidade in ('nenhuma', 'leve', 'media', 'relevante', 'grave')
  ),
  pontos_perdidos smallint not null
    check (pontos_perdidos in (0, 5, 10, 15, 20, 30, 40, 50)),
  fundamentacao text not null check (char_length(fundamentacao) between 1 and 1000),
  confianca numeric(4, 3) not null check (confianca between 0 and 1),
  chave_semantica text not null check (char_length(chave_semantica) between 1 and 120),
  ocorrencias_semelhantes_ids uuid[] not null default '{}',
  evidencia_suficiente boolean not null,
  modelo text not null check (char_length(modelo) between 1 and 120),
  versao_prompt text not null check (char_length(versao_prompt) between 1 and 80),
  hash_dossie text not null check (hash_dossie ~ '^[a-f0-9]{64}$'),
  criada_em timestamptz not null default now(),
  unique (ocorrencia_id, tipo),
  check (
    (veredito = 'condenacao' and pontos_perdidos > 0)
    or (veredito <> 'condenacao' and pontos_perdidos = 0)
  )
);

alter table public.ocorrencias_casa
  add constraint ocorrencias_casa_decisao_atual_fk
  foreign key (decisao_atual_id)
  references public.decisoes_ocorrencias_casa(id) on delete restrict;

create index decisoes_ocorrencias_casa_ocorrencia_idx
  on public.decisoes_ocorrencias_casa (ocorrencia_id, criada_em);

create table public.recursos_ocorrencias_casa (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  vinculo_id uuid not null references public.vinculos_casal(id) on delete cascade,
  ocorrencia_id uuid not null unique
    references public.ocorrencias_casa(id) on delete cascade,
  manifestacao text check (manifestacao is null or char_length(manifestacao) <= 4000),
  transcricao text check (transcricao is null or char_length(transcricao) <= 4000),
  foto_caminho text unique,
  foto_mime text check (foto_mime is null or foto_mime = 'image/webp'),
  foto_hash text check (foto_hash is null or foto_hash ~ '^[a-f0-9]{64}$'),
  descricao_foto text check (
    descricao_foto is null or char_length(descricao_foto) <= 1000
  ),
  decisao_final_id uuid references public.decisoes_ocorrencias_casa(id) on delete restrict,
  criado_em timestamptz not null default now(),
  check (
    coalesce(manifestacao, transcricao, descricao_foto, foto_caminho) is not null
  ),
  check (
    (foto_caminho is null and foto_mime is null and foto_hash is null)
    or (foto_caminho is not null and foto_mime is not null and foto_hash is not null)
  )
);

-- A mídia recebida pertence ao canal, não à Casa. O módulo consumidor recebe
-- apenas a referência privada depois da normalização.
create table public.anexos_recebidos_whatsapp (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  mensagem_id uuid not null unique
    references public.recebidas_whatsapp(id) on delete cascade,
  caminho_privado text not null unique,
  nome text not null check (char_length(nome) between 1 and 160),
  mime_original text not null
    check (mime_original in ('image/jpeg', 'image/png', 'image/webp')),
  mime_normalizado text not null default 'image/webp'
    check (mime_normalizado = 'image/webp'),
  hash_sha256 text not null check (hash_sha256 ~ '^[a-f0-9]{64}$'),
  tamanho_original integer not null check (tamanho_original between 1 and 10485760),
  legenda text check (legenda is null or char_length(legenda) <= 4000),
  descricao_visual text
    check (descricao_visual is null or char_length(descricao_visual) <= 1000),
  estado text not null default 'disponivel'
    check (estado in ('disponivel', 'consumido', 'expirado')),
  criado_em timestamptz not null default now(),
  consumido_em timestamptz,
  expira_em timestamptz not null default (now() + interval '24 hours')
);

create index anexos_recebidos_whatsapp_expira_idx
  on public.anexos_recebidos_whatsapp (expira_em)
  where estado = 'disponivel';

alter table public.configuracoes_whatsapp_casa
  add column if not exists lembretes_pendencias_ativos boolean not null default true;

-- O lembrete usa a caixa que a ponte já entrega. `referencia` identifica o dia
-- da tentativa e mantém dois pulsos concorrentes idempotentes.
alter table public.mensagens_whatsapp_casa
  add column if not exists pendencia_id uuid
    references public.pendencias_casa(id) on delete cascade;

alter table public.mensagens_whatsapp_casa
  drop constraint if exists mensagens_whatsapp_casa_tipo_check;
alter table public.mensagens_whatsapp_casa
  add constraint mensagens_whatsapp_casa_tipo_check
  check (tipo in (
    'bloco',
    'resumo_diario',
    'panorama_semanal',
    'panorama_mensal',
    'demonstracao',
    'lembrete_pendencia'
  ));

alter table public.mensagens_whatsapp_casa
  drop constraint if exists mensagens_whatsapp_casa_origem_check;
alter table public.mensagens_whatsapp_casa
  add constraint mensagens_whatsapp_casa_origem_check
  check (
    (
      tipo = 'bloco'
      and bloco_id is not null
      and referencia is null
      and pendencia_id is null
    )
    or (
      tipo in ('resumo_diario', 'panorama_semanal', 'panorama_mensal')
      and bloco_id is null
      and referencia is not null
      and pendencia_id is null
    )
    or (
      tipo = 'lembrete_pendencia'
      and bloco_id is null
      and referencia is not null
      and pendencia_id is not null
    )
    or (
      tipo = 'demonstracao'
      and bloco_id is null
      and referencia is null
      and pendencia_id is null
    )
  );

create unique index mensagens_whatsapp_casa_lembrete_idx
  on public.mensagens_whatsapp_casa (pendencia_id, referencia)
  where tipo = 'lembrete_pendencia';

-- Atualizações que representam estado corrente têm timestamp automático. As
-- trilhas, decisões e movimentos são append-only e portanto não recebem trigger.
create trigger pendencias_casa_atualizado_em
before update on public.pendencias_casa
for each row execute function public.definir_atualizado_em();

create trigger ocorrencias_casa_atualizado_em
before update on public.ocorrencias_casa
for each row execute function public.definir_atualizado_em();

do $$
declare
  tabela text;
begin
  foreach tabela in array array[
    'pendencias_casa',
    'eventos_pendencias_casa',
    'movimentos_pontos_casa',
    'ocorrencias_casa',
    'decisoes_ocorrencias_casa',
    'recursos_ocorrencias_casa'
  ]
  loop
    execute format('alter table public.%I enable row level security', tabela);
    execute format('alter table public.%I force row level security', tabela);
    execute format(
      'create policy %I_membros on public.%I for all to authenticated '
      'using (public.eh_membro_atividades_casa(vinculo_id)) '
      'with check (public.eh_membro_atividades_casa(vinculo_id))',
      tabela,
      tabela
    );
    execute format('revoke all on public.%I from anon', tabela);
    execute format('grant select on public.%I to authenticated', tabela);
    execute format('revoke insert, update, delete on public.%I from authenticated', tabela);
  end loop;
end
$$;

alter table public.anexos_recebidos_whatsapp enable row level security;
alter table public.anexos_recebidos_whatsapp force row level security;
revoke all on public.anexos_recebidos_whatsapp from anon, authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'anexos-whatsapp',
  'anexos-whatsapp',
  false,
  10485760,
  array['image/webp']
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Conclusão e pontos nascem juntos. A função também é a trava de idempotência
-- contra clique duplo e reentrega do canal.
create or replace function public.concluir_pendencia_casa(
  p_pendencia_id uuid,
  p_usuario_id uuid,
  p_juntos boolean default false,
  p_coordenou_terceiro boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pendencia public.pendencias_casa%rowtype;
  v_criador uuid;
  v_parceiro uuid;
  v_pontos numeric(12, 2);
begin
  select * into v_pendencia
    from public.pendencias_casa
   where id = p_pendencia_id
     and excluida_em is null
   for update;

  if v_pendencia.id is null then
    raise no_data_found using message = 'Pendência não encontrada.';
  end if;
  if v_pendencia.status = 'resolvida' then
    return v_pendencia.id;
  end if;

  select criador_id, parceiro_id into v_criador, v_parceiro
    from public.vinculos_casal
   where id = v_pendencia.vinculo_id
     and status = 'ativo';
  if p_usuario_id not in (v_criador, v_parceiro) then
    raise insufficient_privilege using message = 'Pessoa fora desta residência.';
  end if;

  v_pontos := case
    when p_coordenou_terceiro then least(v_pendencia.pontos_estimados, 25)
    else v_pendencia.pontos_estimados
  end;

  update public.pendencias_casa
     set status = 'resolvida',
         resolvida_por = p_usuario_id,
         resolvida_em = now(),
         proximo_lembrete_em = null
   where id = v_pendencia.id;

  if p_juntos then
    insert into public.movimentos_pontos_casa (
      usuario_id, vinculo_id, pontos, origem, referencia_id, natureza, criado_por
    )
    values
      (
        v_criador, v_pendencia.vinculo_id, round(v_pontos / 2, 2),
        'conclusao_pendencia', v_pendencia.id, 'conclusao', p_usuario_id
      ),
      (
        v_parceiro, v_pendencia.vinculo_id, v_pontos - round(v_pontos / 2, 2),
        'conclusao_pendencia', v_pendencia.id, 'conclusao', p_usuario_id
      )
    on conflict (origem, referencia_id, usuario_id, natureza) do nothing;
  else
    insert into public.movimentos_pontos_casa (
      usuario_id, vinculo_id, pontos, origem, referencia_id, natureza, criado_por
    )
    values (
      p_usuario_id, v_pendencia.vinculo_id, v_pontos,
      'conclusao_pendencia', v_pendencia.id, 'conclusao', p_usuario_id
    )
    on conflict (origem, referencia_id, usuario_id, natureza) do nothing;
  end if;

  insert into public.eventos_pendencias_casa (
    usuario_id, vinculo_id, pendencia_id, evento, chave_idempotencia, dados
  )
  values (
    p_usuario_id,
    v_pendencia.vinculo_id,
    v_pendencia.id,
    'conclusao',
    'conclusao',
    pg_catalog.jsonb_build_object(
      'juntos', p_juntos,
      'coordenou_terceiro', p_coordenou_terceiro,
      'pontos', v_pontos
    )
  )
  on conflict (pendencia_id, evento, chave_idempotencia) where chave_idempotencia is not null
  do nothing;

  return v_pendencia.id;
end;
$$;

create or replace function public.reabrir_pendencia_casa(
  p_pendencia_id uuid,
  p_usuario_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pendencia public.pendencias_casa%rowtype;
  v_movimento record;
begin
  select * into v_pendencia
    from public.pendencias_casa
   where id = p_pendencia_id
     and excluida_em is null
   for update;
  if v_pendencia.id is null then
    raise no_data_found using message = 'Pendência não encontrada.';
  end if;
  if not exists (
    select 1 from public.vinculos_casal
     where id = v_pendencia.vinculo_id
       and status = 'ativo'
       and p_usuario_id in (criador_id, parceiro_id)
  ) then
    raise insufficient_privilege using message = 'Pessoa fora desta residência.';
  end if;
  if v_pendencia.status = 'aberta' then
    return v_pendencia.id;
  end if;

  for v_movimento in
    select * from public.movimentos_pontos_casa
     where origem = 'conclusao_pendencia'
       and referencia_id = v_pendencia.id
  loop
    insert into public.movimentos_pontos_casa (
      usuario_id, vinculo_id, pontos, origem, referencia_id, natureza, criado_por
    )
    values (
      v_movimento.usuario_id,
      v_movimento.vinculo_id,
      -v_movimento.pontos,
      'reversao_pendencia',
      v_pendencia.id,
      'reabertura',
      p_usuario_id
    )
    on conflict (origem, referencia_id, usuario_id, natureza) do nothing;
  end loop;

  update public.pendencias_casa
     set status = 'aberta',
         resolvida_por = null,
         resolvida_em = null,
         proximo_lembrete_em = current_date + 7
   where id = v_pendencia.id;

  insert into public.eventos_pendencias_casa (
    usuario_id, vinculo_id, pendencia_id, evento, chave_idempotencia
  )
  values (
    p_usuario_id, v_pendencia.vinculo_id, v_pendencia.id, 'reabertura', 'reabertura'
  )
  on conflict (pendencia_id, evento, chave_idempotencia) where chave_idempotencia is not null
  do nothing;

  return v_pendencia.id;
end;
$$;

revoke all on function public.concluir_pendencia_casa(uuid, uuid, boolean, boolean)
  from public, anon, authenticated;
revoke all on function public.reabrir_pendencia_casa(uuid, uuid)
  from public, anon, authenticated;

commit;
