# Privacidade, retenção e exclusão

## Dados tratados

Documentos podem conter dados pessoais e patrimoniais. A operação deve ter finalidade,
base legal, controles de acesso e prazo de retenção definidos pelo responsável pelo
tratamento. O software não substitui aconselhamento jurídico ou adequação à LGPD.

## Padrão da primeira versão

- arquivos privados no Supabase Storage;
- banco isolado por usuário com RLS;
- URLs assinadas por 5 minutos;
- retenção até exclusão explícita pelo usuário;
- exclusão do arquivo primeiro e do registro depois;
- cascata para extração, correções e processamento;
- logs sem conteúdo, token, e-mail ou nome de arquivo.

## Operação recomendada

1. Defina um prazo de retenção e comunique-o antes do uso real.
2. Restrinja o painel Supabase e Railway às pessoas indispensáveis.
3. Ative MFA nas contas administrativas.
4. Revise suboperadores, região, termos e controles de dados da OpenAI/Supabase.
5. Não use documentos reais em ambientes de desenvolvimento.
6. Tenha procedimento para incidente, exportação e solicitação de titular.
7. Em uma próxima versão, automatize expiração e relatório de exclusão.

