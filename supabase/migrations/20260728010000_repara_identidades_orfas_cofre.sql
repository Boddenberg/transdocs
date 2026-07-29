begin;

-- Duas criacoes do Cofre chegaram a gravar a identidade, mas falharam antes do
-- primeiro guarda por causa do UPSERT contra o indice unico parcial. Sem guarda
-- nao existe chave capaz de abrir essa identidade; sem item nem envelope tambem
-- nao existe conteudo a preservar. Devolver somente esses casos ao primeiro uso
-- permite que o navegador gere um novo par de chaves e mostre o codigo.
delete from public.cofre_identidades identidade
where not exists (
  select 1
  from public.cofre_guardas guarda
  where guarda.usuario_id = identidade.usuario_id
)
and not exists (
  select 1
  from public.cofre_itens item
  where item.usuario_id = identidade.usuario_id
)
and not exists (
  select 1
  from public.cofre_envelopes envelope
  where envelope.usuario_id = identidade.usuario_id
);

commit;
