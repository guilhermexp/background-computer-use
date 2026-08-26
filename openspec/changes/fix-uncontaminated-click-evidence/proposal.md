## Why

A rota de clique certifica `success` com evidência que o **próprio runtime fabricou**. Medido ao vivo em 2026-08-26 pelo smoke do projeto (`script/smoke_runtime.py`, check `chrome-ocr-click`), idêntico no HEAD e no baseline `a33378d` — logo, pré-existente e não introduzido por `enhance-agent-surface-parity`:

```
fail chrome-ocr-click  click reported success but the page never showed 'Button clicked'
  classification=success  finalRoute=ocr_anchor_xy  dispatched=True
  intentSignals=['ocr_anchor_disappeared', 'focused_element_changed']   (HEAD)
  intentSignals=['ocr_anchor_disappeared']                              (baseline a33378d)
  ambientOnlySignals=[]  targetRegionChangeRatio=0  ocrAnchorDisappeared=True
```

Três causas distintas, todas verificadas no código:

- **O cursor virtual tapa a anchor e isso é lido como prova.** `ocrAnchorDisappeared` (`Actions/Click/ClickRouteService.swift:449`) é um teste de presença que **re-roda o Apple Vision** sobre o PNG model-facing (`OCRClickTargetResolver.swift:41-47` compara texto normalizado + ocorrência + proximidade de box, não id nem hash). Esse PNG tem o cursor virtual **composto dentro dele** (`Screenshot/ScreenshotCaptureService.swift:91-106`), e a rota estaciona o cursor exatamente no centro da anchor antes do clique (`Cursor/AXCursorTargeting.swift:113-118`). O cursor segue composto enquanto ativo dentro de `idleHideDelay` = 1,2 s (`Cursor/CursorModels.swift:270`), contra um settle de 0,35 s (`ClickRouteService.swift:55`): a imagem pré-dispatch não tem cursor sobre a anchor, a pós tem. `Cursor/CursorCoordinator.swift:605-621` **documenta esse risco verbatim** ("an occluded anchor counts as `ocrAnchorDisappeared` — the runtime would manufacture its own proof") e ele acontece de todo jeito.
- **O transporte muda o foco e isso é lido como prova.** `focusedElementChanged` (`ClickRouteService.swift:2480-2489`) dispara por desigualdade de `focusedNodeID` (inclusive nil↔valor) ou de título/descrição/papel. Mas `Actions/Click/NativeBackgroundClickTransport.swift:68-111` executa um focus-without-raise via `SLPSPostEventRecordTo` **antes** de postar qualquer mouse event, e o `nodeID` comparado é um caminho posicional de filhos AX (`AXRawCaptureService.swift:951-952`), então qualquer reordenação da árvore acima do nó focado também conta. O doc comment afirma que identidade e rótulos são estáveis; não são.
- **O veredito reportado não é o veredito que decidiu a recuperação.** A verificação tem dois tiers. O gate de escalação coordenada→AX (`ClickRouteService.swift:1288-1300`) exige `verified == false` e roda dentro de `executeCoordinateClick`, cujo `verifyClick` passa `ocrAnchorDisappeared: nil` (`:1981`). O sinal da anchor entra só depois, em `ocrVerification` (`:591`), e infla apenas a resposta final (`:497`). Consequência: um sinal pós-hoc cria um `success` que o gate nunca viu, e no HEAD quem fechou o gate foi `focused_element_changed` — ou seja, **o falso positivo suprimiu a escalação AX que faria o clique realmente funcionar**, já que `AXPress` no mesmo botão funciona (o próprio smoke passa em `chrome-ax-click`).

O sinal honesto estava presente o tempo todo: `targetRegionChangeRatio: 0`, computado sobre capturas de janela cruas, sem cursor e sem downscale (`ClickRouteService.swift:1184-1187, 1265-1268`). A página de fato não mudou.

Nenhum sinal aqui é condicionado por superfície: `ClickIntentVerifier.swift:87-92` é `if ocrAnchorDisappeared == true` e `if focusedElementChanged == true` puros, em contraste com `:96-99`, onde `windowTitleChanged` é explicitamente restrito a `webRendererSurface == false`.

## What Changes

Tese única: **a verificação não consome evidência que o runtime mesmo produziu, e o veredito reportado é o veredito que a escalação avaliou.**

- **C1 — Presença da anchor lida de imagem não desenhada pelo runtime.** O teste de presença pós-clique passa a re-rodar OCR sobre uma captura **sem o cursor virtual composto**, de modo que a oclusão pelo próprio cursor deixe de ser indistinguível do desaparecimento real da anchor. Quando essa imagem limpa não estiver disponível, `ocrAnchorDisappeared` vem `null` com `ocrAnchorDiagnostic` nomeando o motivo, e não conta como sinal — a regra fail-closed já vigente.
- **C2 — Mudança de foco só conta quando atribuível ao clique.** O baseline de foco é amostrado **depois** do focus-without-raise que o transporte executa, de modo que o foco setado pelo próprio transporte deixe de aparecer como efeito do clique. A comparação passa a usar identidade estável do elemento focado em vez do caminho posicional de filhos AX, para que reordenação de árvore acima do nó focado não conte. Não muda a semântica do sinal no verifier: corrige o que é medido.
- **C3 — Um único veredito.** Nenhum sinal computado após o gate de escalação pode elevar a classificação reportada. O veredito publicado na resposta é o mesmo que a escalação avaliou: ou o sinal entra antes do gate, ou não certifica sucesso.

## Impact

- **API surface:** compatível em forma; **comportamento muda**, e é a correção. Cliques que hoje vêm `success` sustentados por oclusão do próprio cursor ou por foco setado pelo próprio transporte passarão a vir `effect_not_verified` — e, quando a escalação AX conseguir agir, a vir `success` com `finalRoute: coordinate_then_ax_hit_test` e efeito real.
- **Runtime:** `Actions/Click/ClickRouteService.swift`, `Actions/Click/OCRClickTargetResolver.swift`, `Actions/Click/ClickIntentVerifier.swift`, `Screenshot/ScreenshotCaptureService.swift`, `Cursor/CursorCoordinator.swift`.
- **Testes que mudam por desenho:** `Tests/BackgroundComputerUseTests/VerificationHonestyTests.swift:57` (`structuralSignalsAreAccepted`) fixa hoje que `ocrAnchorDisappeared: true` isolado e `focusedElementChanged: true` isolado bastam para sucesso. Continuam bastando **quando não contaminados**; o teste precisa passar a exercitar evidência limpa em vez de evidência sintética indistinguível da contaminada.
- **Custo:** C1 pode exigir uma captura adicional sem cursor por clique OCR. C2 não acrescenta captura, apenas move o instante do baseline de foco.
- **Risco conhecido, a medir:** mesmo com o veredito corrigido, a escalação exige `windowStillSettling == false` (`ClickRouteService.swift:1296-1297`), isto é, ambiente vazio no tier base **e** `fullImageChangeRatio == 0`. Numa página viva isso pode re-suprimir a recuperação. Esse guard **não** deve ser afrouxado nesta change: ele existe para não atuar duas vezes num efeito lento. Se ele bloquear a recuperação na fixture do smoke, o achado é reportado com evidência, não contornado.
- **Docs/tests:** `API/APIDocumentation.swift`, `skills/background-computer-use/SKILL.md`, `script/smoke_runtime.py` (a ordem das asserções hoje esconde os diagnósticos mais específicos quando o gate mente).
