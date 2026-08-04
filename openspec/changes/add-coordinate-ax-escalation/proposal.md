## Why

O clique por coordenada e por âncora OCR não atua em web content de Chromium. Medido em 2026-08-04 contra o runtime instalado, com o gate honesto de verificação já em vigor (fixture `bcu-smoke-runtime.html` no Google Chrome, botão HTML `BCU Smoke Button`):

- **Nenhuma variante de conteúdo de evento resolve.** Nove variantes do transporte foram construídas e medidas uma a uma: evento derivado de `NSEvent` ou de `CGEventSource`; `mouseEventSubtype` 3, 0 e intocado; com e sem o par primer em `(-1, -1)`; estampas completas, mínimas e nenhuma; `CGEventSource(.hidSystemState)` e `.privateState`. Todas retornaram `clicked=false`, `intentSignals=[]`, `targetRegionChangeRatio=0`, tanto com o Chrome em background quanto em foreground.
- **O mesmo evento, entregue pelo tap global, clica.** Postado sem estampas em `CGEvent.post(tap: .cghidEventTap)`, o botão reage (`Button not clicked` → `Button clicked`, `classification: success`). Logo o evento e a coordenada estão corretos: a coordenada foi confirmada por pixel (o cursor do agente aparece exatamente sobre o botão) e coincide com o centro do frame AX do controle.
- **A entrega dirigida por pid é o ponto de falha.** `SLEventPostToPid` não é honrado pelo Chromium — nem no web content, nem na própria UI do browser (clique injetado numa aba inativa não troca de aba). Aplicativos AppKit nativos continuam funcionando pelo mesmo caminho.
- **AX no mesmo controle funciona.** `target.kind=display_index` no mesmo botão retorna `classification: success` / `finalRoute: semantic_ax` e a página reage.

Resultado prático antes desta change: a capacidade central entregue em `1ebacd4` (clicar em superfície web a partir de âncora OCR) despachava no vácuo e devolvia `effect_not_verified`, sem caminho de recuperação.

## What Changes

- **Escalada por hit-test AX.** Quando um clique de coordenada ou de âncora OCR despacha e a verificação não prova efeito, o runtime faz hit-test de acessibilidade **no mesmo ponto de tela** e aciona `AXPress` no elemento encontrado. Reverifica com o mesmo gate honesto; só adota o resultado se ele provar efeito.
- **Elegibilidade explícita.** Só é acionado elemento que expõe `AXPress` e cujo frame cobre o ponto com dimensões mínimas reais. Isso rejeita nós que a árvore mantém para conteúdo fora da viewport — Chromium reporta controle rolado para fora com frame colapsado (medido: botão 177x1), e acioná-lo agiria em algo que ninguém apontou.
- **Relato da escalada.** Nova rota final `coordinate_then_ax_hit_test` e novo `fallbackReason` `coordinate_unverified_using_ax_hit_test`; `transports[]` ganha a tentativa `ax_perform_action` com `liveElementResolution: "ax_hit_test_at_click_point"` e `routeSteps[]` registra o passo. Sucesso pela escalada nunca é reportado como sucesso do transporte de coordenada.
- **Diagnóstico do limite residual.** Coordenada despachada sem efeito em superfície de renderer web passa a `failureDomain: app_specific_semantics` com aviso `renderer_ignores_coordinate_injection`, nomeando o fato medido e indicando `target.kind=display_index`/`node_id`.
- **Smoke.** O caminho OCR passa a ser exercido de ponta a ponta com asserção de efeito real na página; a fixture é levada ao topo quando uma aba reusada ficou rolada e é recarregada entre os caminhos OCR e AX, porque o botão é idempotente; âncoras OCR são casadas com tolerância a erro de reconhecimento do Vision.
- **SKILL.md.** Passa a descrever a escalada, o que ela exige da árvore AX e o limite residual (superfície sem nó AX no ponto continua sem caminho de ponteiro em background).

## Impact

- Especificação afetada: `action-verification`.
- Código: `Sources/BackgroundComputerUse/Actions/Click/ClickRouteService.swift`, `Sources/BackgroundComputerUse/Actions/Click/AXPointPressEligibility.swift`, `Sources/BackgroundComputerUse/Contracts/ClickActionContracts.swift`, `script/smoke_runtime.py`, `skills/background-computer-use/SKILL.md`.
- Compatibilidade: aditiva. Campos existentes mantêm significado; `finalRoute` e `fallbackReason` ganham valores novos que consumidores antigos veem como desconhecidos apenas quando a escalada ocorre.
- Custo: a escalada roda somente depois de um clique de coordenada não verificado, e acrescenta um hit-test AX mais uma releitura de estado nesse caso.
