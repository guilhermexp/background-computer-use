# Project: background-computer-use

Servidor HTTP loopback (macOS) que controla e lê janelas nativas em background **sem roubar o ponteiro do usuário**. O cliente é um agente de IA que fala via `curl`/HTTP; toda ação retorna verificação automática de efeito com evidência.

## Tech stack

- **Swift 6.2**, `platforms: [.macOS(.v14)]` (macOS 14 mínimo). O app/runtime usa somente SDKs Apple (AppKit, ApplicationServices, CoreGraphics, Vision); dependências externas ficam restritas ao target de testes.
- **Package.swift:** library `BackgroundComputerUseKit` (target `BackgroundComputerUse`) + executable `BackgroundComputerUse` (target `BackgroundComputerUseServer`, trivial: `BackgroundComputerUseServer.run()`).
- **Testes:** Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`). **Não** XCTest. `Package.swift` fixa `swift-testing` em `swift-6.2.3-RELEASE` como dependência exclusiva do test target, permitindo `swift test` também em instalações de Command Line Tools sem o módulo `Testing` embutido.

## Convenções

- **Camadas** (por diretório, target único): `API/` (Router, RouteRegistry, HTTP, auth) · `Actions/<Nome>/` (RouteServices, um por rota mutante) + `Actions/Shared/` · `StatePipeline/` (captura AX → projeção) · `Screenshot/` · `Cursor/` · `Contracts/` (DTOs Codable públicos, camada folha) · `Runtime/` (RuntimeServices, filas) · `App/` (facade pública, bootstrap). Regra: `Actions` consome `StatePipeline`/`Cursor`, não o contrário.
- **RouteService read-act-read:** capture (pipeline AX) → validar request/stateToken → resolveTarget → safety gate → cursor prepare → dispatch (AX action ou native transport) → reread/verify → response com classificação verifier-first (`success`/`effect_not_verified`/`verifier_ambiguous`/`unsupported`). Erro de background é reportado, nunca escondido roubando foco.
- **Self-documentation:** `GET /v1/routes` (RouteRegistry + APIDocumentation) é a fonte de verdade do contrato para o agente. Todo campo de request/response deve estar documentado lá e bater com o DTO real.

### 5 pontos de wiring de uma rota nova (aditivo puro)

1. `API/RouteRegistry.swift` — `case xxx` no enum `RouteID`; `RouteDescriptorDTO`; branch em `requestSchema`/`responseSchema` (fonte do strict decode `requestFieldNames`).
2. `Runtime/RuntimeServices.swift` — declarar/instanciar `XxxRouteService`; `func xxx(...)` envolvendo com `execute(routeID:target:)`.
3. `API/Router.swift` — `case (.post, "/v1/route_name")` chamando `decodeAndExecute`; se mutante, incluir em `isActionRoute`.
4. `App/BackgroundComputerUseRuntime.swift` — facade pública: `public func xxx(...)` espelhando RuntimeServices.
5. `Contracts/XxxContracts.swift` — request/response `public` + `Codable` com construtores públicos (validado por `RuntimeFacadePublicAPITests`, import não-`@testable`).

## OpenSpec

- Changes em `openspec/changes/<slug>/`: `proposal.md` (`## Why` / `## What Changes` / `## Impact`), `tasks.md` (checklist `- [ ] N.M`, última task sempre `swift test` + `openspec validate <slug> --strict` + live smoke), `specs/<capability>/spec.md` (delta `## ADDED/MODIFIED Requirements` → `### Requirement:` SHALL → `#### Scenario:` WHEN/THEN).
- Slug começa com letra (nunca prefixo de data — quebra `openspec status`). Archive prefixa a data automaticamente.
- Gate: `openspec validate <slug> --strict` antes de arquivar.

## Segurança (postura)

Ferramenta local single-user. Bind restrito a 127.0.0.1 (porta efêmera), token de 256 bits (SecRandomCopyBytes) obrigatório em todo `/v1` (só `/health` é aberto), manifest em `$TMPDIR/background-computer-use/runtime-manifest.json`. Loopback **não** é boundary de usuário — outro usuário local alcança a porta, então token é a barreira. Nonce/replay é desnecessário (sem rede no meio).

`POST /v1/run_script` amplia explicitamente a autoridade desse token: além das ações UI verificadas, ele autoriza fonte AppleScript/JXA arbitrária e, portanto, controle de qualquer aplicação scriptable acessível ao usuário. A lane não promete verificação de efeito; o chamador relê estado para confirmar o resultado. O controle compensatório é rastreabilidade: toda tentativa é gravada em `$TMPDIR/background-computer-use/audit/script-executions.jsonl`, arquivo `0600` dentro de diretório `0700`, enquanto a fonte é redigida dos artefatos de debug comuns.

## Build / run

- `script/build_and_run.sh [build|run]` — build + `.app` assinada em `dist/` + `~/Applications`.
- `script/start.sh` — sobe o runtime + polling do manifest + valida `/health`.
- `script/package_release.sh` — build release + zip + sha256.
- `script/smoke_runtime.py` — smoke E2E (requer app rodando + Chrome + permissões AX/Screen Recording).
