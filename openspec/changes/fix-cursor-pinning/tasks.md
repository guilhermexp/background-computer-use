# Tasks: fix-cursor-pinning

## 1. P5 — determinismo das suites de cursor (pré-requisito para provar o resto)
- [x] 1.1 Expor um reset de estado de runtime de cursor para teste (`CursorRuntime.resetForTesting()`) que limpa sessões e overlays sem tocar no ciclo de vida de produção.
- [x] 1.2 Serializar as suites de cursor (`@Suite(.serialized)`) e resetar o runtime no início de cada teste que toca `CursorRuntime`.
- [x] 1.3 Tornar explícitos os dwells das asserções de pointing (sem relógio de parede implícito), mantendo cada asserção existente intacta.

## 2. P1 — ponta do cursor = ponto da ação
- [x] 2.1 Teste que falha antes: ponto visual de `prepareClick` com alvo grande == ponto resolvido da ação e `targetPointSource` sem `visual_interest_offset`.
- [x] 2.2 Remover `visualTargetPoint` (candidatos de canto + `CGFloat.random`) de `AXCursorTargeting`; `prepareTargetedCursor` usa o mesmo `targetPoint(for:window:)` da ação.
- [x] 2.3 Remover `visual_interest_offset` do vocabulário de `targetPointSource`.

## 3. P2 — cursor preso à janela atada
- [x] 3.1 Teste que falha antes: ponto fora do frame da janela é clampado à janela e à tela **da janela**, nunca a `NSScreen.main`/outra tela.
- [x] 3.2 Criar `Cursor/CursorWindowPinning.swift`: resolução da tela da janela (maior interseção real, `nil` quando a janela está fora de todas), clamp janela→tela e seam de geometria de janela viva (`CursorWindowAnchorResolver`) para teste.
- [x] 3.3 `AXCursorTargeting.targetPoint`/`clampVisualPoint` passam a usar o clamp ancorado na janela.
- [x] 3.4 `CursorCoordinator.clampToVisibleScreen` e `initialPoint`/`sessionCurrentOrFallbackPoint` usam a tela da janela atada quando existe attachment.
- [x] 3.5 Teste que falha antes: janela atada muda de frame entre ações → cursor mantém posição relativa dentro da janela.
- [x] 3.6 `CursorCoordinator.updateAttachment` reancora a posição pela mudança de frame da janela atada.

## 4. P3 — presença enquanto atado
- [x] 4.1 Teste que falha antes: após `idleHideDelay` com attachment vivo, `visibilityAlpha == 1`.
- [x] 4.2 Teste que falha antes: com attachment perdido (janela off-screen), o fade por `idleHideDelay` volta a valer.
- [x] 4.3 `stepVisibility` mantém `visible`/`visibilityAlpha = 1` enquanto o attachment está vivo, sem renovar `lastActivityAt` (preserva `idleExpireDelay`).

## 5. P4 — sem deriva parada
- [x] 5.1 Teste que falha antes: sem ação, a posição do cursor não muda entre ticks.
- [x] 5.2 Remover `CursorMotionConstants.idleBreathing`, `idleSeed`, `idleBreathOffsetX/Y` e a deriva senoidal de posição em `advance`; manter o assentamento de ângulo na home angle.

## 6. Gates
- [x] 6.1 `swift build -c release` verde.
- [x] 6.2 `swift test` (suite completa, 3 execuções consecutivas, sem `--filter`) verde nas 3.
- [x] 6.3 `openspec validate fix-cursor-pinning --strict` válido.
- [ ] 6.4 Validação visual ao vivo (runtime instalado) é feita pelo orquestrador — cursor preso e visível na janela alvo.
