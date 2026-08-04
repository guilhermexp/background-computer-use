## Why

O cursor visual do agente está "louco": ele não fica onde a ação acontece, sai da janela, pula de tela e some sozinho. Evidência real capturada em 2026-08-04 num `POST /v1/click` com `target.kind=ocr_anchor` sobre uma janela do Chrome:

```json
"coordinate": { "targetPointAppKit": { "x": 120.38095238095238, "y": 2238.28125 },
                "targetPointSource": "ocr_anchor_center" },
"cursor": { "moved": true, "movement": "approach_click_choreography",
            "targetPointAppKit": { "x": 379, "y": 2238.28125 },
            "warnings": ["Visual cursor offset was outside visible screen geometry and was clamped to the nearest matching screen."] }
```

O clique foi despachado em `x=120,4` e o cursor visual foi desenhado em `x=379` — 258 pt longe da ação — e depois clampado para **outra tela**. Causas raiz localizadas no código:

- **Teleporte deliberado.** `Cursor/AXCursorTargeting.swift:413-471` (`visualTargetPoint`) monta 9 candidatos nos cantos/meios do frame do alvo mais 6 pontos `CGFloat.random`, pontua cada um por `distance(to: previousPoint) + CGFloat.random(in: 0...16)` e escolhe o **máximo** — o ponto visual é escolhido para ser o mais longe possível da ação, sob o rótulo `visual_interest_offset`.
- **Clamp para a tela errada.** `AXCursorTargeting.clampVisualPoint` e `CursorCoordinator.clampToVisibleScreen` (`CursorCoordinator.swift:971-979`) resolvem a tela por `screenContaining(point:)`/`NSScreen.main`, então um ponto que escapa da janela é grudado na tela que o ponto calhou de tocar — não na tela da janela atada.
- **Some com a sessão viva.** `CursorPresenceTiming.idleHideDelay = 1.2s` faz o cursor sumir 1,2 s depois de cada ação mesmo com attachment de janela vivo.
- **Deriva parada.** `CursorMotionConstants.idleBreathing = true` alimenta deriva senoidal contínua da posição em `CursorCoordinator.advance` — o cursor se mexe sozinho sem nenhuma ação.
- **Suites não-determinísticas.** As suites de cursor falham de forma intermitente no `swift test` completo (dwell de pointing medido em relógio de parede + estado global compartilhado em `CursorRuntime`), o que impede provar qualquer correção de presença por teste.

## What Changes

- **P1 — ponta = ação.** Remover `visualTargetPoint` e o vocabulário `visual_interest_offset`: o ponto visual do cursor passa a ser exatamente o ponto que a ação despacha. Nenhum `CGFloat.random` decide posição de cursor.
- **P2 — preso à janela.** Um único ponto de ancoragem (`CursorWindowPinning`) clampa primeiro ao frame da janela atada e depois à tela **que contém essa janela**; `NSScreen.main` deixa de ser fallback de posicionamento. Se o frame da janela atada muda entre ações, o cursor acompanha a janela mantendo a posição relativa dentro dela.
- **P3 — sempre visível enquanto atado.** Enquanto a sessão tem attachment vivo e a janela está on-screen, `visibilityAlpha` fica em 1 sem fade por idle. Fade/hide volta a valer quando o attachment se perde (janela fechada/minimizada/fora de tela); `idleExpireDelay` (45 s) continua expirando a sessão como hoje.
- **P4 — sem deriva parada.** Eliminar o idle breathing de posição (`idleBreathing`, `idleSeed`, `idleBreathOffsetX/Y`). A orientação continua assentando na home angle; a posição só muda por ação.
- **P5 — suites determinísticas.** Serializar as suites de cursor, isolar o estado de `CursorRuntime` por teste (reset explícito) e tornar os dwells das asserções explícitos, sem deletar nem enfraquecer asserção.

## Impact

- **Specs:** `cursor-overlay` (ancoragem, presença, determinismo de posição), `agent-feedback-overlay` (clamp de pointing usa a tela da janela atada).
- **Runtime:** `Cursor/AXCursorTargeting.swift`, `Cursor/CursorCoordinator.swift`, `Cursor/CursorModels.swift`, novo `Cursor/CursorWindowPinning.swift` (geometria de ancoragem + seam de teste para geometria de janela viva).
- **API surface:** nenhum campo some. `cursor.targetPointSource` deixa de emitir o sufixo `+visual_interest_offset` (valor de vocabulário, não campo); os textos de `cursor.warnings` de clamp passam a nomear a janela/tela atada. `API/**` está fora do escopo desta change — nenhuma doc de rota enumera esse vocabulário hoje.
- **Testes:** suites de cursor em `Tests/BackgroundComputerUseTests/` ganham cobertura de ponta==ação, clamp por janela, presença atada e ausência de drift, além do harness de determinismo.
