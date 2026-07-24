-- Nome de exibicao do item de consumo: um rotulo curto e familiar ("Hidratante
-- Johnson's") ao lado da descricao original da nota ("HIDRAT JOHNSONS SOFT
-- 200ML"). A IA preenche na leitura; a descricao original continua guardada.

begin;

alter table public.itens_consumo
  add column if not exists nome_exibicao text;

commit;
