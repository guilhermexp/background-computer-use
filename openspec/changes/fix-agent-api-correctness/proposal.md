## Why

A auditoria multi-dimensão (71 findings, 35 verificados adversarialmente com arquivo:linha) achou bugs confirmados que enganam o agente-cliente hoje — não são regressões do núcleo, são buracos que já mordem:

- **A self-doc de `/v1/routes` mente sobre defaults.** `get_window_state` anuncia `includeMenuBar` default `false` mas usa `?? true`; `annotate_window` anuncia `true` mas usa `?? false`. O agente confia na doc e gasta chamadas debugando.
- **`sleepRunLoop` é no-op em threads GCD.** `RunLoop.run(until:)` retorna imediato em thread sem source — os settle delays antes da verificação e o poll do `wait_for` viram zero, gerando falsos `effect_not_verified` e busy-poll.
- **`wait_for gone=true` retorna 404** no exato momento em que a janela-alvo fecha — o caso mais comum de "sumir" vira erro.
- **`internal_error` engole a causa real** — falha de captura/screenshot chega ao agente como "Route X failed." sem pista.
- **`press_key` pode resolver uma janela diferente de `click`** — `scoreWindow`/`resolveWindowElement` estão duplicados e divergentes (pesos diferentes).
- **A exclusão de sessão vaza** — `RuntimeSessionLimiter` sem refcount libera a exclusão com uma ação da mesma sessão ainda em voo.
- **Campos de request documentados são silenciosamente ignorados** — `verificationMode` (scroll) e `imageMode` (ações) não têm efeito observável.
- **Vetores de segurança baratos** — token comparado não-constant-time, manifest/PNGs sem permissão explícita, texto digitado persistido em claro nos debug-artifacts, sem Host guard.

## What Changes

- **U2** `sleepRunLoop` thread-aware: dorme de verdade em threads GCD (`Thread.sleep`), preserva `run(until:)` nos call sites que bombeiam AXObserver / rodam na main thread.
- **U3** Correções de contrato/self-doc: `includeMenuBar` documentado = efetivo; `drag`/`resize` nomeiam o coordinate space real (AppKit-global, bottom-left); `description` de chord no campo `key`; concepts "session" e "coordinates" no guide.
- **U4** Dedupe da resolução de janela: `press_key` usa `scoreWindow`/`resolveWindowElement` do `AXActionTargetResolver` (deletar as cópias divergentes).
- **U5** `wait_for gone=true` reconhece janela fechada como condição satisfeita, não 404 (loop + captura final).
- **U6** `RuntimeSessionLimiter` com refcount; `internal_error` carrega `String(describing: error)` + códigos próprios pra captura/screenshot + requestID real; `verificationMode` removido (YAGNI); `imageMode` em ações vira `postScreenshot` opcional ou é removido dos schemas onde é morto.
- **U7** Segurança proporcional: token constant-time, permissões 0600/0700 (manifest/PNGs/debug-artifacts), redaction de `text`/`value` nos debug-artifacts, Host guard loopback, auth obrigatório (remover default `.disabled`).
- **U8** Scripts da skill: fallback de manifest via `getconf DARWIN_USER_TEMP_DIR` quando `TMPDIR` ausente, `BCU_TIMEOUT` configurável, `platforms: [macos]`.

Nonce/replay no auth fica **fora** (teatro em loopback single-user).

## Impact

- **API surface:** só correções de doc (defaults, coordinate space, chord) e remoção de campos mortos; `postScreenshot` é campo novo opcional. Defaults preservam o comportamento atual — sem quebra pro agente-cliente.
- **Runtime:** `sleepRunLoop` (Shared/RunLoopSupport + call sites de settle), `WaitForRouteService`, `RuntimeSessionLimiter`, `AXActionTargetResolver`/`PressKeyRouteService`, `Router.errorResponse`.
- **Security:** `RuntimeAuth`, `RuntimeBootstrap`, `ScreenshotCaptureService`, `DebugArtifactRecorder`, `LoopbackServer`.
- **Docs/tests/skill:** RouteRegistry/APIDocumentation, scripts da skill, e unit tests dos fixes (executados no CI — Fase 5 — pois esta máquina não tem Xcode.app/módulo Testing; validação local via `swift build` + smoke real).
