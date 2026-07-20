begin;

-- Desfaz a importação detalhada do extrato Itaú, que espalhou lançamentos
-- pelo planejamento. Mantém somente uma fonte neutra em grupo próprio e os
-- ajustes explicitamente pedidos para Salário, Décimo terceiro e PLR.
do $$
begin
  if not exists (
    select 1
    from public.perfis
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and lower(coalesce(nome, '')) like '%filipe%'
  ) then
    raise exception 'Perfil do Filipe não encontrado; correção cancelada.';
  end if;

  if exists (
    select 1
    from public.grupos_fontes_panorama
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and lower(nome) = lower('Extrato Itaú')
      and id <> 'f8ab34c5-8949-5433-9458-9ddb9270526b'::uuid
  ) then
    raise exception 'Já existe outro grupo chamado Extrato Itaú; correção cancelada.';
  end if;

  if exists (
    select 1
    from public.contas
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and lower(nome) = lower('Extrato Itaú')
      and id <> 'd64bb1b6-1140-5470-8695-7aadce45262c'::uuid
  ) then
    raise exception 'Já existe outra fonte chamada Extrato Itaú; correção cancelada.';
  end if;
end;
$$;

do $$
declare
  quantidade_removida integer;
begin
  delete from public.movimentacoes
  where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
    and metadados ->> 'importacao_lote' = 'itau-conta-filipe-2026-01-a-06';

  get diagnostics quantidade_removida = row_count;
  if quantidade_removida <> 223 then
    raise exception
      'Correção Itaú incompleta: esperados 223 lançamentos removidos, removidos %.',
      quantidade_removida;
  end if;
end;
$$;

-- Restaura a transferência já existente do Mercado Pago ao estado anterior.
update public.movimentacoes
set conta_id = 'bbe5ac59-d57f-5149-842e-e4163f9bd0e2'::uuid,
    observacoes = 'Pix recebido FILIPE BODDENBERG RIBEIRO - operacao 153382432040 - saldo apos o lancamento R$ 106.87. Extrato Mercado Pago de 2026-04.',
    metadados = metadados - 'contrapartida_itau'
where id = 'b8fdcfb2-4ace-586f-b47f-28cd0a906ca5'::uuid
  and usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
  and conta_destino_id = '70c10a6f-1882-5411-858a-c465dacecf29'::uuid;

-- A fonte permanece visível para organização, mas sem saldo, transações ou
-- participação no patrimônio e no planejamento.
update public.contas
set nome = 'Extrato Itaú',
    tipo = 'outro',
    instituicao = 'Itaú',
    cor = '#EC7000',
    saldo_inicial = 0,
    data_saldo_inicial = '2026-07-01'::date,
    incluir_no_patrimonio = false,
    ativa = true
where id = 'd64bb1b6-1140-5470-8695-7aadce45262c'::uuid
  and usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid;

delete from public.fontes_grupos_panorama
where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
  and fonte_tipo = 'conta'
  and fonte_id = 'd64bb1b6-1140-5470-8695-7aadce45262c'::uuid;

insert into public.grupos_fontes_panorama (
  id, usuario_id, nome, ordem, recolhido
)
values (
  'f8ab34c5-8949-5433-9458-9ddb9270526b'::uuid,
  'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid,
  'Extrato Itaú', 3, false
)
on conflict (id) do update
set nome = excluded.nome,
    ordem = excluded.ordem,
    recolhido = excluded.recolhido;

insert into public.fontes_grupos_panorama (
  id, usuario_id, grupo_id, fonte_tipo, fonte_id, ordem
)
values (
  'caaa4434-87d1-55db-be24-8e7726e1d990'::uuid,
  'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid,
  'f8ab34c5-8949-5433-9458-9ddb9270526b'::uuid,
  'conta', 'd64bb1b6-1140-5470-8695-7aadce45262c'::uuid, 0
)
on conflict (usuario_id, fonte_tipo, fonte_id) do update
set grupo_id = excluded.grupo_id,
    ordem = excluded.ordem;

-- Preserva somente os ajustes solicitados nas recorrências.
update public.recorrencias
set categoria_id = '95659a0a-60c8-4a4c-88c7-30b608ef802e'::uuid,
    conta_id = null,
    valor_estimado = 9455.96,
    metadados = metadados || $json${"ajuste_usuario":{"valor_anterior":"7500.00","valor_adicionado":"1955.96","valor_final":"9455.96"}}$json$::jsonb
where id = '6929d257-5bd0-4db4-b4f3-6371b76d476a'::uuid
  and usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid;

update public.recorrencias
set categoria_id = '76eb021f-5f19-5d0c-9fc4-9f1a1fbf2f87'::uuid,
    conta_id = null
where id in (
  '028366d0-4591-4667-9dc6-08ce9ed61148'::uuid,
  'a06de776-725f-460d-88b5-45cffed0c7a8'::uuid
)
  and usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid;

update public.recorrencias
set categoria_id = '520dd656-9326-5875-b2b7-a209efc414e3'::uuid,
    conta_id = null
where id in (
  '09227aa5-f3e3-40f8-bd7c-6a49f9d1f3f3'::uuid,
  'a0127352-6767-4b0d-b31c-8832521edb44'::uuid,
  'c4a988d2-e9d0-408d-90e9-b4a39e6355eb'::uuid,
  '5e9f6176-8292-4c1f-bea5-32283bd212c9'::uuid
)
  and usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid;

-- Mantém a organização visual que já existia no grupo Entradas, trocando
-- apenas as chaves antigas das recorrências pelas novas linhas de categoria.
update public.linhas_grupos_panorama
set fonte_chave = 'entradas:categoria:95659a0a-60c8-4a4c-88c7-30b608ef802e'
where id = 'fa469a79-0366-4312-87cc-14c7e373965a'::uuid
  and usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid;

update public.linhas_grupos_panorama
set fonte_chave = 'entradas:categoria:520dd656-9326-5875-b2b7-a209efc414e3'
where id = '45b0b668-e6a8-47d5-97ba-a172d69176e5'::uuid
  and usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid;

update public.linhas_grupos_panorama
set fonte_chave = 'entradas:categoria:76eb021f-5f19-5d0c-9fc4-9f1a1fbf2f87'
where id = '41d11fff-6d34-493e-98b0-664f0a56199f'::uuid
  and usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid;

do $$
declare
  quantidade_recorrencias integer;
  quantidade_linhas_entradas integer;
begin
  if exists (
    select 1
    from public.movimentacoes
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and metadados ->> 'importacao_lote' = 'itau-conta-filipe-2026-01-a-06'
  ) then
    raise exception 'Ainda existem lançamentos da importação detalhada do Itaú.';
  end if;

  if exists (
    select 1
    from public.movimentacoes
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and (
        conta_id = 'd64bb1b6-1140-5470-8695-7aadce45262c'::uuid
        or conta_destino_id = 'd64bb1b6-1140-5470-8695-7aadce45262c'::uuid
      )
  ) then
    raise exception 'A fonte neutra Extrato Itaú ainda possui movimentações.';
  end if;

  if not exists (
    select 1
    from public.contas
    where id = 'd64bb1b6-1140-5470-8695-7aadce45262c'::uuid
      and nome = 'Extrato Itaú'
      and saldo_inicial = 0
      and incluir_no_patrimonio = false
      and ativa = true
  ) then
    raise exception 'A fonte Extrato Itaú não ficou neutra.';
  end if;

  if not exists (
    select 1
    from public.fontes_grupos_panorama
    where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
      and grupo_id = 'f8ab34c5-8949-5433-9458-9ddb9270526b'::uuid
      and fonte_tipo = 'conta'
      and fonte_id = 'd64bb1b6-1140-5470-8695-7aadce45262c'::uuid
  ) then
    raise exception 'A fonte Extrato Itaú não foi colocada no grupo próprio.';
  end if;

  if not exists (
    select 1
    from public.movimentacoes
    where id = 'b8fdcfb2-4ace-586f-b47f-28cd0a906ca5'::uuid
      and conta_id = 'bbe5ac59-d57f-5149-842e-e4163f9bd0e2'::uuid
      and conta_destino_id = '70c10a6f-1882-5411-858a-c465dacecf29'::uuid
      and not (metadados ? 'contrapartida_itau')
  ) then
    raise exception 'A transferência do Mercado Pago não foi restaurada.';
  end if;

  select count(*)
  into quantidade_recorrencias
  from public.recorrencias
  where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
    and conta_id is null
    and (
      (id = '6929d257-5bd0-4db4-b4f3-6371b76d476a'::uuid
       and categoria_id = '95659a0a-60c8-4a4c-88c7-30b608ef802e'::uuid
       and valor_estimado = 9455.96)
      or (id in (
            '028366d0-4591-4667-9dc6-08ce9ed61148'::uuid,
            'a06de776-725f-460d-88b5-45cffed0c7a8'::uuid
          )
          and categoria_id = '76eb021f-5f19-5d0c-9fc4-9f1a1fbf2f87'::uuid)
      or (id in (
            '09227aa5-f3e3-40f8-bd7c-6a49f9d1f3f3'::uuid,
            'a0127352-6767-4b0d-b31c-8832521edb44'::uuid,
            'c4a988d2-e9d0-408d-90e9-b4a39e6355eb'::uuid,
            '5e9f6176-8292-4c1f-bea5-32283bd212c9'::uuid
          )
          and categoria_id = '520dd656-9326-5875-b2b7-a209efc414e3'::uuid)
    );

  if quantidade_recorrencias <> 7 then
    raise exception 'As recorrências de Salário, Décimo terceiro e PLR não foram preservadas.';
  end if;

  select count(*)
  into quantidade_linhas_entradas
  from public.linhas_grupos_panorama
  where usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'::uuid
    and grupo_id = '1f3cbd79-d4b8-4f2b-b74f-dbfc16469bd6'::uuid
    and fonte_chave in (
      'entradas:categoria:95659a0a-60c8-4a4c-88c7-30b608ef802e',
      'entradas:categoria:520dd656-9326-5875-b2b7-a209efc414e3',
      'entradas:categoria:76eb021f-5f19-5d0c-9fc4-9f1a1fbf2f87'
    );

  if quantidade_linhas_entradas <> 3 then
    raise exception 'As três linhas de receita não ficaram no grupo Entradas.';
  end if;
end;
$$;

commit;
