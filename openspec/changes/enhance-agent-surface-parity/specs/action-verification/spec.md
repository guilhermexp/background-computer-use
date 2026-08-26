# action-verification Specification

## ADDED Requirements

### Requirement: Web-area text change is an intent signal only against a stable baseline

On a web renderer surface, a change in the text of the target window's `AXWebArea` subtree SHALL count as the intent signal `web_area_text_changed`, but only when the runtime first proved the page was not rewriting itself. Before dispatching, the runtime SHALL sample the web-area text twice and compare them. The post-click change SHALL earn intent credit only when the dispatch succeeded, the surface is a web renderer, the two pre-dispatch samples were identical, and the post-settle text differs from them. When the pre-dispatch samples differ, the page is self-mutating and the post-click change SHALL be reported in `ambientOnlySignals` with a diagnostic, never as intent. The scope SHALL be the web area only, excluding browser chrome, because chrome text such as a per-tab memory readout rewrites itself without any click. Whole-window `renderedTextChanged` SHALL remain an ambient signal on every surface.

#### Scenario: Genuine page effect outside the clicked element is verified

- **WHEN** a click dispatches on a web renderer surface against a button whose handler rewrites a different element's text, the two pre-dispatch web-area samples were identical, and the post-settle web-area text differs
- **THEN** the response classifies the click as `success` and `verification.intentSignals` contains `web_area_text_changed`

#### Scenario: Self-mutating page earns no intent credit

- **WHEN** the two pre-dispatch web-area samples differ from each other, and the post-settle web-area text also differs
- **THEN** `verification.intentSignals` does not contain `web_area_text_changed`, the change is reported in `verification.ambientOnlySignals`, and a diagnostic states that the pre-dispatch baseline was unstable

#### Scenario: Baseline that cannot be established fails closed

- **WHEN** the runtime cannot sample the web-area text before dispatch
- **THEN** `web_area_text_changed` is not awarded, a diagnostic names the reason, and the absence of the baseline never counts as evidence

#### Scenario: Browser chrome churn is not a page effect

- **WHEN** the only text that changed between the pre-dispatch and post-settle reads lies outside the `AXWebArea` subtree, such as a tab's memory readout
- **THEN** `web_area_text_changed` is not awarded, because the diff is scoped to the web area

#### Scenario: Native surfaces are unaffected

- **WHEN** a click dispatches against a window that does not project a web renderer profile
- **THEN** `web_area_text_changed` is never awarded, and whole-window `renderedTextChanged` remains ambient exactly as before
