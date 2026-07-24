begin;

-- Nome de exibicao gerado pela IA -------------------------------------------
--
-- O nome do arquivo enviado costuma ser ruim ("scan_20260724_0001.pdf"). Ao
-- processar o upload, a IA le o conteudo e propoe um nome claro e curto (ex.:
-- "Contrato de financiamento do veiculo"). Guardamos esse nome aqui, sem
-- perder o `nome_original`; o drive e o hub mostram o de exibicao quando existe.
alter table public.documentos_financeiros
  add column if not exists nome_exibicao text
    check (nome_exibicao is null or char_length(nome_exibicao) between 1 and 255);

commit;
