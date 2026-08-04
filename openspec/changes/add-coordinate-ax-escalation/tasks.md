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
