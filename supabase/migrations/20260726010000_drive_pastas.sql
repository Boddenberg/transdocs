begin;

-- Pastas dentro das prateleiras do drive ------------------------------------
--
-- A gaveta tinha 11 prateleiras fixas e nada abaixo delas: "Moradia" com 40
-- papeis vira uma pilha. As pastas sao o segundo nivel, e quem as cria de
-- verdade e a IA — ela le o arquivo e decide que ele pertence ao "Apartamento
-- Rua X" ou ao "Fiat Argo 2022". A prateleira continua sendo a raiz porque e
-- o vocabulario que o RAG, o /app/documentos e a captura financeira ja usam.
--
-- `criada_por` e o que sustenta a regra combinada: pasta vazia so existe se
-- foi feita na mao. A pasta da IA nasce com um documento dentro e some quando
-- esvazia; a da pessoa fica de pe mesmo vazia, esperando o papel que vai
-- chegar.
create table if not exists public.pastas_documentos (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  nome text not null check (char_length(nome) between 1 and 80),
  -- A prateleira raiz. Espelha o check de documentos_financeiros.categoria.
  categoria text not null check (categoria in (
    'identificacao', 'contratos', 'financeiro', 'moradia', 'veiculo',
    'viagens', 'saude', 'seguros', 'trabalho', 'estudos', 'outros'
  )),
  -- Subpasta de outra pasta. Nulo = pasta no primeiro nivel da prateleira.
  pai_id uuid references public.pastas_documentos(id) on delete cascade,
  criada_por text not null default 'pessoa'
    check (criada_por in ('ia', 'pessoa')),
  criada_em timestamptz not null default now()
);

-- Duas pastas com o mesmo nome no mesmo lugar seriam indistinguiveis na tela —
-- e a IA, que resolve o destino procurando pelo nome, escolheria uma das duas
-- ao acaso. `coalesce` porque unique nao trata NULLs como iguais.
create unique index if not exists pastas_documentos_nome_idx
  on public.pastas_documentos (
    usuario_id,
    categoria,
    coalesce(pai_id, '00000000-0000-0000-0000-000000000000'::uuid),
    lower(nome)
  );

create index if not exists pastas_documentos_usuario_idx
  on public.pastas_documentos (usuario_id, categoria, criada_em);

alter table public.pastas_documentos enable row level security;
alter table public.pastas_documentos force row level security;

drop policy if exists pastas_do_proprio_usuario on public.pastas_documentos;
create policy pastas_do_proprio_usuario on public.pastas_documentos
for all to authenticated
using ((select auth.uid()) = usuario_id)
with check ((select auth.uid()) = usuario_id);

revoke all on public.pastas_documentos from anon;
grant select, insert, update, delete on public.pastas_documentos to authenticated;

alter table public.documentos_financeiros
  -- Documento sem pasta fica solto na raiz da prateleira: e o estado normal de
  -- quem nao pertence a nenhum conjunto (um RG nao precisa de pasta).
  add column if not exists pasta_id uuid
    references public.pastas_documentos(id) on delete set null,
  -- Quem arrumou este documento.
  --   pendente = a IA nunca tocou (e o mutirao ainda pode propor);
  --   ia       = a IA nomeou e arquivou;
  --   pessoa   = o dono mexeu na mao, e isso e soberano — a IA nao volta aqui.
  add column if not exists organizacao text not null default 'pendente'
    check (organizacao in ('pendente', 'ia', 'pessoa'));

-- Quem ja tem nome de exibicao passou pela leitura da IA em algum upload.
-- Marcar isso agora evita que o primeiro mutirao proponha rearrumar o que ja
-- estava arrumado.
update public.documentos_financeiros
   set organizacao = 'ia'
 where organizacao = 'pendente'
   and nome_exibicao is not null;

create index if not exists documentos_pasta_idx
  on public.documentos_financeiros (usuario_id, pasta_id, criado_em desc);

-- Parcial: o mutirao so olha o que esta pendente, e essa lista tende a ser
-- curta perto da gaveta inteira.
create index if not exists documentos_organizacao_pendente_idx
  on public.documentos_financeiros (usuario_id, criado_em)
  where organizacao = 'pendente';

commit;
