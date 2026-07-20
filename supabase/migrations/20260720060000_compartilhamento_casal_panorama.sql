begin;

-- Qualquer despesa real exibida no Panorama pode seguir o mesmo fluxo de
-- aprovacao das compras de cartao. A marcacao fica na entidade de origem para
-- que valor, data, conta/forma de pagamento e recorrencia continuem sendo os
-- dados canonicos do lancamento.

alter table public.recorrencias
  add column if not exists compartilhada_casal boolean not null default false,
  add column if not exists percentual_casal_criador numeric(5, 2)
    check (percentual_casal_criador is null
           or (percentual_casal_criador >= 0 and percentual_casal_criador <= 100));

alter table public.parcelas_divida
  add column if not exists compartilhada_casal boolean not null default false,
  add column if not exists percentual_casal_criador numeric(5, 2)
    check (percentual_casal_criador is null
           or (percentual_casal_criador >= 0 and percentual_casal_criador <= 100));

alter table public.ajustes_celulas_panorama
  add column if not exists compartilhada_casal boolean not null default false,
  add column if not exists percentual_casal_criador numeric(5, 2)
    check (percentual_casal_criador is null
           or (percentual_casal_criador >= 0 and percentual_casal_criador <= 100));

alter table public.ajustes_celulas_panorama
  add column if not exists data_referencia date;
update public.ajustes_celulas_panorama
set data_referencia = competencia
where data_referencia is null;
alter table public.ajustes_celulas_panorama
  alter column data_referencia set not null,
  drop constraint if exists ajustes_celulas_panorama_data_referencia_check;
alter table public.ajustes_celulas_panorama
  add constraint ajustes_celulas_panorama_data_referencia_check
  check (date_trunc('month', data_referencia)::date = competencia);

alter table public.movimentacoes_investimentos
  add column if not exists compartilhada_casal boolean not null default false,
  add column if not exists percentual_casal_criador numeric(5, 2)
    check (percentual_casal_criador is null
           or (percentual_casal_criador >= 0 and percentual_casal_criador <= 100));

create index if not exists recorrencias_compartilhadas_casal_idx
  on public.recorrencias (usuario_id, proxima_data)
  where compartilhada_casal and ativa;

create index if not exists parcelas_divida_compartilhadas_casal_idx
  on public.parcelas_divida (usuario_id, data_vencimento)
  where compartilhada_casal and status in ('prevista', 'paga', 'atrasada');

create index if not exists ajustes_celulas_compartilhados_casal_idx
  on public.ajustes_celulas_panorama (usuario_id, competencia)
  where compartilhada_casal;

create index if not exists movimentos_investimentos_compartilhados_casal_idx
  on public.movimentacoes_investimentos (usuario_id, data_movimentacao)
  where compartilhada_casal and tipo = 'aporte';

-- A solicitacao identifica a entidade do Panorama e guarda um pequeno retrato
-- para o Hub e a notificacao. O aceite continua alterando a entidade original;
-- o retrato nao substitui nem duplica os dados financeiros.
alter table public.compartilhamentos_casal
  add column if not exists entidade_tipo text not null default 'movimentacao',
  add column if not exists entidade_id uuid,
  add column if not exists data_referencia date,
  add column if not exists recorrente boolean not null default false,
  add column if not exists periodicidade text,
  add column if not exists forma_pagamento text;

alter table public.compartilhamentos_casal
  drop constraint if exists compartilhamentos_casal_entidade_tipo_check;
alter table public.compartilhamentos_casal
  add constraint compartilhamentos_casal_entidade_tipo_check
  check (entidade_tipo in (
    'movimentacao', 'recorrencia', 'parcela_divida',
    'ajuste_celula', 'movimentacao_investimento'
  ));

alter table public.compartilhamentos_casal
  drop constraint if exists compartilhamentos_casal_periodicidade_check;
alter table public.compartilhamentos_casal
  add constraint compartilhamentos_casal_periodicidade_check
  check (periodicidade is null or periodicidade in (
    'semanal', 'quinzenal', 'mensal', 'bimestral',
    'trimestral', 'semestral', 'anual'
  ));

create index if not exists compartilhamentos_casal_entidade_idx
  on public.compartilhamentos_casal (vinculo_id, entidade_tipo, entidade_id, status);

commit;
