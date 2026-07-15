from dataclasses import dataclass
from uuid import UUID


@dataclass(frozen=True, slots=True)
class UsuarioAutenticado:
    id: UUID
    email: str | None


@dataclass(frozen=True, slots=True, repr=False)
class SessaoAutenticada:
    usuario: UsuarioAutenticado
    token: str

