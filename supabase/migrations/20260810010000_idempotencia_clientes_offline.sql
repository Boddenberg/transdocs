-- A fila offline pode repetir uma requisição depois de perder a resposta.
-- Guardamos a chave do cliente e a impressão do pedido para distinguir uma
-- retomada legítima de uma reutilização acidental do mesmo UUID.

alter table public.registros_atividades_casa
  add column id_cliente uuid,
  add column conteudo_idempotencia text;

alter table public.pendencias_casa
  add column id_cliente uuid,
  add column conteudo_idempotencia text;

alter table public.diario_culinaria
  add column id_cliente uuid,
  add column conteudo_idempotencia text;

alter table public.registros_atividades_casa
  add constraint registros_casa_idempotencia_conteudo_check check (
    (id_cliente is null and conteudo_idempotencia is null)
    or (
      id_cliente is not null
      and conteudo_idempotencia ~ '^[a-f0-9]{64}$'
    )
  );

alter table public.pendencias_casa
  add constraint pendencias_casa_idempotencia_conteudo_check check (
    (id_cliente is null and conteudo_idempotencia is null)
    or (
      id_cliente is not null
      and conteudo_idempotencia ~ '^[a-f0-9]{64}$'
    )
  );

alter table public.diario_culinaria
  add constraint diario_culinaria_idempotencia_conteudo_check check (
    (id_cliente is null and conteudo_idempotencia is null)
    or (
      id_cliente is not null
      and conteudo_idempotencia ~ '^[a-f0-9]{64}$'
    )
  );

create unique index registros_casa_usuario_id_cliente_idx
  on public.registros_atividades_casa (usuario_id, id_cliente)
  where id_cliente is not null;

create unique index pendencias_casa_usuario_id_cliente_idx
  on public.pendencias_casa (usuario_id, id_cliente)
  where id_cliente is not null;

create unique index diario_culinaria_usuario_id_cliente_idx
  on public.diario_culinaria (usuario_id, id_cliente)
  where id_cliente is not null;
