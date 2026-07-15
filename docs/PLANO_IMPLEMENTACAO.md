# Plano de implementação do TransDocs

## Referência técnica auditada

Foram inspecionados `padoka100` e `padoka100-web` após atualização segura por
`git pull --ff-only`. Os conceitos reaproveitados são configuração por ambiente,
FastAPI, Supabase Auth, cliente de API central, Bearer token, OpenAI Responses com
saída estruturada e deploy Railway com health check. Nenhuma regra de negócio,
credencial, URL privada, tabela ou bucket da Padoka faz parte do TransDocs.

## Execução

1. Criar o núcleo FastAPI, configuração, erros seguros e logs sem dados pessoais.
2. Implementar Auth Supabase e proteção obrigatória dos endpoints privados.
3. Modelar documento, resultado de extração, correção e processamento.
4. Implementar upload validado, bucket privado, hash e propriedade por usuário.
5. Extrair texto de PDFs e usar análise visual em imagens/PDFs digitalizados.
6. Integrar OpenAI em um único adaptador, com schema estrito e guardrails.
7. Criar migrations com índices, RLS e políticas de Storage.
8. Criar o front-end Next.js com identidade própria e autenticação Supabase.
9. Implementar upload, histórico, busca, filtros e acompanhamento moderado.
10. Implementar a bancada lado a lado, origem, confiança, edição e confirmação.
11. Preparar Railway, documentação, retenção, validações e smoke tests.
12. Organizar commits pequenos e enviar `main` nos dois repositórios.

## Condições externas

Supabase, Railway e domínios serão provisionados automaticamente somente se as
sessões locais estiverem válidas. Sem autorização externa, migrations, manifests,
variáveis e instruções serão entregues prontos, sem bloquear a implementação.

