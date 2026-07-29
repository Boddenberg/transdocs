begin;

-- A fotinha de cada atividade — o que o cartão do cômodo mostra antes do nome.
-- Guardada como caminho no Storage, no mesmo bucket privado das capturas, sob
-- o prefixo `icones/`: a coluna nunca carrega bytes, só o ponteiro e o mime,
-- como na foto de perfil.
alter table public.catalogo_atividades_casa
  add column if not exists icone_caminho text,
  add column if not exists icone_mime text;

-- A marcação rápida: um toque no cartão do cômodo diz "feito" e vira registro,
-- sem passar pela câmera. A foto continua obrigatória no fluxo completo — o que
-- muda é que ela deixa de ser a única porta de entrada, e por isso a captura
-- passa a ser opcional na linha do registro.
--
-- A restrição de unicidade continua valendo e não atrapalha: em Postgres, nulo
-- não conflita com nulo, então quantas marcações rápidas se quiser.
alter table public.registros_atividades_casa
  alter column captura_id drop not null;

commit;
