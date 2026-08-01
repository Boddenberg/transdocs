begin;

-- =====================================================================
-- Hospedagens: a vitrine das casas perto do aeroporto.
--
-- O sexto app do hub quebra uma premissa dos outros cinco: **parte dele e
-- lida por quem nao tem conta**. O site publico e a razao de o app existir —
-- alguem acha o anuncio no Google, olha as fotos e chama no WhatsApp.
--
-- Duas consequencias no desenho abaixo, as duas de proposito:
--
-- 1. **O bucket das fotos e publico.** Todos os outros buckets do projeto sao
--    privados com URL assinada de uma hora, porque guardam nota fiscal, foto
--    de perfil e retrato da casa. Aqui a foto E o produto: ela precisa de uma
--    URL estavel que o Google indexe, que o WhatsApp mostre na previa do link
--    e que sobreviva ao cache da pagina. Uma URL assinada expirando no meio de
--    uma pagina estatica seria uma vitrine com as fotos quebradas.
--
-- 2. **A vitrine e uma so, nao uma por pessoa.** As casas sao do casal, e a
--    area administrativa e compartilhada como o resto do hub. `usuario_id`
--    marca quem criou cada linha (e mantem o contrato do reset de dados), mas
--    o site publico le tudo o que estiver publicado, sem filtrar por pessoa.
--    Por isso `hospedagens_contato` e uma linha so, travada no id 'principal'.
--
-- Nao ha reserva, calendario, pagamento nem cadastro de hospede aqui. Se um
-- dia aparecer uma tabela com data de entrada e saida, o app deixou de ser uma
-- vitrine e a decisao precisa ser tomada de novo.
-- =====================================================================

create table public.hospedagens_acomodacoes (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  -- O slug e o endereco da casa no site e nunca muda sozinho: renomear o
  -- anuncio nao pode quebrar o link que ja foi mandado para alguem.
  slug text not null unique
    check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and char_length(slug) between 2 and 90),
  nome text not null check (char_length(nome) between 2 and 120),
  -- A frase do cartao: uma linha, a que faz a pessoa clicar.
  chamada text check (chamada is null or char_length(chamada) <= 240),
  descricao text check (descricao is null or char_length(descricao) <= 6000),
  -- Uma informacao por linha; a tela transforma em lista.
  informacoes text check (informacoes is null or char_length(informacoes) <= 4000),
  -- A localizacao dita em tempo, nunca em endereco. O endereco completo so vai
  -- pelo WhatsApp, depois da conversa — a coluna para ele nao existe aqui.
  referencia_local text check (referencia_local is null or char_length(referencia_local) <= 160),
  minutos_do_aeroporto integer check (
    minutos_do_aeroporto is null or minutos_do_aeroporto between 0 and 240
  ),
  capacidade_maxima integer not null default 2 check (capacidade_maxima between 1 and 60),
  quartos integer not null default 1 check (quartos between 0 and 30),
  camas integer not null default 1 check (camas between 0 and 60),
  banheiros integer not null default 1 check (banheiros between 0 and 30),
  -- Links opcionais, e so isso: nao ha integracao nenhuma com essas
  -- plataformas, nem sincronia de preco, nem de disponibilidade.
  link_airbnb text check (link_airbnb is null or link_airbnb ~* '^https://'),
  link_booking text check (link_booking is null or link_booking ~* '^https://'),
  estado text not null default 'rascunho'
    check (estado in ('rascunho', 'publicada', 'oculta')),
  ordem integer not null default 0 check (ordem >= 0),
  foto_capa_id uuid,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  publicado_em timestamptz,
  check (estado <> 'publicada' or publicado_em is not null)
);

create table public.hospedagens_fotos (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  acomodacao_id uuid not null
    references public.hospedagens_acomodacoes(id) on delete cascade,
  caminho text not null unique,
  mime text not null check (mime in ('image/jpeg', 'image/png', 'image/webp')),
  legenda text check (legenda is null or char_length(legenda) <= 160),
  ordem integer not null default 0 check (ordem >= 0),
  criado_em timestamptz not null default now()
);

-- A capa aponta para uma foto da propria acomodacao. `set null` e de proposito:
-- apagar a capa nao pode apagar o anuncio; a tela escolhe a proxima.
alter table public.hospedagens_acomodacoes
  add constraint hospedagens_acomodacoes_foto_capa_fkey
  foreign key (foto_capa_id) references public.hospedagens_fotos(id) on delete set null;

create table public.hospedagens_comodidades (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  acomodacao_id uuid not null
    references public.hospedagens_acomodacoes(id) on delete cascade,
  -- `chave` sai do catalogo do backend quando e uma comodidade conhecida
  -- (cozinha, wifi, estacionamento...) e ganha o icone certo na tela. Uma
  -- comodidade escrita a mao entra com chave 'livre' e vale pelo rotulo.
  chave text not null check (chave ~ '^[a-z0-9_]+$' and char_length(chave) <= 40),
  rotulo text check (rotulo is null or char_length(rotulo) <= 80),
  ordem integer not null default 0 check (ordem >= 0),
  criado_em timestamptz not null default now(),
  check (chave <> 'livre' or rotulo is not null)
);

-- Uma comodidade do catalogo nao se repete na mesma casa; as escritas a mao
-- podem, porque cada uma diz uma coisa diferente.
create unique index hospedagens_comodidades_unica_idx
  on public.hospedagens_comodidades (acomodacao_id, chave)
  where chave <> 'livre';

-- A vitrine e uma so. O check no id nao e enfeite: e o que impede a segunda
-- linha de existir e a pergunta "qual das duas o site usa?" de aparecer.
create table public.hospedagens_contato (
  id text primary key default 'principal' check (id = 'principal'),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  -- So digitos, com DDI. E assim que entra no link do wa.me.
  whatsapp text not null default '' check (whatsapp ~ '^[0-9]{0,15}$'),
  mensagem_padrao text check (mensagem_padrao is null or char_length(mensagem_padrao) <= 400),
  titulo text check (titulo is null or char_length(titulo) <= 120),
  subtitulo text check (subtitulo is null or char_length(subtitulo) <= 400),
  chamada_contato text check (chamada_contato is null or char_length(chamada_contato) <= 400),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

-- O site publico faz uma consulta so, e e esta: as casas publicadas na ordem
-- em que a pessoa escolheu mostrar.
create index hospedagens_acomodacoes_vitrine_idx
  on public.hospedagens_acomodacoes (ordem, criado_em)
  where estado = 'publicada';
create index hospedagens_acomodacoes_usuario_idx
  on public.hospedagens_acomodacoes (usuario_id, ordem);
create index hospedagens_fotos_acomodacao_idx
  on public.hospedagens_fotos (acomodacao_id, ordem, criado_em);
create index hospedagens_comodidades_acomodacao_idx
  on public.hospedagens_comodidades (acomodacao_id, ordem);

do $$
declare
  tabela text;
begin
  foreach tabela in array array[
    'hospedagens_acomodacoes',
    'hospedagens_contato'
  ]
  loop
    execute format(
      'create trigger %I_atualizado_em before update on public.%I '
      'for each row execute function public.definir_atualizado_em()',
      tabela,
      tabela
    );
  end loop;
end
$$;

-- RLS ligada e **sem policy nenhuma**: ninguem le estas tabelas direto, nem
-- anon nem authenticated. Quem le e a API, com service role, que ignora RLS.
-- Este Supabase e compartilhado com o transdocs — uma policy generosa para
-- `authenticated` abriria a vitrine para contas que nao tem nada com este hub.
-- O site publico nao consulta o banco: ele consulta a API, que decide o que e
-- publico (o que esta publicado) e o que nao e.
do $$
declare
  tabela text;
begin
  foreach tabela in array array[
    'hospedagens_acomodacoes',
    'hospedagens_fotos',
    'hospedagens_comodidades',
    'hospedagens_contato'
  ]
  loop
    execute format('alter table public.%I enable row level security', tabela);
    execute format('alter table public.%I force row level security', tabela);
    execute format('revoke all on public.%I from anon, authenticated', tabela);
  end loop;
end
$$;

-- O unico bucket publico do projeto, e o motivo esta no topo do arquivo: a
-- foto da casa e material de anuncio, feita para ser vista por quem nunca vai
-- ter conta aqui. Publico quer dizer *legivel* por URL — gravar continua sendo
-- so pela API (service role), porque nao ha policy de insert para ninguem.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'hospedagens-fotos',
  'hospedagens-fotos',
  true,
  10485760,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = true,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

commit;
