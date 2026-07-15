# Tasks: fix-agent-api-correctness

## 1. U2 — sleepRunLoop thread-aware
- [ ] 1.1 Tornar `Shared/RunLoopSupport.sleepRunLoop` thread-aware: `!Thread.isMainThread` && sem source anexado → `Thread.sleep(forTimeInterval:)`; senão `run(until:)`.
- [ ] 1.2 Preservar `run(until:)` nos call sites que bombeiam AXObserver (`WindowMotionBackend`, loop de projeção) e nos branches `Thread.isMainThread` do `CursorCoordinator`; alinhar a cópia shadow em `AXMenuPathActivator`.
- [ ] 1.3 Micro-teste que mede o tempo real de `sleepRunLoop` numa DispatchQueue concorrente (assert elapsed >= interval*0.9).

## 2. U3 — correções de contrato/self-doc
- [ ] 2.1 `RouteRegistry`: `includeMenuBar` defaultValue documentado = efetivo (`get_window_state` true, `annotate_window` false); corrigir a descrição copy-paste "annotation candidate set".
- [ ] 2.2 `APIDocumentation`: usage de `drag`/`resize` nomeia o space real (AppKit-global, bottom-left, logical points); `description` em `toX/toY` no RouteRegistry.
- [ ] 2.3 `description` do campo `key` do `press_key` (separador `+`, aliases command/cmd/meta/super, control/ctrl, option/alt, shift; exemplos).
- [ ] 2.4 APIConceptDTO "session" (header `X-Background-Computer-Use-Session`, 409/429) e "coordinates" (stub) no guide.

## 3. U4 — dedupe da resolução de janela
- [ ] 3.1 Promover `scoreWindow`/`resolveWindowElement` do `AXActionTargetResolver` de `private` para `internal`.
- [ ] 3.2 Deletar as cópias divergentes do `PressKeyRouteService`; apontar os call sites (linhas ~117, ~196) para o resolver.
- [ ] 3.3 Teste de fixture: 2 janelas do mesmo app sem AXWindowNumber, uma focada → `press_key` e `click` resolvem a mesma janela.

## 4. U5 — wait_for gone=true tolera janela fechada
- [ ] 4.1 No loop de poll e na captura final: `catch DiscoveryError.windowNotFound`; `gone=true` → `conditionMet=true` + nota "target window closed"; `gone=false` → `conditionMet=false` + nota; nunca 404.
- [ ] 4.2 Cobrir a race da captura final (janela fecha entre último poll e captura final).
- [ ] 4.3 Testes: gone=true com fechamento no loop e na captura final; gone=false com fechamento.

## 5. U6 — ações verdadeiras (SessionLimiter, errorResponse, campos mortos)
- [ ] 5.1 `RuntimeSessionLimiter`: contador por sessionID; `release()` decrementa e só limpa `activeSessionID` ao zerar.
- [ ] 5.2 `Router.errorResponse` default: incluir `String(describing: error)` na message; mapear captura/screenshot para `capture_failed`/`screenshot_failed` com recovery; usar o requestID real (não UUID novo).
- [ ] 5.3 Remover `verificationMode` do ScrollRequest + schema + doc + enum `ActionVerificationModeDTO`; atualizar `HardenedAgentAPITests` que lista o campo.
- [ ] 5.4 `imageMode` em ações: expor `postScreenshot: Screenshot?` na response quando `imageMode != omit` (click/press_key/select_text/perform_secondary_action) OU remover o campo dos schemas onde é morto (scroll/type_text/set_value). Decisão documentada no proposal se divergir.
- [ ] 5.5 Testes: SessionLimiter concorrente, errorResponse com causa, campo morto ausente do schema, imageMode coerente.

## 6. U7 — segurança proporcional
- [ ] 6.1 `RuntimeAuth`: comparação constant-time do token (XOR acumulado sobre [UInt8]).
- [ ] 6.2 Helper de escrita compartilhado com `createDirectory [.posixPermissions: 0o700]` + `setAttributes 0o600`; aplicar em manifest, PNGs de captura, debug-artifacts.
- [ ] 6.3 `DebugArtifactRecorder`: redigir `text`/`value` (typeText/setValue/pressKey) e `responseBody` de readText → `"<redacted len=N>"`; override `DEBUG_ARTIFACTS_RAW=1`.
- [ ] 6.4 Host guard no Router: rejeitar request cujo `Host` não comece com `127.0.0.1`/`localhost`.
- [ ] 6.5 Remover default `auth: .disabled` dos inits de `LoopbackServer`/`Router` (auth obrigatório; testes passam `.disabled` explícito).
- [ ] 6.6 Testes: constant-time helper (correção), redaction, Host guard aceita/rejeita, permissões 0600.

## 7. U8 — scripts da skill
- [ ] 7.1 `bcu-request.py` + `ensure-runtime.sh`: fallback de manifest via `getconf DARWIN_USER_TEMP_DIR` (shell) / `subprocess getconf` (python — NÃO `os.confstr('CS_DARWIN_USER_TEMP_DIR')`, lança ValueError no macOS) quando `TMPDIR` ausente; manter `BCU_MANIFEST_PATH` override.
- [ ] 7.2 `bcu-request.py`: `BCU_TIMEOUT` (default 30); para `/v1/wait_for`, derivar timeout de `timeoutSeconds + margem`.
- [ ] 7.3 `SKILL.md` frontmatter: `platforms: [macos]`.

## 8. Validação e fechamento
- [ ] 8.1 `swift build` limpo (código de produção compila).
- [ ] 8.2 Live smoke real: subir o app (`script/start.sh`), exercitar via curl os endpoints tocados — medir settle real (U2), `wait_for gone=true` com janela que fecha (U5), 2 requests concorrentes da mesma sessão (U6), Host guard rejeitando Host não-loopback (U7). Reportar observação concreta, não inferência.
- [ ] 8.3 `openspec validate fix-agent-api-correctness --strict`.
- [ ] 8.4 `swift test` fica pro CI (Fase 5) — esta máquina não tem Xcode.app/módulo Testing. Os unit tests escritos aqui devem compilar em intenção e ser rodados no CI.
- [ ] 8.5 RESULT block (assinatura de saída definida no brief do orquestrador).
