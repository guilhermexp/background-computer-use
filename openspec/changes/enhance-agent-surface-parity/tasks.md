# Tasks

## 1. Sinal de intent escopado à web area (P1)

- [x] 1.1 Teste vermelho: clique em superfície web cujo efeito é texto **fora** do frame do alvo, com baseline pré-clique estável, exige `success` e `web_area_text_changed` em `intentSignals`.
- [x] 1.2 Teste vermelho: baseline pré-clique **instável** (duas amostras diferentes) exige `effect_not_verified`, com a mudança em `ambientOnlySignals` e diagnóstico de baseline.
- [x] 1.3 Extrair o texto da subárvore `AXWebArea` (excluindo chrome do browser) como fonte do diff, reutilizável pelo verifier.
- [x] 1.4 Amostrar o texto da web area duas vezes antes do dispatch em `ClickRouteService` e propagar o baseline para `ClickIntentVerifier.assess`.
- [x] 1.5 Adicionar `IntentSignal.webAreaTextChanged` e o predicado condicionado (`webRendererSurface` + dispatch OK + baseline estável) em `ClickIntentVerifier`; manter `renderedTextChanged` ambiente em toda superfície.
- [x] 1.6 Diagnóstico quando o baseline não pôde ser estabelecido; ausência de baseline nunca conta como evidência.

## 2. Payload enxuto (P2)

- [ ] 2.1 Teste vermelho: nó de estado não contém locator duplicado com `ancestorFingerprints`/`rolePath`; `nodeID`, `refetchFingerprint` e `displayIndex` presentes.
- [ ] 2.2 Teste vermelho de orçamento: custo serializado por nó abaixo do teto declarado, com a medição no texto da falha.
- [ ] 2.3 Remover `.prettyPrinted` e `.sortedKeys` do encoder em `API/JSONSupport.swift`.
- [ ] 2.4 Deixar um único locator canônico no DTO de nó em `StatePipelineExperiment.makeSurfaceNodeDTO`; remover as cópias aninhadas da resposta.
- [ ] 2.5 Confirmar que os quatro `target.kind` resolvem inalterados após o trim (teste de round-trip leitura → ação).

## 3. Identidade de DOM e consulta dirigida (P3)

- [ ] 3.1 Teste vermelho: nó de elemento HTML com `id` expõe `domIdentifier`; nó sem valor omite o campo.
- [ ] 3.2 Acrescentar `AXDOMIdentifier` à allowlist `AXAttributeNames` e ao caminho de captura; expor como `domIdentifier` no DTO de nó.
- [ ] 3.3 Teste vermelho: `find_elements` por papel + substring devolve só os nós casados, com `stateToken` e `interactionToken` da mesma leitura; query sem match devolve lista vazia com sucesso.
- [ ] 3.4 Implementar `Actions/FindElements/FindElementsRouteService.swift` (read-only) reaproveitando a projeção existente.
- [ ] 3.5 Wiring da rota (5 pontos): `RouteRegistry` (enum + descriptor + schemas), `RuntimeServices`, `Router`, facade `BackgroundComputerUseRuntime`, `Contracts/FindElementsContracts.swift`.
- [ ] 3.6 Teste de contrato: campos de request/response documentados em `/v1/routes` batem com os DTOs reais.

## 4. Lane de script auditada (P4)

- [ ] 4.1 Teste vermelho: script que retorna valor devolve `stdout` e `status`; script que falha devolve `stderr` com status não-zero, sem erro de transporte.
- [ ] 4.2 Teste vermelho: script que estoura o timeout devolve `timedOut: true` sem processo sobrevivente; timeout acima do máximo é limitado e o valor efetivo é reportado.
- [ ] 4.3 Teste vermelho: resposta de `run_script` não carrega `classification`.
- [ ] 4.4 Implementar `Actions/Script/ScriptRouteService.swift` com execução limitada por deadline e terminação da árvore de processo.
- [ ] 4.5 Log de auditoria `0600` em diretório `0700`, registrando também recusas e timeouts.
- [ ] 4.6 Wiring da rota (5 pontos) e inclusão em `isActionRoute` para exclusão de sessão e throttling.
- [ ] 4.7 Self-doc em `/v1/routes` declarando lane sem verificação de efeito e a instrução de confirmar efeito relendo estado.

## 5. Documentação

- [ ] 5.1 `skills/background-computer-use/SKILL.md`: `find_elements` como atalho de leitura, `domIdentifier` como alvo em web content, o novo `web_area_text_changed` com sua regra de baseline, e a lane `run_script` marcada como não verificada.
- [ ] 5.2 `openspec/project.md`: atualizar a seção de postura de segurança com a autoridade ampliada pelo lane de script.

## 6. Gates

- [ ] 6.1 `swift build -c release` e `swift test`.
- [ ] 6.2 `python3 script/smoke_runtime.py` contra o runtime instalado, cobrindo o caso web de P1 e as duas rotas novas.
- [ ] 6.3 `openspec validate enhance-agent-surface-parity --strict`.
