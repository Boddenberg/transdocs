# Arquitetura, fluxo e decisões

## Visão geral

```text
Navegador ── Supabase Auth ── access token
    │
    └── ThiagoDocs API ── valida token ── escopo usuario_id
            ├── Supabase PostgreSQL (RLS)
            ├── Supabase Storage privado
            └── OpenAI Responses API
```

O front autentica pela anon key pública e envia o access token. A service role e a
chave OpenAI existem somente no back-end. O projeto Padoka é apenas referência de
padrões; não é dependência e nenhum domínio, banco, bucket ou segredo é compartilhado.

## Escritura assistida

O registro `preenchimentos` funciona como o processo da escritura. As fontes são classificadas
explicitamente como documentos dos vendedores, documentos dos compradores, matrícula ou valor
venal. O preço não é enviado como narrativa solta: `dados_negociacao` valida a soma dos meios de
pagamento e produz o valor por extenso de forma determinística.

A resposta estruturada da IA contém dois produtos independentes:

- blocos editáveis que poderão preencher o modelo DOCX;
- `analise_imovel`, com identificação, descrição, provável proprietário atual, forma de
  aquisição, atos em ordem cronológica, ônus ativos/cancelados/incertos, valor venal e divergências.

Toda conclusão registral precisa apontar arquivo, página e trecho. Um ônus só permanece com estado
`cancelado` quando o servidor encontra a referência a um ato cancelador na própria cronologia;
caso contrário, o estado é rebaixado para `incerto`. A geração exige `revisao_confirmada=true`.

## Estados

```text
pendente -> processando -> concluido
                       ├-> erro_leitura
                       ├-> erro_arquivo
                       ├-> erro_openai
                       └-> erro_interno
```

Uma atualização condicional de `pendente` para `processando` funciona como reivindicação
e evita duas chamadas simultâneas. Reprocessamento é uma ação explícita do usuário.

## Resultado persistido

```json
{
  "tipo_documento": null,
  "resumo": null,
  "pessoas": [],
  "empresas": [],
  "documentos_identificados": [],
  "enderecos": [],
  "datas": [],
  "valores": [],
  "imoveis": [],
  "campos_adicionais": [],
  "alertas": [],
  "campos_nao_encontrados": []
}
```

Cada item encontrado contém `valor`, `tipo`, `pagina`, `trecho`, `confianca`,
`precisa_revisao`, `confirmado` e `editado`. Pessoas e empresas também podem conter
`papel`. Confiança abaixo de 0,80 é forçada para revisão pelo código, mesmo que o modelo
não a marque.

## Estratégia de leitura

- PDF textual: pypdf extrai texto com marcadores de página. O texto é truncado no
  limite configurado antes da chamada.
- PDF sem texto legível: o PDF é enviado como `input_file`; modelos com visão recebem
  texto e imagens das páginas.
- Imagem: base64 em `input_image` com detalhe alto.
- `store=False` reduz retenção no provedor; consulte também os controles contratuais e
  de dados da conta OpenAI usada em produção.

## Decisões de segurança

- Assinatura binária é verificada além de extensão/MIME.
- Hash SHA-256 único por usuário impede duplicidade acidental.
- Caminho de Storage começa por `usuario_id/documento_id`.
- RLS é habilitada e forçada em todas as tabelas com dados pessoais.
- O back-end repete o filtro de propriedade mesmo com service role.
- Correção nunca substitui silenciosamente o resultado: gera registro antes/depois.
- Logs usam somente método, caminho, status, duração, ID técnico e tipo de falha.

## Evoluções recomendadas

1. Fila persistente e worker Railway separado, com idempotency key.
2. OCR local/privado para reduzir envio visual e custo em documentos simples.
3. Organizações/cartórios, membros e papéis, preservando RLS por escopo.
4. Webhooks ou Supabase Realtime para substituir acompanhamento periódico.
5. Política automatizada de expiração/retenção configurável por organização.
6. Avaliações com conjunto documental anonimizado e métricas por tipo de campo.
7. Testes unitários, integração com Supabase local e testes de autorização negativos.
