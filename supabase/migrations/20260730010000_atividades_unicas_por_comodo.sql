begin;

-- O catálogo antigo ligava a mesma atividade a vários cômodos. Ele fica
-- arquivado para preservar os registros históricos, enquanto a residência
-- recompõe manualmente o catálogo ativo.
update public.catalogo_atividades_casa
set
  status = 'arquivada',
  atualizado_em = now()
where status = 'ativa';

delete from public.ambientes_catalogo_atividades_casa;

-- Uma atividade pode ser geral (sem linha nesta tabela) ou de um único cômodo.
-- A garantia no banco evita que integrações futuras reintroduzam o
-- compartilhamento mesmo que não passem pela API.
alter table public.ambientes_catalogo_atividades_casa
  add constraint ambientes_catalogo_atividade_unico unique (atividade_id);

commit;
