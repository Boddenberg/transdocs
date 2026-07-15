# Deploy independente no Railway

O TransDocs não deve usar o projeto, serviço ou variáveis da Padoka.

## Estado desta entrega

O repositório contém `railway.json`, health check e variáveis documentadas. A sessão do
Railway CLI disponível durante a implementação estava expirada; por isso nenhum projeto,
serviço, domínio ou variável externa foi criado automaticamente.

## Único fluxo manual restante

1. Entre no Railway e crie um projeto chamado `transdocs`.
2. Adicione um serviço a partir do repositório GitHub `transdocs`, branch `main`.
3. Confirme Railpack e o start command do `railway.json`.
4. Preencha todas as variáveis de `.env.example`; use valores do projeto Supabase
   exclusivo do TransDocs.
5. Defina `APP_ENV=production` e `CORS_ORIGINS=https://DOMINIO-DO-FRONT`.
6. Gere um domínio para a API.
7. Valide `https://DOMINIO-DA-API/health` e confirme `status: ok`.
8. No serviço `transdocs-web`, configure `NEXT_PUBLIC_API_URL` com esse domínio antes do
   build.
9. Depois do front publicado, confirme CORS sem wildcard e teste login/upload/resultado.

Variáveis secretas (`SUPABASE_SERVICE_ROLE_KEY` e `OPENAI_API_KEY`) pertencem somente ao
serviço `transdocs`. Nunca as configure no front-end.
