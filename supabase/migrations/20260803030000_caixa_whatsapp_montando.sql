begin;

-- ------------------------------------------- a resposta so aparece inteira
--
-- O bug: a resposta com anexo entrava na caixa em dois passos. Primeiro a
-- linha de `caixa_whatsapp`, ja com `status = 'pendente'` — e portanto ja
-- visivel para a ponte —, e so depois as linhas de base64 em
-- `anexos_caixa_whatsapp`. A ponte le a caixa a cada dois segundos, e subir
-- tres PDFs em base64 leva mais do que isso.
--
-- No intervalo, ela lia uma mensagem cujo `anexos` ainda era `[]`, mandava o
-- texto sozinho e confirmava a entrega. Quando os anexos chegavam, a linha ja
-- estava `entregue` e ninguem mais a leria. Nao havia erro em lugar nenhum:
-- o backend tinha os bytes na mao (por isso a frase dizia "enviei os 3
-- arquivos") e a ponte fez exatamente o que a caixa mostrou.
--
-- O conserto e um estado a mais. Uma resposta com anexo nasce `montando`, que
-- a leitura nao enxerga, e so vira `pendente` depois que os bytes estao
-- gravados. A ponte continua sem saber que isto existe — `ler_caixa_whatsapp`
-- ja filtra por `pendente` e nao muda nem de assinatura.
alter table public.caixa_whatsapp
  drop constraint if exists caixa_whatsapp_status_check;

alter table public.caixa_whatsapp
  add constraint caixa_whatsapp_status_check
  check (status in ('montando', 'pendente', 'entregue', 'descartada'));

-- A varredura do pulso precisa achar o que ficou meio montado quando o
-- processo morreu entre os dois passos. Sem indice, isso e um seq scan a cada
-- batida da ponte.
create index if not exists caixa_whatsapp_montando_idx
  on public.caixa_whatsapp (ponte_id, criada_em)
  where status = 'montando';

commit;
