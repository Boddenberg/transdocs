class FalhaLeituraDocumento(Exception):
    """O arquivo não pôde ser interpretado como documento."""


class FalhaOpenAI(Exception):
    """A extração estruturada falhou no provedor de IA."""
