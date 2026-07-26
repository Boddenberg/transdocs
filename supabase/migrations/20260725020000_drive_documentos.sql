begin;

-- Drive de documentos da vida ------------------------------------------------
--
-- `documentos_financeiros` nasceu para os papeis que sustentam os numeros:
-- extrato, fatura, holerite, comprovante. So que a gaveta de casa e maior que
-- isso — RG, passaporte, contrato de aluguel, apolice do seguro, ticket do
-- cruzeiro. O drive passa a guardar tudo, e a tabela ganha a taxonomia da
-- vida ao lado da financeira (que continua intacta, alimentando a captura).
--
-- `tipo` continua sendo o que a IA da captura usa para ler dinheiro no
-- arquivo. `categoria` e a prateleira do drive — e as duas convivem: uma
-- fatura e `tipo=fatura` e `categoria=financeiro` ao mesmo tempo.
alter table public.documentos_financeiros
  add column if not exists categoria text not null default 'outros'
    check (categoria in (
      'identificacao', 'contratos', 'financeiro', 'moradia', 'veiculo',
      'viagens', 'saude', 'seguros', 'trabalho', 'estudos', 'outros'
    )),
  -- Uma linha dizendo o que e o documento, escrita pela IA na leitura do
  -- upload ou pela pessoa na ficha. E o que aparece embaixo do nome no drive.
  add column if not exists descricao text
    check (descricao is null or char_length(descricao) between 1 and 400),
  -- O que vence: passaporte, CNH, apolice, contrato de aluguel. Sem isso o
  -- drive seria so um deposito; com isso ele avisa antes de virar problema.
  add column if not exists validade date,
  add column if not exists favorito boolean not null default false,
  add column if not exists etiquetas text[] not null default '{}'::text[];

-- Os documentos que ja existiam entram na prateleira que combina com o tipo
-- financeiro deles, em vez de caírem todos em "outros".
update public.documentos_financeiros
   set categoria = case tipo
     when 'divida' then 'contratos'
     when 'outro' then 'outros'
     else 'financeiro'
   end
 where categoria = 'outros';

create index if not exists documentos_categoria_idx
  on public.documentos_financeiros (usuario_id, categoria, criado_em desc);

-- Parcial: so quem tem data de validade interessa para o aviso de vencimento.
create index if not exists documentos_validade_idx
  on public.documentos_financeiros (usuario_id, validade)
  where validade is not null;

create index if not exists documentos_favorito_idx
  on public.documentos_financeiros (usuario_id, criado_em desc)
  where favorito;

commit;
