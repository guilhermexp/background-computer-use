## 1. Diagnóstico (concluído antes de qualquer código)

- [x] 1.1 Instrumentar o transporte com variantes selecionáveis por env e medir nove combinações de conteúdo de evento contra a fixture Chrome, em background e em foreground.
- [x] 1.2 Provar por controle que o mesmo evento sem estampas, postado no tap HID global, clica o botão (`Button not clicked` → `Button clicked`).
- [x] 1.3 Confirmar a coordenada por pixel (cursor do agente sobre o botão) e pelo centro do frame AX do controle.
- [x] 1.4 Verificar que a UI do próprio Chrome também ignora a injeção dirigida por pid (clique em aba inativa não troca de aba).
- [x] 1.5 Remover o scaffold de variantes do transporte.

## 2. Escalada AX

- [x] 2.1 Extrair `AXPointPressEligibility` com o guard de press + frame cobrindo o ponto com dimensão mínima.
- [x] 2.2 Cobrir a elegibilidade com testes, incluindo o frame colapsado de controle rolado para fora da viewport.
- [x] 2.3 Implementar o hit-test + `AXPress` no ponto do clique após dispatch não verificado, com releitura e reverificação pelo mesmo gate.
- [x] 2.4 Adotar o resultado somente quando a reverificação provar efeito.

## 3. Contrato e diagnóstico

- [x] 3.1 Adicionar `ClickFinalRouteDTO.coordinateThenAXHitTest` e `ClickFallbackReasonDTO.coordinateUnverifiedUsingAXHitTest`.
- [x] 3.2 Registrar a tentativa em `transports[]` (`ax_perform_action`, `ax_hit_test_at_click_point`) e em `routeSteps[]`.
- [x] 3.3 Classificar dispatch sem efeito em superfície de renderer web como `app_specific_semantics` com aviso `renderer_ignores_coordinate_injection` e a alternativa AX.

## 4. Smoke e skill

- [x] 4.1 Casar âncora OCR com tolerância a erro de reconhecimento do Vision.
- [x] 4.2 Levar a fixture ao topo quando uma aba reusada ficou rolada.
- [x] 4.3 Recarregar a fixture entre o caminho OCR e o caminho AX (o botão é idempotente).
- [x] 4.4 Documentar a escalada e o limite residual na SKILL.md.

## 5. Gates

- [x] 5.1 `swift build`
- [x] 5.2 `swift test`
- [x] 5.3 `python3 -m py_compile script/smoke_runtime.py`
- [x] 5.4 `python3 script/smoke_runtime.py` com o caminho OCR provando efeito na página
- [x] 5.5 `openspec validate add-coordinate-ax-escalation --strict`

## 6. Hardening exigido pelo gate pré-push (2026-08-04)

- [x] 6.1 Escopo de processo: exigir que o elemento do hit-test pertença ao pid da janela nomeada (fallback systemWide não pode cruzar processo).
- [x] 6.2 Aplicar `RuntimeSafetyPolicy.evaluateLabel` ao rótulo do elemento antes do `AXPress`, com recusa reportada em `warnings`.
- [x] 6.3 Elegibilidade: exigir `AXEnabled != false` e teto de dimensão, além de `AXPress` e frame cobrindo o ponto.
- [x] 6.4 Não escalar quando há mudança ambiente ou visual de janela (evita dupla atuação em efeito lento).
- [x] 6.5 Adotar `postCapture`/`verification` da releitura pós-press mesmo quando o press não é creditado.
- [x] 6.6 Rotular o step da coordenada com o veredito dela mesma; preservar o step da escalada no caminho OCR.
- [x] 6.7 `finalRoute` e `failureDomain` do caminho OCR coerentes com a escalada; filtro de warnings casando o diagnóstico renomeado.
- [x] 6.8 Timeout de mensageria AX no elemento de aplicação e no elemento do hit-test.
- [x] 6.9 Publicar `coordinate_then_ax_hit_test` e `coordinate_unverified_using_ax_hit_test` em `/v1/routes` e documentar a escalada em `nextSteps`.
- [x] 6.10 Smoke: lane OCR passa a poder ficar vermelha (regressão da escalada) e o oráculo de sucesso exige match exato.
