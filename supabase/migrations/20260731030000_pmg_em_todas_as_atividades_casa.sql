begin;

-- Toda atividade da casa passa a oferecer as tres faixas.
--
-- O cartao do comodo agora marca por toque: um toque e P, dois e M, tres e G.
-- Uma atividade que so tinha P ficava com um unico toque util e o gesto morria
-- na metade — a pessoa toca de novo esperando "mais caprichado" e a atividade
-- se desmarca. Preencher M e G para todas e o que faz o gesto valer em todo
-- cartao.
--
-- A escala sai do peso que a atividade ja tinha, e nao de um numero novo: P e o
-- que estava cadastrado (1 regar a planta, 3 limpar o fogao, 5 lavar o box),
-- M vale o dobro e G o triplo. O que ja tinha faixa cadastrada a mao fica como
-- esta; so o que estava em branco e preenchido, e cada uma pode ser reescrita
-- pelo lapis da gaveta.
--
-- O corte em 333 e o teto de 999 pontos falando: acima disso o triplo nao
-- caberia, e uma atividade que nao pode ter G fica como esta em vez de ganhar
-- uma faixa inventada. Nenhuma atividade real chega perto (a maior vale 8).
update public.catalogo_atividades_casa
set pontos_m = coalesce(pontos_m, round(pontos_p * 2, 2)),
    pontos_g = coalesce(pontos_g, round(coalesce(pontos_m, pontos_p * 2) * 1.5, 2)),
    atualizado_em = now()
where (pontos_m is null or pontos_g is null)
  and pontos_p <= 333;

commit;
