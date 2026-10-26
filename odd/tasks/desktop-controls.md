# SmartWindow desktop controls
Branch: `feat/desktop-controls` from `4a84454b6a28b5da002e993fcf7dd321dac523d9`; local-only feature-branch-chain delivery; forecast 1,500–2,200 new authored lines plus the already-approved baseline.
Checks: focused standalone Swift probes (isolated state), `swift build`, app UI inspection, and physical-notch verification only when a notched screen is available.

## Specs

S1. User: "1. Ah vale si". Accepted proposal: "**Inicio automático real.** El switch existe, pero todavía no registra la app para arrancar al iniciar sesión."
S2. User: "2. vale". Accepted proposal: "**Overflow de ventanas.** Cuando haya muchas pestañas, mostrar un `+N` con buscador en lugar de apretarlas."
S3. User: "3. va me gusta". Accepted proposal: "**Modo concentración.** Ocultar widgets secundarios con un clic y dejar solo ventanas, reloj y música."
S4. User: "4. dale". Accepted proposal: "**Controles multimedia.** Play/pausa y siguiente/anterior en un pequeño desplegable del badge."
S5. User: "5. uf genial". Accepted proposal: "**Ajustes por monitor.** Elegir dónde mostrar cada widget y si querés Now Playing en todas las pantallas."
S6. User: "vale si notshc fisico  vaaa deale todo ese work em saviisas paraerevisar". Accepted recommendation: "También probaría el notch físico y los permisos de la app instalada antes de publicar otra versión."
S7. User decision: "Guardar la base en commits locales"; option description: "Separar lo anterior en commits por tema y desarrollar las mejoras en una rama. Sin push, instalación ni cambios al ZIP existente."
S8. User decision: "Rama de trabajo con bloques encadenados — recomendado"; option description: "Una rama agrupa la mejora y cada bloque queda preparado para revisarse por separado, con commits por comportamiento."

S9. User routing correction: "el worker no sirve por que no tengo cuota jaja te toca hacerlo tu mismo".

S10. User: "dale y crao de nuevo el build". Accepted recommendation: "Recomiendo tabs compactas según el contenido, separación uniforme y título de ventana al pasar el cursor. Mantendría el verde activo, la numeración y el `+N` buscable."

## Tasks

T0 | S7-S8 | inline baseline preservation, no writer | done | commits: 624323d (metrics/Finder), 8729c58 (media), cc19a24 (Settings), f047c07 (Tailscale), 2aae01e (keyboard), e6cbd5c (docs/license/tracker); build and baseline probes passed; SmartWindow.zip excluded.
T1 | S1,S9 | inline | done | commit: 4406495; RED/GREEN login probe and build passed; native medium, reviewDue=false; Risk: item 5; independent proof tracked in T6.
T2 | S4,S9 | inline | done | commit: 9d91477; transport RED/GREEN, unchanged parser differential, build passed; Risk: none.
T3 | S2,S10 | inline | done | commits: 6d875fa (overflow), eee3551 (compact tab geometry/hover context); RED/GREEN updated width probe, equal-width/search differential, seven regression probes and build passed; live screenshot verified compact spacing; native medium/under_budget, no separate verifier required for this fix; Risk: none.
T4 | S5 | inline | done | commit: 79bc5de; RED/GREEN isolated-suite preferences probe and build passed; native medium, reviewDue=false; Risk: item 3, independent/multi-monitor proof in T6.
T5 | S3 | inline | done | commit: 0aec687; RED/GREEN isolated focus/display preferences probe and build passed; Risk: item 3, native medium/under_budget (reviewDue=false); independent proof in T6.
T6 | S1-S6 | inline self-verification; independent proof unavailable | blocked | verified source tip: eee3551; all seven probes and latest build passed (job-17); compact left-tab screenshot verified. Awaiting independent reviewer/quota, physical-notch hardware and signed-install authorization. General UI observed; remaining live UI proof incomplete. No native review was due for assessed work units.

## Log

L1. Original request verbatim:
1. Ah vale si  
2. vale 
3. va me gusta
4. dale
5. uf genial 
vale si notshc fisico  vaaa deale todo ese work em saviisas paraerevisar

L2. User approved baseline local commits and feature-branch-chain organization through the two structured questions; exact choices are S7-S8. Publishing, installing, and modifying SmartWindow.zip are not authorized.
L3. Exploration: main HEAD was 4a84454b6a28b5da002e993fcf7dd321dac523d9. Existing approved working-tree changes span ~2,500 tracked diff lines plus new keyboard/Tailscale services and probes. SmartWindow.zip was modified before implementation and must remain untouched/uncommitted. Only LG ULTRAWIDE is connected (2560×1080, safeAreaInsets.top = 0); physical-notch proof is unavailable until the MacBook display is open.
L4. Routing: startup registration and playback controls are independent several-file units and will launch together with disjoint allowed edit surfaces. Overflow, per-screen settings, and focus mode share composition/persistence files and stay inline in dependency order. Mapping agent mvpmdsc6-2-l813 returned path:line evidence; no source writes occurred during exploration.
L6. Baseline preservation completed as six thematic local commits through e6cbd5c. The pre-existing media and Settings rewrites exceed the ~400-line heuristic but were kept coherent rather than cosmetically fragmented. An inherited whitespace-only line in Info.plist was fixed before staging. Plain diff-check flags only verbatim user trailing spaces in this log; the quoted request is intentionally preserved. Source/docs whitespace checks passed. Full baseline build and both standalone probes passed; keyboard live switching was skipped in this baseline rerun (it was previously verified and restored). No new implementation/native review candidate was introduced by this archival preservation step. T1 and T2 launch together; the visible todo groups their parallel execution into one in-progress item.

L5. Implementation conventions (not additional product requirements): use macOS 13 SMAppService status as startup truth; retain current window ordering and shortcut numbering in overflow search; focus mode is a global one-click view filter that does not erase widget preferences; per-screen overrides inherit global defaults and use stable display identity when available; retain click-to-open-player on artwork/text and use the playback indicator for controls. Native labels/artifacts remain English. Approx. 400 authored changed lines is a reviewability heuristic, not a code-size gate.

L7. Both background writers failed before delivering work: mvpmvz8h-4-bmj0 (T2) and mvpmvz8f-3-qmkn (T1), each with "assistant reported an error" and no further diagnostics. No automatic retry was made. Git inspection confirms no implementation files changed; only this tracking document and the pre-existing excluded ZIP remain dirty. T1/T2 are blocked on writer availability. T3 has been read for implementation but no new source or probe was written. The entire five-feature implementation remains unimplemented; T0 alone is complete. Need an explicit decision about an alternative available execution route (Claude Code) or waiting for the normal workers to be restored.

L8. User correction verbatim: "el worker no sirve por que no tengo cuota jaja te toca hacerlo tu mismo". Resume inline without retries, alternate paid agents, or a claimed independent verifier. Source state reconciled with the tracker and committed baseline. All five implementation tasks remain authorized. Physical-notch/signed-install evidence remains unavailable until hardware/authorization is supplied.

L9. T1: RED failed "registers with macOS"; GREEN stdout "PASS: login item registration states and failures", exit 0. swift build passed. No host login item was registered/unregistered by tests. Legacy preference never auto-registers. Commit 4406495; native assessment medium/under_budget (reviewDue=false), escalated item 5 requires independent verification, unavailable with user's exhausted worker quota and tracked in T6. Next: transport controls.

L10. Implementation checkpoints: T2 9d91477 (transport routing and paused/idle parser probe; parser differential against preceding code matched exit/stdout/stderr). T3 6d875fa (overflow budget/search RED/GREEN; initial build failed on an incorrect optional icon reference/type-check expression; corrected row built successfully). T4 79bc5de (isolated display-inheritance/persistence/reset RED/GREEN; build passed). T5 0aec687 (global focus RED/GREEN with per-screen overrides preserved; build passed). All technical UI/docs are English. No playback or startup registration was changed by tests.

L11. Final self-verification job-15: all seven standalone probes passed (login, media, overflow, display preferences, focus, Tailscale, keyboard) and swift build passed, exit 0. Keyboard live switching intentionally skipped in this suite; previous baseline live check was already performed and restored. No SwiftPM test target exists. Native assessments for T1/T4/T5 returned medium/under_budget and reviewDue=false, so no lineage/reviewer/approval was created. Explicit risk escalations require a separate verifier; quota is exhausted and the parent does not claim its own readback is independent verification.

L12. Debug app job-16, PID 53765, runs .build/out/Products/Debug/SmartWindow --settings without installing. General pane tree/screenshot verified the disabled unbundled launch-at-login switch, Focus control, and Displays sidebar. External-screen screenshot observed focus-on layout with readable window tabs, clock and moon; no supported-player badge was visible. Settings closed during inspection; fresh Orca status returned window_not_found and list-windows returned no windows. No repeated restart or forced reopening was attempted. Displays-pane interaction, overflow/media popovers, real second-monitor reconnection and physical-notch geometry remain unverified live. Only LG ULTRAWIDE is attached; installed/signed permissions/login-item proof is not authorized. The debug process is left running for user review. The previously running baseline debug app was intentionally terminated (job-7 exit 143), not a test failure. ZIP remains untouched/uncommitted. S1-S5 implementation and automated self-checks passed; S6 and independent proof remain blocked, so the overall feature is not claimed fully verified.

L13. User reported left-tab UI using screenshot at 2.35.06 PM; read-only review reproduced wide uneven gaps, larger active background, redundant > Orca text and indistinguishable same-app windows. Cause: a 150pt outer frame wraps MiniTabView's narrower intrinsic background. User authorization verbatim: "dale y crao de nuevo el build". Reopen T3 only; implement the accepted compact/content-bounded layout and hover titles inline, preserve search/ordering/shortcuts, build and relaunch the debug executable. T6's independent/hardware/installed-app blockers remain unchanged.

L14. S10 fix completed in eee3551. RED: "tabs size to content within readable bounds" failed before changing geometry. GREEN: measured bounded widths and content-aware overflow passed; prior search and equal-width budget examples matched base exit/stdout/stderr in a scratch differential. Job-17 build and seven regression probes passed; keyboard --switch intentionally skipped. New debug job-18/PID 77351 runs without --settings. .build/review/tabs-after.png confirms consistent compact backgrounds/gaps and no redundant active-app suffix; hover help compiled but was not visually exercised. Native medium, reviewDue=false, independentVerifier=false for this bounded fix. ZIP SHA-256 stayed adde4548bb97efe4d1120486c56aa201a5aaaa5c57a6cd6c9ea25290765445cc before/after; no install/push. Old debug job-16 exit 143 was intentional replacement. Existing T6 blockers are not cleared by this visual correction.
