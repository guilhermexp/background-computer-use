# Tasks

## 1. Presença da anchor sem contaminação do cursor (C1)

- [x] 1.1 Teste vermelho: cursor virtual estacionado sobre a anchor e página inalterada exige `ocrAnchorDisappeared` diferente de `true` e classificação `effect_not_verified`.
- [x] 1.2 Teste vermelho: captura limpa indisponível exige `ocrAnchorDisappeared: null` + `ocrAnchorDiagnostic`, sem contar como sinal.
- [x] 1.3 Prover um caminho de captura sem composição do overlay para uso exclusivo de evidência, mantendo a composição do cursor na imagem devolvida ao chamador.
- [x] 1.4 Fazer o teste de presença pós-clique (`ClickRouteService` + `OCRClickTargetResolver`) re-rodar OCR sobre a captura limpa.
- [x] 1.5 Teste provando que a imagem devolvida ao chamador continua com o cursor composto (não regredir a explicação visual).

## 2. Foco atribuível ao clique (C2)

- [x] 2.1 Teste vermelho: focus-without-raise do transporte, sem mais nenhuma mudança, exige `focusedElementChanged == false`.
- [x] 2.2 Teste vermelho: reordenação de nós antes do elemento focado, com foco parado, exige `focusedElementChanged == false`.
- [x] 2.3 Teste verde de não-regressão: movimento real de foco para outro elemento continua produzindo `focused_element_changed`.
- [x] 2.4 Amostrar o baseline de foco **após** o focus-without-raise do transporte em `NativeBackgroundClickTransport`/`ClickRouteService`.
- [x] 2.5 Trocar a comparação de foco de caminho posicional AX para identidade estável do elemento focado.
- [x] 2.6 Teste vermelho: churn de `renderedTextChanged`/`selectionSummaryChanged` causado somente pelo focus-without-raise é absorvido pelo baseline pós-focus e não torna `windowStillSettling` verdadeiro.
- [x] 2.7 Teste de não-regressão: churn que continua **depois** do baseline pós-focus permanece ambiente e continua bloqueando a escalação.
- [x] 2.8 Capturar o baseline completo de verificação após o focus-without-raise e antes do mouse event; comparar o pós-dispatch contra esse baseline, sem afrouxar o guard globalmente.

## 3. Um único veredito (C3)

- [x] 3.1 Teste vermelho: sinal computado depois do gate de escalação não pode elevar a classificação reportada a `success`.
- [x] 3.2 Teste vermelho: clique OCR sem sinal sólido, com janela quieta, alcança a escalação AX e, com efeito provado, reporta `finalRoute: coordinate_then_ax_hit_test` e `fallbackReason: coordinate_unverified_using_ax_hit_test`.
- [x] 3.3 Unificar os tiers: ou o sinal entra no veredito que gateia a escalação, ou não certifica sucesso.
- [x] 3.4 Teste de não-regressão do guard de efeito em voo: ambiente não-vazio ou `fullImageChangeRatio > 0` continua impedindo a escalação (não afrouxar).

## 4. Testes existentes que mudam por desenho

- [x] 4.1 `VerificationHonestyTests.structuralSignalsAreAccepted`: passar a exercitar evidência **limpa** para `ocrAnchorDisappeared` e `focusedElementChanged`, em vez de evidência sintética indistinguível da contaminada. Os dois sinais continuam suficientes quando sólidos.

## 5. Documentação

- [x] 5.1 `skills/background-computer-use/SKILL.md` e `API/APIDocumentation.swift`: registrar que anchor-disappearance é medida em imagem sem overlay e que foco só conta quando atribuível ao clique.
- [x] 5.2 `script/smoke_runtime.py`: reordenar as asserções de `chrome-ocr-click` para que o diagnóstico específico (escalação rodou e a página não mudou) não fique inalcançável quando a classificação for `success`.

## 6. Gates

- [x] 6.1 `swift build -c release` e `swift test`.
- [x] 6.2 `openspec validate fix-uncontaminated-click-evidence --strict`.
- [ ] 6.3 Smoke ao vivo com runtime instalado e Chrome — executado pelo orquestrador, não pelo worker.
