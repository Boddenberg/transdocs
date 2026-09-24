-- Retenção curta na observabilidade.
--
-- Em 20/09/2026 o banco parou: o disco encheu e o Postgres entrou em laço de
-- recuperação por quatro dias. O que o encheu foi `obs_llm_chamadas` com 5,1
-- milhões de linhas — regravação de lote, já corrigida no escritor. Mas a
-- janela de 90 dias foi cúmplice: enquanto o defeito duplicava, nada saía.
--
-- Os prazos abaixo são o que cabe num projeto desta escala. Eles respondem à
-- pergunta que essas tabelas existem para responder — "como o hub se comportou
-- ultimamente?" —, e não a uma auditoria histórica: para isso existe
-- `obs_rollup_horario`, que é agregado, minúsculo e continua com 400 dias.
--
-- As notas continuam durando o mesmo que as chamadas que as geraram (30 dias):
-- uma nota sem a chamada ao lado não responde nada. Os spans duram menos que
-- todo o resto (7 dias) porque são o volume — uma dezena por interação — e são
-- olhados no dia em que alguma coisa deu errado, não um mês depois.

begin;

create or replace function public.obs_expurgar()
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.obs_spans where inicio < now() - interval '7 days';
  delete from public.obs_llm_chamadas where criado_em < now() - interval '30 days';
  delete from public.obs_avaliacoes where avaliada_em < now() - interval '30 days';
  delete from public.obs_interacoes where inicio < now() - interval '30 days';
  delete from public.obs_erros where ultima_ocorrencia < now() - interval '90 days';
  delete from public.obs_saude where hora < now() - interval '90 days';
  delete from public.obs_rollup_horario where hora < now() - interval '400 days';
$$;

revoke all on function public.obs_expurgar() from public, anon, authenticated;

commit;
