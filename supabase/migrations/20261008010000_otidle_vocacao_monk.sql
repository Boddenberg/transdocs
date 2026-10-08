-- O Monk, a quinta vocação do OT Idle: o check de 20261007010000 só aceitava
-- as quatro clássicas, e criar um personagem pelo caminho dos punhos dava erro.

alter table public.otidle_personagens
  drop constraint if exists otidle_personagens_vocacao_check;

alter table public.otidle_personagens
  add constraint otidle_personagens_vocacao_check
  check (vocacao in ('cavaleiro', 'paladino', 'feiticeiro', 'druida', 'monge'));
