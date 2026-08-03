begin;

-- A tabela enviada pelo casal passa a ser a régua da Casa. O valor informado é
-- sempre P; M mantém o gesto já adotado pelo app (+100%) e G vale +200% sobre P.
create temporary table nova_pontuacao_casa (
  comodo text not null,
  atividade text not null,
  pontos_p numeric(8, 2) not null check (pontos_p > 0),
  primary key (comodo, atividade)
) on commit drop;

insert into nova_pontuacao_casa (comodo, atividade, pontos_p)
values
  ('Cozinha', 'Limpar os armários', 60),
  ('Cozinha', 'Limpar a air fryer', 30),
  ('Cozinha', 'Limpar o fogão', 25),
  ('Cozinha', 'Limpar o micro-ondas', 15),
  ('Cozinha', 'Limpar a pia', 10),
  ('Cozinha', 'Colocar louça na lava-louça', 15),
  ('Cozinha', 'Retirar louça da lava-louça', 10),
  ('Cozinha', 'Limpar a lava-louça', 30),
  ('Cozinha', 'Limpar a geladeira por fora', 10),
  ('Cozinha', 'Limpar a geladeira por dentro', 50),
  ('Cozinha', 'Fazer marmita', 100),
  ('Cozinha', 'Fazer janta', 45),
  ('Cozinha', 'Fazer sobremesa', 30),
  ('Cozinha', 'Limpar o filtro', 10),
  ('Cozinha', 'Arrumar a gaveta de temperos', 25),
  ('Cozinha', 'Limpar a gaveta de talheres', 15),
  ('Sala', 'Colocar comida e água', 5),
  ('Sala', 'Passar aspirador', 20),
  ('Sala', 'Varrer', 15),
  ('Sala', 'Passar pano', 20),
  ('Sala', 'Limpar a mesa', 10),
  ('Sala', 'Limpar o rack', 10),
  ('Sala', 'Limpar a janela', 25),
  ('Sala', 'Molhar a planta', 5),
  ('Sala', 'Aspirar o sofá', 20),
  ('Sala', 'Limpar embaixo do sofá', 40),
  ('Sala', 'Limpar o canto alemão', 25),
  ('Sala', 'Limpar o espelho', 10),
  ('Sala', 'Passar pano na estante', 10),
  ('Nosso quarto', 'Trocar lençol', 20),
  ('Nosso quarto', 'Passar aspirador', 15),
  ('Nosso quarto', 'Varrer', 10),
  ('Nosso quarto', 'Limpar a janela', 20),
  ('Nosso quarto', 'Limpar o guarda-roupa', 45),
  ('Corredor', 'Varrer', 5),
  ('Corredor', 'Limpar o rodapé', 20),
  ('Corredor', 'Passar aspirador', 5),
  ('Corredor', 'Passar pano', 10),
  ('Banheiro', 'Tirar o lixo', 5),
  ('Banheiro', 'Limpar o vaso', 30),
  ('Banheiro', 'Trocar o tapete', 5),
  ('Banheiro', 'Limpar o box', 40),
  ('Banheiro', 'Limpar a pia', 15),
  ('Banheiro', 'Limpar o chão', 20),
  ('Lavabo', 'Recolher o lixo', 5),
  ('Lavabo', 'Limpar o vaso', 20),
  ('Lavabo', 'Limpar o chão', 10),
  ('Lavabo', 'Limpar o espelho', 5),
  ('Área de serviço', 'Lavar lençol do quarto', 10),
  ('Área de serviço', 'Tirar coco do cachorro', 10),
  ('Área de serviço', 'Estender lençol do quarto', 15),
  ('Área de serviço', 'Lavar cobertor dos cachorros', 10),
  ('Área de serviço', 'Estender cobertor dos cachorros', 15),
  ('Área de serviço', 'Lavar nossos cobertores', 20),
  ('Área de serviço', 'Estender nossos cobertores', 25),
  ('Área de serviço', 'Lavar pano de prato', 5),
  ('Área de serviço', 'Estender pano de prato', 5),
  ('Área de serviço', 'Lavar toalha de banho', 10),
  ('Área de serviço', 'Estender toalha de banho', 15),
  ('Área de serviço', 'Lavar pano de chão', 10),
  ('Área de serviço', 'Estender pano de chão', 10),
  ('Área de serviço', 'Trocar o tapetinho do cachorro', 10),
  ('Área de serviço', 'Tirar o lixo', 10),
  ('Área de serviço', 'Colocar saco de lixo na lixeira', 5),
  ('Área de serviço', 'Dar banho no cachorro', 45),
  ('Área de serviço', 'Cortar a unha do cachorro', 25),
  ('Área de serviço', 'Lavar a caminha do cachorro', 25);

do $$
declare
  alvo uuid;
  executor uuid;
  candidatos integer;
  atividades_atualizadas integer;
  registros_esperados integer;
  auditorias_criadas integer;
  registros_zerados integer;
  marco timestamptz := now();
  motivo text := 'Reinício da pontuação da Casa solicitado em 03/08/2026.';
begin
  -- O alvo é reconhecido pelo catálogo inteiro, não por nome de pessoa nem por
  -- um UUID privado gravado no histórico. Se houver zero ou dois candidatos, a
  -- migration para antes de tocar em qualquer residência.
  with catalogos_compativeis as (
    select atividade.vinculo_id
      from public.catalogo_atividades_casa as atividade
      join public.ambientes_catalogo_atividades_casa as ligacao
        on ligacao.atividade_id = atividade.id
      join public.ambientes_atividades_casa as ambiente
        on ambiente.id = ligacao.ambiente_id
      left join nova_pontuacao_casa as nova
        on nova.comodo = ambiente.nome
       and nova.atividade = atividade.nome
     where atividade.status = 'ativa'
       and ambiente.status = 'ativo'
     group by atividade.vinculo_id
    having count(*) = (select count(*) from nova_pontuacao_casa)
       and count(nova.atividade) = count(*)
       and count(distinct (ambiente.nome, atividade.nome)) = count(*)
  )
  select count(*), max(vinculo_id::text)::uuid
    into candidatos, alvo
    from catalogos_compativeis;

  if candidatos <> 1 then
    raise exception
      'Reinício da Casa recusado: esperava um catálogo compatível, encontrei %.',
      candidatos;
  end if;

  select vinculo.criador_id
    into strict executor
    from public.vinculos_casal as vinculo
   where vinculo.id = alvo
     and vinculo.status = 'ativo';

  update public.catalogo_atividades_casa as atividade
     set peso_base = nova.pontos_p,
         pontos_p = nova.pontos_p,
         pontos_m = nova.pontos_p * 2,
         pontos_g = nova.pontos_p * 3,
         atualizado_em = marco
    from public.ambientes_catalogo_atividades_casa as ligacao,
         public.ambientes_atividades_casa as ambiente,
         nova_pontuacao_casa as nova
   where atividade.vinculo_id = alvo
     and atividade.status = 'ativa'
     and ligacao.atividade_id = atividade.id
     and ambiente.id = ligacao.ambiente_id
     and ambiente.status = 'ativo'
     and nova.comodo = ambiente.nome
     and nova.atividade = atividade.nome;

  get diagnostics atividades_atualizadas = row_count;
  if atividades_atualizadas <> (select count(*) from nova_pontuacao_casa) then
    raise exception
      'Reinício da Casa recusado: esperava atualizar 67 atividades, atualizei %.',
      atividades_atualizadas;
  end if;

  select count(*)
    into registros_esperados
    from public.registros_atividades_casa as registro
   where registro.vinculo_id = alvo
     and registro.excluida_em is null;

  insert into public.auditoria_registros_atividades_casa (
    usuario_id,
    vinculo_id,
    registro_id,
    evento,
    dados_anteriores,
    dados_novos,
    justificativa,
    criado_em
  )
  select
    executor,
    registro.vinculo_id,
    registro.id,
    'exclusao',
    to_jsonb(registro) || jsonb_build_object(
      'participantes',
      coalesce(
        (
          select jsonb_agg(to_jsonb(participacao) order by participacao.criado_em)
            from public.participantes_registros_atividades_casa as participacao
           where participacao.registro_id = registro.id
        ),
        '[]'::jsonb
      )
    ),
    null,
    motivo,
    marco
  from public.registros_atividades_casa as registro
  where registro.vinculo_id = alvo
    and registro.excluida_em is null;

  get diagnostics auditorias_criadas = row_count;
  if auditorias_criadas <> registros_esperados then
    raise exception
      'Reinício da Casa recusado: esperava % auditorias, criei %.',
      registros_esperados,
      auditorias_criadas;
  end if;

  update public.registros_atividades_casa as registro
     set excluida_em = marco,
         excluida_por = executor,
         justificativa_exclusao = motivo,
         atualizado_em = marco
   where registro.vinculo_id = alvo
     and registro.excluida_em is null;

  get diagnostics registros_zerados = row_count;
  if registros_zerados <> registros_esperados then
    raise exception
      'Reinício da Casa recusado: esperava zerar % registros, zerei %.',
      registros_esperados,
      registros_zerados;
  end if;

  raise notice
    'Casa reiniciada: % atividades atualizadas e % registros zerados.',
    atividades_atualizadas,
    registros_zerados;
end;
$$;

commit;
