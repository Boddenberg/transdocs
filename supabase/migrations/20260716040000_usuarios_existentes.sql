begin;

insert into public.perfis (usuario_id, nome)
select
  usuario.id,
  coalesce(usuario.raw_user_meta_data ->> 'nome', split_part(usuario.email, '@', 1))
from auth.users usuario
on conflict (usuario_id) do nothing;

insert into public.categorias (usuario_id, nome, natureza, icone, cor, padrao)
select usuario.id, categoria.nome, categoria.natureza, categoria.icone, categoria.cor, true
from auth.users usuario
cross join (
  values
    ('Salario', 'receita', 'briefcase-business', '#67e8b5'),
    ('Freelance', 'receita', 'sparkles', '#72b7ff'),
    ('Beneficios', 'receita', 'badge-dollar-sign', '#ffd166'),
    ('Rendimentos', 'receita', 'chart-no-axes-combined', '#8b7cff'),
    ('Outros ganhos', 'receita', 'plus', '#9de2d0'),
    ('Moradia', 'despesa', 'house', '#ff8c73'),
    ('Alimentacao', 'despesa', 'utensils', '#ffbd66'),
    ('Transporte', 'despesa', 'car-front', '#72b7ff'),
    ('Saude', 'despesa', 'heart-pulse', '#ff7aa2'),
    ('Lazer', 'despesa', 'popcorn', '#b39cff'),
    ('Assinaturas', 'despesa', 'repeat-2', '#7cd4ca'),
    ('Educacao', 'despesa', 'graduation-cap', '#8bb8ff'),
    ('Impostos', 'despesa', 'landmark', '#d1a26f'),
    ('Compras', 'despesa', 'shopping-bag', '#e99cff'),
    ('Outros gastos', 'despesa', 'ellipsis', '#98a2b8')
) as categoria(nome, natureza, icone, cor)
on conflict (usuario_id, nome) do nothing;

commit;

