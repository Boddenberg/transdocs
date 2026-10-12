-- O recorde de pessoas no servidor, por servidor de jogo.
--
-- O aviso de recorde passou a contar pessoas (as contas que dividem aparelho
-- contam como uma), e o diario do jogo so guarda o pico de personagens com o
-- jogo aberto. O vigia guarda aqui o maior numero ja avisado, para o deploy do
-- backend nao recomecar a conta: { "beta": { "pessoas": 27, "em": "..." } }.

alter table public.quinteto_avisos
  add column if not exists recordes jsonb not null default '{}'::jsonb
    check (jsonb_typeof(recordes) = 'object');
