begin;

-- Os ambientes da Casa nasceram genéricos ("Quarto", "Escritório", "Banheiro do
-- casal") porque o catálogo inicial foi escrito antes de a planta existir. Agora
-- o painel desenha a casa de verdade e cada cômodo do desenho encontra o seu
-- ambiente pelo slug — então o catálogo passa a falar os nomes da planta.
--
-- É renomeação, não troca: o quarto do casal continua sendo a mesma linha, com
-- os mesmos vínculos de atividade e o mesmo histórico apontando para ela. Só o
-- "Escritório", que não existe nesta casa, sai de circulação — arquivado, nunca
-- apagado, para os registros antigos continuarem legíveis.

update public.ambientes_atividades_casa
set slug = 'nosso-quarto',
    nome = 'Nosso quarto',
    atualizado_em = now()
where slug = 'quarto'
  and not exists (
    select 1
    from public.ambientes_atividades_casa as existente
    where existente.vinculo_id = ambientes_atividades_casa.vinculo_id
      and existente.slug = 'nosso-quarto'
  );

update public.ambientes_atividades_casa
set slug = 'banheiro',
    nome = 'Banheiro',
    atualizado_em = now()
where slug = 'banheiro-casal'
  and not exists (
    select 1
    from public.ambientes_atividades_casa as existente
    where existente.vinculo_id = ambientes_atividades_casa.vinculo_id
      and existente.slug = 'banheiro'
  );

update public.ambientes_atividades_casa
set status = 'arquivado',
    atualizado_em = now()
where slug = 'escritorio'
  and status = 'ativo';

-- A ordem é a caminhada pela casa (sala → cozinha → serviço → corredor →
-- banheiros → quartos), a mesma de `AMBIENTES_INICIAIS`. Ela dita a sequência do
-- "Onde foi?" no registro, e as linhas renomeadas ainda carregam a ordem antiga.
update public.ambientes_atividades_casa as ambiente
set ordem = nova.ordem,
    atualizado_em = now()
from (
  values
    ('sala', 0),
    ('cozinha', 1),
    ('area-servico', 2),
    ('corredor', 3),
    ('banheiro', 4),
    ('lavabo', 5),
    ('nosso-quarto', 6),
    ('quarto-filipe', 7),
    ('quarto-victor', 8),
    ('todos-banheiros', 9),
    ('casa-toda', 10)
) as nova (slug, ordem)
where ambiente.slug = nova.slug
  and ambiente.ordem is distinct from nova.ordem;

commit;
