-- Os desenhos dos monstros andando, para o álbum do bestiário no celular.
--
-- A Grade desenha a caminhada de cada criatura a partir dos arquivos públicos
-- do jogo (`grade-idle/src/andando.js`). A foto do painel (`huntera_painel`)
-- leva só os monstros da caçada de agora, porque ela vai a cada minuto; o
-- álbum mostra as 158 criaturas, perto de 1 MB de desenho que quase nunca
-- muda. Então eles moram numa linha à parte: a Grade manda de novo só quando
-- desenha monstros novos, e o celular baixa uma vez.
--
-- Uma linha por pessoa, sobrescrita, `jsonb` opaco com teto no backend, e
-- pessoal como o painel: RLS forçado e nada para `anon` nem `authenticated`.

begin;

create table public.huntera_sprites (
  usuario_id uuid primary key references auth.users(id) on delete cascade,
  sprites jsonb not null,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

alter table public.huntera_sprites enable row level security;
alter table public.huntera_sprites force row level security;
revoke all on public.huntera_sprites from anon, authenticated;

create trigger huntera_sprites_atualizado_em
before update on public.huntera_sprites
for each row execute function public.definir_atualizado_em();

commit;
