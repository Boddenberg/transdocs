begin;

-- Uma decisão de Têmis não guardava nada sobre a própria produção. O provedor
-- devolve `input_tokens`/`output_tokens` a cada chamada e o código os
-- descartava na linha seguinte, então "quanto custa e quanto demora um
-- julgamento" não tinha resposta possível a partir do repositório — nem para
-- decidir se uma versão nova do prompt ficou melhor ou apenas mais cara.
--
-- `pontos_politica` e `teto_recurso` são as colunas de sombra: a pena que a
-- régua em código (app/modulos/casa/dominio/dosimetria.py) aplicaria a estes
-- mesmos fatores, gravada ao lado da pena que o modelo aplicou. Enquanto a
-- divergência não for medida, quem decide continua sendo o modelo.
--
-- Tudo aqui é aditivo e anulável: decisões já gravadas seguem legíveis.
alter table public.decisoes_ocorrencias_casa
  add column if not exists tokens_entrada integer
    check (tokens_entrada is null or tokens_entrada >= 0),
  add column if not exists tokens_saida integer
    check (tokens_saida is null or tokens_saida >= 0),
  add column if not exists duracao_ms integer
    check (duracao_ms is null or duracao_ms >= 0),
  add column if not exists tentativas smallint
    check (tentativas is null or tentativas between 1 and 10),
  add column if not exists com_imagem boolean,
  add column if not exists fatores_gravidade jsonb,
  add column if not exists pontos_politica smallint
    check (pontos_politica is null or pontos_politica in (0, 5, 10, 15, 20, 30, 40, 50)),
  add column if not exists teto_recurso smallint
    check (teto_recurso is null or teto_recurso in (0, 5, 10, 15, 20, 30, 40, 50));

-- Comparar o custo de duas versões de prompt exige achar as decisões de cada
-- uma sem varrer a tabela inteira.
create index if not exists decisoes_ocorrencias_casa_versao_idx
  on public.decisoes_ocorrencias_casa (versao_prompt, criada_em desc);

create or replace function public.registrar_julgamento_ocorrencia_casa(
  p_ocorrencia jsonb,
  p_decisao jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ocorrencia_id uuid := (p_ocorrencia ->> 'id')::uuid;
  v_decisao_id uuid := (p_decisao ->> 'id')::uuid;
  v_vinculo_id uuid := (p_ocorrencia ->> 'vinculo_id')::uuid;
  v_acusador_id uuid := (p_ocorrencia ->> 'acusador_id')::uuid;
  v_acusado_id uuid := (p_ocorrencia ->> 'acusado_id')::uuid;
  v_pontos smallint := (p_decisao ->> 'pontos_perdidos')::smallint;
  v_veredito text := p_decisao ->> 'veredito';
begin
  if not exists (
    select 1
      from public.vinculos_casal
     where id = v_vinculo_id
       and status = 'ativo'
       and v_acusador_id in (criador_id, parceiro_id)
       and v_acusado_id in (criador_id, parceiro_id)
       and v_acusador_id <> v_acusado_id
  ) then
    raise insufficient_privilege using message = 'Pessoas fora desta residência.';
  end if;
  if v_pontos not in (0, 5, 10, 15, 20, 30, 40, 50)
    or (v_veredito = 'condenacao') <> (v_pontos > 0)
  then
    raise check_violation using message = 'Sentença fora da régua da Casa.';
  end if;

  insert into public.ocorrencias_casa (
    id, usuario_id, vinculo_id, acusador_id, acusado_id, relato, transcricao,
    foto_caminho, foto_mime, foto_hash, descricao_foto, origem, wa_id, estado,
    chave_semantica
  )
  values (
    v_ocorrencia_id,
    v_acusador_id,
    v_vinculo_id,
    v_acusador_id,
    v_acusado_id,
    p_ocorrencia ->> 'relato',
    p_ocorrencia ->> 'transcricao',
    p_ocorrencia ->> 'foto_caminho',
    p_ocorrencia ->> 'foto_mime',
    p_ocorrencia ->> 'foto_hash',
    p_ocorrencia ->> 'descricao_foto',
    p_ocorrencia ->> 'origem',
    p_ocorrencia ->> 'wa_id',
    'julgada',
    p_decisao ->> 'tipo_interno'
  )
  on conflict (vinculo_id, wa_id) where wa_id is not null do nothing;

  -- Reentrega do mesmo wa_id devolve o caso anterior sem duplicar decisão/pontos.
  if not found then
    select id into v_ocorrencia_id
      from public.ocorrencias_casa
     where vinculo_id = v_vinculo_id
       and wa_id = p_ocorrencia ->> 'wa_id';
    return v_ocorrencia_id;
  end if;

  insert into public.decisoes_ocorrencias_casa (
    id, usuario_id, vinculo_id, ocorrencia_id, tipo, veredito, gravidade,
    pontos_perdidos, fundamentacao, confianca, chave_semantica,
    ocorrencias_semelhantes_ids, evidencia_suficiente, modelo, versao_prompt,
    hash_dossie, tokens_entrada, tokens_saida, duracao_ms, tentativas,
    com_imagem, fatores_gravidade, pontos_politica
  )
  values (
    v_decisao_id,
    v_acusador_id,
    v_vinculo_id,
    v_ocorrencia_id,
    'inicial',
    v_veredito,
    p_decisao ->> 'gravidade',
    v_pontos,
    p_decisao ->> 'fundamentacao',
    (p_decisao ->> 'confianca')::numeric,
    p_decisao ->> 'tipo_interno',
    array(
      select jsonb_array_elements_text(
        coalesce(p_decisao -> 'ocorrencias_semelhantes_ids', '[]'::jsonb)
      )::uuid
    ),
    (p_decisao ->> 'evidencia_suficiente')::boolean,
    p_decisao ->> 'modelo',
    p_decisao ->> 'versao_prompt',
    p_decisao ->> 'hash_dossie',
    (p_decisao ->> 'tokens_entrada')::integer,
    (p_decisao ->> 'tokens_saida')::integer,
    (p_decisao ->> 'duracao_ms')::integer,
    (p_decisao ->> 'tentativas')::smallint,
    (p_decisao ->> 'com_imagem')::boolean,
    p_decisao -> 'fatores_gravidade',
    (p_decisao ->> 'pontos_politica')::smallint
  );

  update public.ocorrencias_casa
     set decisao_atual_id = v_decisao_id
   where id = v_ocorrencia_id;

  if v_pontos > 0 then
    insert into public.movimentos_pontos_casa (
      usuario_id, vinculo_id, pontos, origem, referencia_id, natureza, criado_por
    )
    values (
      v_acusado_id, v_vinculo_id, -v_pontos, 'condenacao',
      v_ocorrencia_id, 'decisao_inicial', v_acusador_id
    )
    on conflict (origem, referencia_id, usuario_id, natureza) do nothing;
  end if;

  return v_ocorrencia_id;
end;
$$;

create or replace function public.registrar_recurso_ocorrencia_casa(
  p_recurso jsonb,
  p_decisao jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ocorrencia public.ocorrencias_casa%rowtype;
  v_recurso_id uuid := (p_recurso ->> 'id')::uuid;
  v_decisao_id uuid := (p_decisao ->> 'id')::uuid;
  v_usuario_id uuid := (p_recurso ->> 'usuario_id')::uuid;
  v_pontos_antes smallint;
  v_pontos_depois smallint := (p_decisao ->> 'pontos_perdidos')::smallint;
  v_veredito text := p_decisao ->> 'veredito';
begin
  select * into v_ocorrencia
    from public.ocorrencias_casa
   where id = (p_recurso ->> 'ocorrencia_id')::uuid
     and excluida_em is null
   for update;
  if v_ocorrencia.id is null then
    raise no_data_found using message = 'Ocorrência não encontrada.';
  end if;
  if v_usuario_id <> v_ocorrencia.acusado_id then
    raise insufficient_privilege using message = 'Somente a pessoa acusada pode recorrer.';
  end if;
  if exists (
    select 1 from public.recursos_ocorrencias_casa
     where ocorrencia_id = v_ocorrencia.id
  ) then
    raise unique_violation using message = 'Esta ocorrência já recebeu recurso.';
  end if;

  select pontos_perdidos into v_pontos_antes
    from public.decisoes_ocorrencias_casa
   where id = v_ocorrencia.decisao_atual_id;
  if v_pontos_depois not in (0, 5, 10, 15, 20, 30, 40, 50)
    or (v_veredito = 'condenacao') <> (v_pontos_depois > 0)
  then
    raise check_violation using message = 'Sentença do recurso fora da régua da Casa.';
  end if;

  insert into public.recursos_ocorrencias_casa (
    id, usuario_id, vinculo_id, ocorrencia_id, manifestacao, transcricao,
    foto_caminho, foto_mime, foto_hash, descricao_foto
  )
  values (
    v_recurso_id,
    v_usuario_id,
    v_ocorrencia.vinculo_id,
    v_ocorrencia.id,
    p_recurso ->> 'manifestacao',
    p_recurso ->> 'transcricao',
    p_recurso ->> 'foto_caminho',
    p_recurso ->> 'foto_mime',
    p_recurso ->> 'foto_hash',
    p_recurso ->> 'descricao_foto'
  );

  insert into public.decisoes_ocorrencias_casa (
    id, usuario_id, vinculo_id, ocorrencia_id, tipo, veredito, gravidade,
    pontos_perdidos, fundamentacao, confianca, chave_semantica,
    ocorrencias_semelhantes_ids, evidencia_suficiente, modelo, versao_prompt,
    hash_dossie, tokens_entrada, tokens_saida, duracao_ms, tentativas,
    com_imagem, fatores_gravidade, pontos_politica, teto_recurso
  )
  values (
    v_decisao_id,
    v_usuario_id,
    v_ocorrencia.vinculo_id,
    v_ocorrencia.id,
    'recurso',
    v_veredito,
    p_decisao ->> 'gravidade',
    v_pontos_depois,
    p_decisao ->> 'fundamentacao',
    (p_decisao ->> 'confianca')::numeric,
    p_decisao ->> 'tipo_interno',
    array(
      select jsonb_array_elements_text(
        coalesce(p_decisao -> 'ocorrencias_semelhantes_ids', '[]'::jsonb)
      )::uuid
    ),
    (p_decisao ->> 'evidencia_suficiente')::boolean,
    p_decisao ->> 'modelo',
    p_decisao ->> 'versao_prompt',
    p_decisao ->> 'hash_dossie',
    (p_decisao ->> 'tokens_entrada')::integer,
    (p_decisao ->> 'tokens_saida')::integer,
    (p_decisao ->> 'duracao_ms')::integer,
    (p_decisao ->> 'tentativas')::smallint,
    (p_decisao ->> 'com_imagem')::boolean,
    p_decisao -> 'fatores_gravidade',
    (p_decisao ->> 'pontos_politica')::smallint,
    (p_decisao ->> 'teto_recurso')::smallint
  );

  update public.recursos_ocorrencias_casa
     set decisao_final_id = v_decisao_id
   where id = v_recurso_id;
  update public.ocorrencias_casa
     set estado = 'final',
         decisao_atual_id = v_decisao_id,
         chave_semantica = p_decisao ->> 'tipo_interno'
   where id = v_ocorrencia.id;

  if v_pontos_depois < v_pontos_antes then
    insert into public.movimentos_pontos_casa (
      usuario_id, vinculo_id, pontos, origem, referencia_id, natureza, criado_por
    )
    values (
      v_ocorrencia.acusado_id,
      v_ocorrencia.vinculo_id,
      v_pontos_antes - v_pontos_depois,
      'estorno',
      v_ocorrencia.id,
      'recurso',
      v_usuario_id
    )
    on conflict (origem, referencia_id, usuario_id, natureza) do nothing;
  elsif v_pontos_depois > v_pontos_antes then
    insert into public.movimentos_pontos_casa (
      usuario_id, vinculo_id, pontos, origem, referencia_id, natureza, criado_por
    )
    values (
      v_ocorrencia.acusado_id,
      v_ocorrencia.vinculo_id,
      -(v_pontos_depois - v_pontos_antes),
      'condenacao',
      v_ocorrencia.id,
      'recurso_agravamento',
      v_usuario_id
    )
    on conflict (origem, referencia_id, usuario_id, natureza) do nothing;
  end if;

  return v_ocorrencia.id;
end;
$$;

revoke all on function public.registrar_julgamento_ocorrencia_casa(jsonb, jsonb)
  from public, anon, authenticated;
revoke all on function public.registrar_recurso_ocorrencia_casa(jsonb, jsonb)
  from public, anon, authenticated;

commit;
