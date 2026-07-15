begin;

alter table public.preenchimentos
  add column if not exists dados_negociacao jsonb;

alter table public.preenchimentos
  drop constraint if exists preenchimentos_instrucoes_negociacao_check;

alter table public.preenchimentos
  add constraint preenchimentos_instrucoes_negociacao_check
  check (char_length(instrucoes_negociacao) <= 20000);

alter table public.preenchimentos
  drop constraint if exists preenchimentos_dados_negociacao_objeto_check;

alter table public.preenchimentos
  add constraint preenchimentos_dados_negociacao_objeto_check
  check (dados_negociacao is null or jsonb_typeof(dados_negociacao) = 'object');

alter table public.preenchimentos_fontes
  drop constraint if exists preenchimentos_fontes_categoria_check;

alter table public.preenchimentos_fontes
  add constraint preenchimentos_fontes_categoria_check
  check (categoria in (
    'documentos_caso', 'documentos_partes', 'documentos_vendedores',
    'documentos_compradores', 'estado_civil', 'enderecos', 'matricula_imovel',
    'cadastro_municipal', 'valor_venal', 'cndt', 'itbi', 'indisponibilidade',
    'arquivamentos'
  ));

commit;
