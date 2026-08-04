# Tasks

## 1. Gate de sucesso honesto

- [x] 1.1 Teste vermelho: evidência só com `renderedTextChanged`/`selectionSummaryChanged` verdadeiros e `targetRegionChangeRatio: 0` exige `effect_not_verified`.
- [x] 1.2 Extrair o gate para `Actions/Click/ClickIntentVerifier.swift` com limiar declarado, `intentSignals[]` e `ambientOnlySignals[]`.
- [x] 1.3 Aplicar o mesmo gate em `coordinate_xy`, `ocr_anchor_xy`, `semantic_ax` e `ax_element_pointer_xy`; remover a exceção permissiva das AX selection plans.

## 2. Evidência sempre computada

- [x] 2.1 Teste vermelho: `targetRegionChangeRatio` computado (não `null`) quando existe região de alvo; `targetRegionDiagnostic` presente quando não dá para computar.
- [x] 2.2 Resolver região de alvo por rota (box da anchor, frame AX, caixa de sondagem de 48 pt no ponto) e capturar imagens de janela antes/depois em todas as rotas de clique.
- [x] 2.3 Adicionar `targetRegionChangeThreshold`, `targetRegionDiagnostic`, `ocrAnchorDiagnostic`, `intentSignals`, `ambientOnlySignals` ao contrato de verificação e à self-doc.

## 3. OCR utilizável

- [x] 3.1 Teste vermelho: `performance.ocrMs` presente e deadline de OCR retorna `recognition_failed` com diagnóstico.
- [x] 3.2 `OCRRecognitionService` com deadline explícito e medição de duração.
- [x] 3.3 Prewarm não-bloqueante no `RuntimeBootstrap` e `ocrMs` no `WindowStateService`.

## 4. Smoke resiliente

- [x] 4.1 Encapsular requests do runner: timeout/exceção viram `fail`, nunca crash da run; orçamento maior na primeira chamada com OCR.
- [x] 4.2 Check dedicado de OCR aquecido abaixo de limite declarado.
- [x] 4.3 Executar o caminho `ocr_anchor` incondicionalmente e registrar a classificação honesta, com `fail`/`skip` motivado quando o limite do Chromium aparecer.

## 5. Documentação

- [x] 5.1 SKILL.md: loop OCR→click→reread, staleness fail-closed do `interactionToken`, custo do primeiro OCR, limite empírico do web content de Chromium; remover retry cego de coordenada.

## 6. Gates

- [x] 6.1 `swift build -c release` e `swift test`.
- [x] 6.2 `python3 -m py_compile script/smoke_runtime.py skills/background-computer-use/scripts/bcu-request.py` e `python3 script/smoke_runtime.py` contra o runtime instalado.
- [x] 6.3 `openspec validate fix-verification-honesty --strict`.
