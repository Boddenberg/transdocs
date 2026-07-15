begin;

alter table public.preenchimentos
  add column if not exists instrucoes_negociacao text not null default '';

alter table public.preenchimentos
  drop constraint if exists preenchimentos_instrucoes_negociacao_check;

alter table public.preenchimentos
  add constraint preenchimentos_instrucoes_negociacao_check
  check (char_length(instrucoes_negociacao) <= 8000);

alter table public.preenchimentos_fontes
  drop constraint if exists preenchimentos_fontes_categoria_check;

alter table public.preenchimentos_fontes
  add constraint preenchimentos_fontes_categoria_check
  check (categoria in (
    'documentos_caso', 'documentos_partes', 'estado_civil', 'enderecos',
    'matricula_imovel', 'cadastro_municipal', 'cndt', 'itbi',
    'indisponibilidade', 'arquivamentos'
  ));

commit;
