begin;

with detalhes (grupo_id, movimentacao_id, descricao, composicao) as (
  values
    (
      '9e33cf91-2766-40ab-a7f7-c81a0e5e982d'::uuid,
      null::uuid,
      'Bermuda de ciclismo com forro em gel D80',
      $json$
      {
        "tipo": "compra",
        "identificacao": "associacao_inferida",
        "itens": [
          {
            "descricao": "Bermuda de ciclismo com forro em gel D80 (MTB/BMC)",
            "quantidade": 1
          }
        ],
        "observacao": "O Mercado Livre não informou qual compra de 16/07 corresponde a R$ 12,59 ou R$ 13,60. A associação foi feita pela ordem de exibição.",
        "recorrente": false
      }
      $json$::jsonb
    ),
    (
      '405c51b5-b552-4724-a98b-c28437e248ac'::uuid,
      null::uuid,
      'Saco para plastificação Polaseal A4',
      $json$
      {
        "tipo": "compra",
        "identificacao": "associacao_inferida",
        "itens": [
          {
            "descricao": "Saco para plastificação Polaseal A4 (kit com 100 unidades)",
            "quantidade": 1
          }
        ],
        "observacao": "O Mercado Livre não informou qual compra de 16/07 corresponde a R$ 12,59 ou R$ 13,60. A associação foi feita pela ordem de exibição.",
        "recorrente": false
      }
      $json$::jsonb
    ),
    (
      '8c8372d0-e11a-4364-8d24-9f162562e904'::uuid,
      null::uuid,
      'Kit de acessórios para bicicleta',
      $json$
      {
        "tipo": "compra",
        "identificacao": "completa",
        "itens": [
          {
            "descricao": "Corda elástica para bagageiro (kit com 4)",
            "quantidade": 2
          },
          {
            "descricao": "Bolsa de quadro para bicicleta com suporte para celular",
            "quantidade": 1
          },
          {
            "descricao": "Farol para bicicleta com 3 LEDs recarregável USB",
            "quantidade": 1
          },
          {
            "descricao": "Luva acolchoada para ciclismo/academia (GG)",
            "quantidade": 2
          },
          {
            "descricao": "Farol/lanterna para bicicleta com 6 LEDs",
            "quantidade": 1
          }
        ],
        "observacao": null,
        "recorrente": false
      }
      $json$::jsonb
    ),
    (
      '1de640d0-cb93-49b5-a229-561183c523c6'::uuid,
      null::uuid,
      'Kit com 5 molduras A4 tabaco',
      $json$
      {
        "tipo": "compra",
        "identificacao": "completa",
        "itens": [
          {
            "descricao": "Kit com 5 molduras A4 (21x30 cm), cor tabaco",
            "quantidade": 1
          }
        ],
        "observacao": null,
        "recorrente": false
      }
      $json$::jsonb
    ),
    (
      '72e8a1bf-7738-42f2-be1e-4a5529042dd3'::uuid,
      null::uuid,
      'Compra Mercado Livre não identificada',
      $json$
      {
        "tipo": "compra",
        "identificacao": "incompleta",
        "itens": [],
        "observacao": "O Mercado Livre mostrou o parcelamento em 8 vezes, mas não exibiu a tela de detalhes desta compra. Os produtos não puderam ser identificados.",
        "recorrente": false
      }
      $json$::jsonb
    ),
    (
      '194d0607-89c8-4642-b5d2-75e92967c1ad'::uuid,
      null::uuid,
      'Compra Mercado Livre com 22 itens',
      $json$
      {
        "tipo": "compra",
        "identificacao": "completa",
        "itens": [
          {
            "descricao": "Amolador/afiador profissional de facas",
            "quantidade": 2
          },
          {
            "descricao": "Pegador grande de salada em aço inox (kit com 2)",
            "quantidade": 1
          },
          {
            "descricao": "Ventilador de mesa portátil 127 V",
            "quantidade": 1
          },
          {
            "descricao": "Saco para enjoo/vômito (kit com 10)",
            "quantidade": 1
          },
          {
            "descricao": "Ralador grande Tramontina em inox",
            "quantidade": 1
          },
          {
            "descricao": "Halter sextavado de 5 kg",
            "quantidade": 2
          },
          {
            "descricao": "Placa de som/adaptador USB P2/P3",
            "quantidade": 1
          },
          {
            "descricao": "Kit farol e lanterna para bicicleta",
            "quantidade": 1
          },
          {
            "descricao": "Escova removedora de pelos para pets",
            "quantidade": 2
          },
          {
            "descricao": "Spray pulverizador para azeite/óleo/vinagre",
            "quantidade": 1
          },
          {
            "descricao": "Mini compressor digital portátil para pneus",
            "quantidade": 1
          },
          {
            "descricao": "Cabo original Apple USB-C para Lightning",
            "quantidade": 1
          },
          {
            "descricao": "Cola Super Bonder Power Flex Gel",
            "quantidade": 1
          },
          {
            "descricao": "Hand Grip fortalecedor de mãos",
            "quantidade": 1
          },
          {
            "descricao": "Espátula de aço inox com cabo de madeira",
            "quantidade": 1
          },
          {
            "descricao": "Modelador para tapioca/panqueca/omelete (kit com 2)",
            "quantidade": 1
          },
          {
            "descricao": "Álcool isopropílico 99,8% (1 litro)",
            "quantidade": 1
          },
          {
            "descricao": "Fio dental com haste (100 unidades)",
            "quantidade": 1
          },
          {
            "descricao": "Modelador profissional de hambúrguer",
            "quantidade": 1
          },
          {
            "descricao": "Fone Plantronics Blackwire C3220",
            "quantidade": 1
          },
          {
            "descricao": "Ralador manual de quatro faces em inox",
            "quantidade": 1
          },
          {
            "descricao": "Prensador de bife em ferro fundido",
            "quantidade": 1
          }
        ],
        "observacao": null,
        "recorrente": false
      }
      $json$::jsonb
    ),
    (
      null::uuid,
      '16bf62fb-5aad-4edc-8242-86e4fb858589'::uuid,
      'Kit com 5 calcinhas fio duplo',
      $json$
      {
        "tipo": "compra",
        "identificacao": "completa",
        "itens": [
          {
            "descricao": "Kit com 5 calcinhas fio duplo com regulagem lateral e renda",
            "quantidade": 1
          }
        ],
        "observacao": null,
        "recorrente": false
      }
      $json$::jsonb
    ),
    (
      null::uuid,
      'c1374fdc-64a6-4f33-ae76-2b2adb56ffcf'::uuid,
      'Meli+',
      $json$
      {
        "tipo": "servico",
        "identificacao": "completa",
        "itens": [
          {
            "descricao": "Assinatura Meli+",
            "quantidade": 1
          }
        ],
        "observacao": "Cobrança mensal recorrente, sem número definido de parcelas.",
        "recorrente": true
      }
      $json$::jsonb
    )
)
update public.movimentacoes as movimentacao
set
  descricao = detalhes.descricao,
  metadados = movimentacao.metadados
    || jsonb_build_object('composicao_fatura', detalhes.composicao)
from detalhes
where movimentacao.usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'
  and (
    (detalhes.grupo_id is not null
      and movimentacao.grupo_parcelas_id = detalhes.grupo_id)
    or (detalhes.movimentacao_id is not null
      and movimentacao.id = detalhes.movimentacao_id)
  );

insert into public.recorrencias (
  usuario_id,
  conta_id,
  categoria_id,
  natureza,
  descricao,
  valor_estimado,
  periodicidade,
  proxima_data,
  confianca,
  detectada_por_ia,
  ativa,
  metadados
)
select
  conta.usuario_id,
  conta.id,
  (
    select categoria.id
    from public.categorias as categoria
    where categoria.usuario_id = conta.usuario_id
      and lower(categoria.nome) = lower('Assinaturas')
    order by categoria.padrao desc
    limit 1
  ),
  'despesa',
  'Meli+',
  9.90,
  'mensal',
  '2026-08-01'::date,
  1,
  false,
  true,
  jsonb_build_object(
    'composicao_fatura',
    $json$
    {
      "tipo": "servico",
      "identificacao": "completa",
      "itens": [
        {
          "descricao": "Assinatura Meli+",
          "quantidade": 1
        }
      ],
      "observacao": "Cobrança mensal recorrente, sem número definido de parcelas.",
      "recorrente": true
    }
    $json$::jsonb
  )
from public.contas as conta
where conta.id = 'd33d76b9-5f1b-436c-aec1-2f7270a863e6'
  and conta.usuario_id = 'cafaa5dd-2a6a-4d0c-b08b-aa4dd73563e7'
  and not exists (
    select 1
    from public.recorrencias as recorrencia
    where recorrencia.usuario_id = conta.usuario_id
      and recorrencia.conta_id = conta.id
      and lower(recorrencia.descricao) = lower('Meli+')
  );

commit;
