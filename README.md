# ThiagoDocs API

API independente para leitura assistida, extração estruturada e conferência humana de
PDFs e imagens. O ThiagoDocs não valida autenticidade nem validade jurídica: toda
informação extraída deve ser conferida no documento original.

## Tecnologias

- Python 3.12+ e FastAPI;
- Supabase Auth, PostgreSQL e Storage privado;
- OpenAI Responses API, visão e Structured Outputs;
- pypdf para leitura local antes de usar visão;
- Pydantic para configuração e validação do resultado;
- Railway/Railpack para deploy.

## Arquitetura

```text
app/
├── api/                 # rotas, contratos HTTP e dependências de autenticação
├── aplicacao/           # casos de uso e orquestração do processamento
├── dominio/             # modelos, regras de arquivo e falhas de negócio
├── infraestrutura/
│   ├── arquivos/        # extração local de texto do PDF
│   ├── openai/          # único ponto de chamada à OpenAI, prompt e schema
│   └── supabase/        # Auth, repositório e Storage
└── core/                # configuração, erros e observabilidade
supabase/migrations/     # banco, índices, RLS, bucket e políticas
docs/                    # fluxo, deploy, privacidade e decisões
```

A API sempre valida o Bearer token no Supabase Auth. Mesmo usando a service role no
servidor, toda consulta de documento inclui `usuario_id`; RLS e políticas de Storage
formam uma segunda barreira.

## Fluxo de um documento

1. O arquivo é lido em blocos; PDFs aceitam até 50 MB e imagens até 25 MB.
2. MIME e assinatura binária são validados; o nome é sanitizado.
3. O SHA-256 evita upload e chamada de IA duplicados para a mesma conta.
4. O registro é criado e o arquivo vai para um caminho privado por usuário/documento.
5. Um trabalho em background reivindica o status de forma condicional.
6. PDFs tentam extração local de texto; PDFs digitalizados usam visão de páginas.
7. Imagens usam visão. O conteúdo enviado é somente o necessário à extração.
8. A OpenAI responde por JSON Schema estrito e o Pydantic valida novamente.
9. Achados, origem, confiança, alertas, ausências e consumo técnico são persistidos.
10. Correções e confirmações humanas geram histórico próprio.

Detalhes e estrutura do resultado: [docs/ARQUITETURA_E_FLUXO.md](docs/ARQUITETURA_E_FLUXO.md).

## Configuração local

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -e ".[dev]"
Copy-Item .env.example .env
uvicorn app.main:app --reload
```

Em máquinas com outra versão compatível, substitua `py -3.12` pelo executável
disponível. A API estará em `http://localhost:8000`, o health check em `/health` e a
documentação interativa em `/docs`.

## Variáveis de ambiente

| Variável | Uso |
|---|---|
| `APP_NAME` | Nome exibido no health/OpenAPI |
| `APP_ENV` | `local` ou `production` |
| `API_PREFIX` | Prefixo, padrão `/api/v1` |
| `CORS_ORIGINS` | Origens exatas, separadas por vírgula; sem wildcard |
| `SUPABASE_URL` | URL do projeto exclusivo do ThiagoDocs |
| `SUPABASE_ANON_KEY` | Chave pública usada para Auth |
| `SUPABASE_SERVICE_ROLE_KEY` | Segredo somente do back-end |
| `SUPABASE_DOCUMENTS_BUCKET` | Bucket privado, padrão `documentos` |
| `OPENAI_API_KEY` | Segredo somente do back-end |
| `OPENAI_MODEL` | Modelo com visão e Structured Outputs |
| `OPENAI_TIMEOUT_SECONDS` | Timeout da chamada, padrão 90 s |
| `OPENAI_INPUT_USD_PER_MILLION` | Preço estimado de 1 milhão de tokens de entrada |
| `OPENAI_OUTPUT_USD_PER_MILLION` | Preço estimado de 1 milhão de tokens de saída |
| `USD_BRL_RATE` | Cotação usada para estimar o custo em reais |
| `MAX_UPLOAD_BYTES` | Limite de PDF, padrão 50 MB |
| `MAX_FULL_ANALYSIS_BYTES` | Acima deste limite, o PDF exige análise só da primeira página |
| `MAX_EXTRACTED_TEXT_CHARS` | Teto de texto enviado ao modelo |
| `SIGNED_URL_TTL_SECONDS` | Validade da URL privada, padrão 300 s |

Não copie valores da Padoka. Crie `.env` próprio e nunca o versione.

## Supabase

1. Crie um projeto Supabase exclusivo.
2. Abra o SQL Editor e execute
   [`20260714000100_schema_inicial.sql`](supabase/migrations/20260714000100_schema_inicial.sql).
3. Em Authentication, configure URL do front e redirects de recuperação.
4. Confirme que o bucket `documentos` está privado.
5. Preencha as três variáveis do Supabase na API; o navegador recebe somente URL e
   anon key.

O nome `documentos` é usado também nas políticas SQL. Se alterar
`SUPABASE_DOCUMENTS_BUCKET`, atualize e reaplique as políticas da migration.

A migration cria:

- `documentos`;
- `extracoes_documentos`;
- `correcoes_extracao`;
- `processamentos`;
- índices por usuário/status/data;
- RLS forçada e políticas `auth.uid() = usuario_id`;
- bucket privado, limite de 50 MB e políticas por primeira pasta do usuário.

## OpenAI

Toda integração vive em `app/infraestrutura/openai`. A chave nunca chega ao front.
O cliente usa timeout, duas tentativas de rede, `store=False`, prompt contra invenção e
injeção documental e JSON Schema estrito. O retorno é validado antes de salvar.

O processamento registra somente modelo, estratégia e tokens; documento, prompt e
conteúdo extraído não são enviados aos logs.

O histórico calcula o custo estimado usando os tokens registrados, os preços configurados
e a cotação `USD_BRL_RATE`. O valor é informativo e pode diferir da cobrança final.

## Endpoints principais

| Método e caminho | Finalidade |
|---|---|
| `POST /api/v1/auth/cadastro` | Cadastro via Supabase Auth |
| `POST /api/v1/auth/login` | Login via Supabase Auth |
| `POST /api/v1/auth/recuperar-senha` | Recuperação de senha |
| `GET /api/v1/auth/sessao` | Validar sessão atual |
| `POST /api/v1/documentos` | Upload PDF/imagem e início do processamento |
| `GET /api/v1/documentos` | Histórico com busca indexada no arquivo e em todos os dados extraídos, status e paginação |
| `GET /api/v1/documentos/{id}` | Documento e extração |
| `GET /api/v1/documentos/{id}/arquivo` | URL assinada temporária |
| `PATCH /api/v1/documentos/{id}/resultado` | Corrigir/confirmar campo |
| `PATCH /api/v1/documentos/{id}/revisao` | Marcar revisão completa |
| `POST /api/v1/documentos/{id}/reprocessar` | Nova tentativa explícita |
| `DELETE /api/v1/documentos/{id}` | Excluir arquivo e dados relacionados |

Todos os endpoints de documento exigem `Authorization: Bearer <access_token>`.

## Qualidade e segurança

```powershell
ruff check app
python -m compileall -q app
```

- erros internos e stack traces nunca fazem parte da resposta;
- logs não registram e-mail, token, conteúdo ou nome do documento;
- tipos permitidos: PDF, JPEG, PNG e WEBP;
- CORS de produção exige origens explícitas;
- URL de arquivo expira e não há URL pública;
- exclusão remove Storage e o `on delete cascade` limpa dados derivados.

Política de retenção: [docs/PRIVACIDADE_E_RETENCAO.md](docs/PRIVACIDADE_E_RETENCAO.md).

## Deploy

O `railway.json` define Railpack, start command, health check e reinício. Veja
[docs/DEPLOY_RAILWAY.md](docs/DEPLOY_RAILWAY.md) para o procedimento completo e as
etapas externas ainda necessárias.

## Limitações da primeira versão

- O processador usa `BackgroundTasks` do processo web. Em escala ou com tarefas longas,
  deve migrar para uma fila persistente com worker separado.
- Não há OCR local; documentos digitalizados usam a capacidade visual do modelo.
- PDFs aceitam até 50 MB; acima de 25 MB é obrigatório analisar somente a primeira página.
- Imagens aceitam até 25 MB e os formatos Office não são aceitos.
- Não há organizações/cartórios compartilhados; `usuario_id` centraliza o escopo e
  permite introduzir esse contexto futuramente sem misturar contas.
- Resultados de IA exigem conferência; não existe validação jurídica automática.
