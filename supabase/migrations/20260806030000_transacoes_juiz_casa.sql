begin;

-- A decisão e o desconto não podem aparecer separados. Os payloads já chegam
-- validados em Python, mas as mesmas invariantes são repetidas aqui na fronteira
-- transacional do banco.
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
    hash_dossie
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
    p_decisao ->> 'hash_dossie'
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
    or v_pontos_depois > v_pontos_antes
    or (v_veredito = 'condenacao') <> (v_pontos_depois > 0)
  then
    raise check_violation using message = 'O recurso não pode aumentar a pena.';
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
    hash_dossie
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
    p_decisao ->> 'hash_dossie'
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
  end if;

  return v_ocorrencia.id;
end;
$$;

revoke all on function public.registrar_julgamento_ocorrencia_casa(jsonb, jsonb)
  from public, anon, authenticated;
revoke all on function public.registrar_recurso_ocorrencia_casa(jsonb, jsonb)
  from public, anon, authenticated;

commit;
