-- A Casa deixa de mandar um fechamento todos os dias. Permanecem o panorama
-- semanal e o panorama mensal no primeiro dia do mês.

alter table public.configuracoes_whatsapp_casa
  alter column resumo_diario_ativo set default false;

update public.configuracoes_whatsapp_casa
   set resumo_diario_ativo = false,
       panorama_semanal_ativo = true,
       panorama_mensal_ativo = true,
       panorama_mensal_dia = 1,
       atualizada_em = now()
 where resumo_diario_ativo is distinct from false
    or panorama_semanal_ativo is distinct from true
    or panorama_mensal_ativo is distinct from true
    or panorama_mensal_dia is distinct from 1;

-- Se a ponte esteve desligada, pode haver resumos diários esperando na caixa.
-- Descartá-los faz a nova preferência valer já no primeiro reinício.
update public.mensagens_whatsapp_casa
   set status = 'descartada',
       erro = 'Resumo diário desativado pela configuração da Casa.'
 where tipo = 'resumo_diario'
   and status = 'pendente';
