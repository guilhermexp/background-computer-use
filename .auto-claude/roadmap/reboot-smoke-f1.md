# Diagnóstico histórico — AX globalmente travado (pré-reboot, F1 click evidence)

Estado de tarefas, critérios de aceite e roteiro de smoke **não vivem aqui**. Donos canônicos:

- `openspec/changes/fix-uncontaminated-click-evidence/` (tasks e deltas do F1 click evidence)
- `openspec/changes/harden-bcu-runtime-excellence/` (smoke ao vivo assinado que superou este roteiro)

O único registro preservado abaixo é o diagnóstico do travamento do subsistema de
Accessibility do macOS, porque nenhum outro documento o cobre.

## Sintomas

- BCU retornava 0 janelas AX para Chrome, TextEdit e Finder.
- `macos-harness state TextEdit` (ferramenta independente) também retornava só
  `AXApplication`, 0 `AXWindow` — logo, não era bug do BCU.
- CGWindow continuava enxergando as janelas reais de TextEdit/Chrome.
- `AXIsProcessTrusted` permanecia `true` nas duas ferramentas.

## O que não resolveu

Reiniciar os serviços de usuário `universalaccessd` e `AccessibilityUIServer` e
relançar o app alvo: o AX seguiu travado. Só o reboot da máquina recuperou.

## Como reconhecer de novo

Se `list_windows` retorna 0 janelas AX para múltiplos apps ao mesmo tempo e uma
ferramenta AX independente concorda, o subsistema está travado globalmente — não
investigue o BCU nem enfraqueça heurísticas de settle; rebote a máquina.
