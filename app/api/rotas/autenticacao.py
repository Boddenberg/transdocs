import re
from typing import Annotated, Any

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field, field_validator

from app.api.dependencias import SessaoAtual, UsuarioAtual
from app.infraestrutura.supabase.autenticacao import (
    AutenticacaoSupabase,
    obter_autenticacao_supabase,
)

router = APIRouter(prefix="/auth", tags=["autenticação"])
AutenticacaoAtual = Annotated[
    AutenticacaoSupabase, Depends(obter_autenticacao_supabase)
]


class Credenciais(BaseModel):
    email: str = Field(min_length=5, max_length=254)
    senha: str = Field(min_length=8, max_length=128)

    @field_validator("email")
    @classmethod
    def validar_email(cls, valor: str) -> str:
        email = valor.strip().lower()
        if not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", email):
            raise ValueError("e-mail inválido")
        return email


class Cadastro(Credenciais):
    nome: str = Field(min_length=2, max_length=100)


class Recuperacao(BaseModel):
    email: str = Field(min_length=5, max_length=254)
    redirecionamento: str | None = Field(default=None, max_length=500)


@router.post("/cadastro", status_code=201)
def cadastrar(
    dados: Cadastro,
    autenticacao: AutenticacaoAtual,
) -> dict[str, Any]:
    return autenticacao.cadastrar(email=dados.email, senha=dados.senha, nome=dados.nome.strip())


@router.post("/login")
def entrar(
    dados: Credenciais,
    autenticacao: AutenticacaoAtual,
) -> dict[str, Any]:
    return autenticacao.entrar(email=dados.email, senha=dados.senha)


@router.post("/recuperar-senha", status_code=202)
def recuperar_senha(
    dados: Recuperacao,
    autenticacao: AutenticacaoAtual,
) -> dict[str, str]:
    autenticacao.solicitar_recuperacao(
        email=dados.email.strip().lower(), redirecionamento=dados.redirecionamento
    )
    return {"mensagem": "Se o e-mail estiver cadastrado, enviaremos as instruções."}


@router.get("/sessao")
def consultar_sessao(usuario: UsuarioAtual) -> dict[str, str | None]:
    return {"id": str(usuario.id), "email": usuario.email}


@router.post("/logout", status_code=204)
def sair(
    sessao: SessaoAtual,
    autenticacao: AutenticacaoAtual,
) -> None:
    autenticacao.sair(sessao.token)
