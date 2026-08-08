begin;

-- O recurso é um novo julgamento, não um benefício automático. A transação
-- continua aplicando somente a diferença entre as decisões, agora nos dois
-- sentidos: estorna quando reduz e desconta o adicional quando agrava.
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

revoke all on function public.registrar_recurso_ocorrencia_casa(jsonb, jsonb)
  from public, anon, authenticated;

commit;
