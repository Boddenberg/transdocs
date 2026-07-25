-- Culinaria: o caderno de receitas sai do codigo e vira dado do casal, com a
-- camada de IA que so existe porque o app tem dado proprio (nota fiscal, diario
-- de bordo, historico do casal e do mes).
--
-- Cinco tabelas e uma funcao:
--   receitas_culinaria   — o caderno. Receita transcrita pela IA nasce com
--                          `revisada = false` e as duvidas marcadas; nada entra
--                          no acervo sem o usuario confirmar (mesma regra da
--                          nota fiscal).
--   diario_culinaria     — o que foi comido/cozinhado, com a nota de quem
--                          cozinhou ("metade da pimenta"). E dele que sai o
--                          gosto aprendido e a leitura mensal.
--   cardapios_culinaria  — o menu proposto para uma semana, editavel.
--   recusas_culinaria    — "nao, outra": o prato recusado nao volta na mesma
--                          noite e o historico vira sinal de preferencia.
--   respostas_cozinha    — cache das respostas de IA por assinatura de entrada.
--                          Uma so tabela porque o padrao e um so: guardar o
--                          resultado enquanto a entrada nao mudou, para nao
--                          pagar duas vezes pela mesma pergunta.
--
-- O caderno e do casal: as consultas do backend leem as receitas do usuario E
-- do parceiro, entao a policy libera as duas pontas do vinculo ativo.

begin;

-- ------------------------------------------------------------------ receitas
create table if not exists public.receitas_culinaria (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  slug text not null check (slug ~ '^[a-z0-9-]{1,120}$'),
  titulo text not null check (char_length(titulo) between 1 and 200),
  resumo text not null default '' check (char_length(resumo) <= 400),
  categoria text not null default 'Prato principal',
  momento text not null default 'dia a dia' check (momento in ('dia a dia', 'especial')),
  dificuldade text not null default 'Fácil',
  tempo text not null default '' check (char_length(tempo) <= 60),
  -- Minutos estimados a partir de `tempo`: e o que a decisao rapida compara
  -- ("20h40 de uma terca pede algo de 20 minutos"). Texto nao da para ordenar.
  tempo_minutos integer check (tempo_minutos is null or tempo_minutos between 0 and 6000),
  rendimento text not null default '' check (char_length(rendimento) <= 80),
  porcoes integer check (porcoes is null or porcoes between 1 and 200),
  fonte text not null default '' check (char_length(fonte) <= 200),
  fonte_url text,
  video_id text check (video_id is null or char_length(video_id) <= 40),
  -- Foto original do papel amarelado / do prato, guardada ao lado da receita.
  documento_id uuid references public.documentos_financeiros(id) on delete set null,
  ingredientes jsonb not null default '[]'::jsonb,
  preparo jsonb not null default '[]'::jsonb,
  notas jsonb not null default '[]'::jsonb,
  -- 'manual' | 'transcricao' | 'catalogo'. Transcricao guarda o que a IA nao
  -- teve certeza em `duvidas` para a tela pedir revisao campo a campo.
  origem text not null default 'manual'
    check (origem in ('manual', 'transcricao', 'catalogo')),
  duvidas jsonb not null default '[]'::jsonb,
  revisada boolean not null default true,
  modelo_ia text,
  -- Busca em linguagem natural: um vetor por receita, custo unico por receita.
  embedding vector(1536),
  embedding_modelo text,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create unique index if not exists receitas_culinaria_slug_idx
  on public.receitas_culinaria (usuario_id, slug);
create index if not exists receitas_culinaria_usuario_idx
  on public.receitas_culinaria (usuario_id, revisada, atualizado_em desc);
create index if not exists receitas_culinaria_embedding_idx
  on public.receitas_culinaria using hnsw (embedding vector_cosine_ops);

-- -------------------------------------------------------------------- diario
create table if not exists public.diario_culinaria (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  receita_id uuid references public.receitas_culinaria(id) on delete set null,
  data date not null,
  -- 'cozinhado' e a receita feita em casa; 'delivery' e 'fora' entram porque a
  -- leitura mensal precisa saber quantas tercas viraram pedido.
  tipo text not null default 'cozinhado'
    check (tipo in ('cozinhado', 'delivery', 'fora')),
  -- Quando nao ha receita no caderno ("pizza da esquina"), o titulo diz o que foi.
  titulo text not null check (char_length(titulo) between 1 and 200),
  -- O ajuste de quem cozinhou: "metade da pimenta", "sem coentro". E a materia
  -- prima do gosto aprendido.
  nota text check (nota is null or char_length(nota) <= 600),
  avaliacao smallint check (avaliacao is null or avaliacao between 1 and 5),
  quem_cozinhou text check (quem_cozinhou is null or char_length(quem_cozinhou) <= 80),
  criado_em timestamptz not null default now()
);

create index if not exists diario_culinaria_usuario_data_idx
  on public.diario_culinaria (usuario_id, data desc);
create index if not exists diario_culinaria_receita_idx
  on public.diario_culinaria (receita_id, data desc);

-- ------------------------------------------------------------------ cardapio
create table if not exists public.cardapios_culinaria (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  -- Segunda-feira da semana proposta.
  semana_inicio date not null,
  dias jsonb not null default '[]'::jsonb,
  observacao text check (observacao is null or char_length(observacao) <= 600),
  modelo_ia text,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create unique index if not exists cardapios_culinaria_semana_idx
  on public.cardapios_culinaria (usuario_id, semana_inicio);

-- ------------------------------------------------------------------- recusas
create table if not exists public.recusas_culinaria (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  receita_id uuid not null references public.receitas_culinaria(id) on delete cascade,
  data date not null,
  criado_em timestamptz not null default now()
);

-- Recusar o mesmo prato duas vezes na mesma noite e a mesma recusa.
create unique index if not exists recusas_culinaria_dia_idx
  on public.recusas_culinaria (usuario_id, receita_id, data);
create index if not exists recusas_culinaria_usuario_idx
  on public.recusas_culinaria (usuario_id, data desc);

-- ------------------------------------------------- cache das respostas de IA
-- `chave` identifica a pergunta (a data da sugestao, "slug|cognac" para a
-- substituicao, "2026-07" para a leitura do mes). `assinatura` e o resumo das
-- entradas que, se mudarem, invalidam a resposta guardada. `expira_em` cobre o
-- que envelhece sozinho (a sugestao vale por uma hora); substituicao nao expira.
create table if not exists public.respostas_cozinha (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  tipo text not null check (char_length(tipo) between 1 and 40),
  chave text not null check (char_length(chave) between 1 and 300),
  assinatura text not null default '',
  conteudo jsonb not null,
  modelo_ia text,
  criado_em timestamptz not null default now(),
  expira_em timestamptz
);

create unique index if not exists respostas_cozinha_chave_idx
  on public.respostas_cozinha (usuario_id, tipo, chave);

-- ----------------------------------------------------------------------- RLS
alter table public.receitas_culinaria enable row level security;
alter table public.receitas_culinaria force row level security;
alter table public.diario_culinaria enable row level security;
alter table public.diario_culinaria force row level security;
alter table public.cardapios_culinaria enable row level security;
alter table public.cardapios_culinaria force row level security;
alter table public.recusas_culinaria enable row level security;
alter table public.recusas_culinaria force row level security;
alter table public.respostas_cozinha enable row level security;
alter table public.respostas_cozinha force row level security;

-- O caderno de receitas e de vocês dois: quem tem vinculo ativo le e escreve no
-- mesmo acervo. O diario, as recusas e o cache continuam pessoais — sao o
-- registro de quem cozinhou e o custo de quem perguntou.
create or replace function public.e_do_casal_culinaria(dono uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select dono = (select auth.uid())
     or exists (
       select 1 from public.vinculos_casal v
       where v.status = 'ativo'
         and (
           (v.criador_id = dono and v.parceiro_id = (select auth.uid()))
           or (v.parceiro_id = dono and v.criador_id = (select auth.uid()))
         )
     );
$$;

drop policy if exists receitas_culinaria_do_casal on public.receitas_culinaria;
create policy receitas_culinaria_do_casal on public.receitas_culinaria
for all to authenticated
using (public.e_do_casal_culinaria(usuario_id))
with check ((select auth.uid()) = usuario_id);

drop policy if exists diario_culinaria_do_casal on public.diario_culinaria;
create policy diario_culinaria_do_casal on public.diario_culinaria
for all to authenticated
using (public.e_do_casal_culinaria(usuario_id))
with check ((select auth.uid()) = usuario_id);

drop policy if exists cardapios_culinaria_do_casal on public.cardapios_culinaria;
create policy cardapios_culinaria_do_casal on public.cardapios_culinaria
for all to authenticated
using (public.e_do_casal_culinaria(usuario_id))
with check ((select auth.uid()) = usuario_id);

drop policy if exists recusas_culinaria_do_usuario on public.recusas_culinaria;
create policy recusas_culinaria_do_usuario on public.recusas_culinaria
for all to authenticated
using ((select auth.uid()) = usuario_id)
with check ((select auth.uid()) = usuario_id);

drop policy if exists respostas_cozinha_do_usuario on public.respostas_cozinha;
create policy respostas_cozinha_do_usuario on public.respostas_cozinha
for all to authenticated
using ((select auth.uid()) = usuario_id)
with check ((select auth.uid()) = usuario_id);

revoke all on public.receitas_culinaria from anon;
revoke all on public.diario_culinaria from anon;
revoke all on public.cardapios_culinaria from anon;
revoke all on public.recusas_culinaria from anon;
revoke all on public.respostas_cozinha from anon;
grant select, insert, update, delete on public.receitas_culinaria to authenticated;
grant select, insert, update, delete on public.diario_culinaria to authenticated;
grant select, insert, update, delete on public.cardapios_culinaria to authenticated;
grant select, insert, update, delete on public.recusas_culinaria to authenticated;
grant select, insert, update, delete on public.respostas_cozinha to authenticated;
revoke all on function public.e_do_casal_culinaria(uuid) from anon;
grant execute on function public.e_do_casal_culinaria(uuid) to authenticated, service_role;

-- ------------------------------------------------- busca em linguagem natural
-- "algo rapido, sem forno, que agrade visita": a pergunta vira vetor e a
-- distancia responde. O backend usa a service role, por isso a lista de donos
-- (usuario + parceiro) vem explicita em vez de sair da RLS.
create or replace function public.match_receitas_culinaria(
  consulta vector(1536),
  donos uuid[],
  limite integer default 8
)
returns table (
  id uuid,
  slug text,
  titulo text,
  distancia double precision
)
language sql
stable
as $$
  select r.id, r.slug, r.titulo, (r.embedding <=> consulta) as distancia
  from public.receitas_culinaria r
  where r.usuario_id = any(donos)
    and r.revisada
    and r.embedding is not null
  order by r.embedding <=> consulta
  limit greatest(limite, 1);
$$;

revoke all on function public.match_receitas_culinaria(vector, uuid[], integer) from anon;
grant execute on function public.match_receitas_culinaria(vector, uuid[], integer)
  to authenticated, service_role;

commit;
