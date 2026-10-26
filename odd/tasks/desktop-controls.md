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

## Tasks

T0 | S7-S8 | inline baseline preservation, no writer | in_progress | commit: pending; preserve existing staged deletion and exclude SmartWindow.zip.
T1 | S1 | delegated writer, independent heavy unit (login service + General UI + isolated tests/docs) | pending | commit: pending; Risk: item 5 (OS login registration).
T2 | S4 | delegated writer, independent heavy unit disjoint from T1 (media service + notch controls + tests/docs) | pending | commit: pending; Risk: none pending implementation assessment.
T3 | S2 | inline overflow policy/search + tests/docs, after baseline | pending | commit: pending; preserve WindowManager.windows order and Option+1–9 indices.
T4 | S5 | inline per-display persistence/controllers/UI + tests/docs, after T1/T2 shared files return | pending | commit: pending; Risk: item 3 (shared widget/settings routing).
T5 | S3 | inline focus composition and one-click control + tests/docs, after T3/T4 | pending | commit: pending; preserve clock, windows, and music.
T6 | S1-S6 | final seam checks, high-risk independent verification, applicable native review and live debug review | pending | commit: pending; physical-notch and signed-install checks await available hardware/authorization, never inferred.

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
L5. Implementation conventions (not additional product requirements): use macOS 13 SMAppService status as startup truth; retain current window ordering and shortcut numbering in overflow search; focus mode is a global one-click view filter that does not erase widget preferences; per-screen overrides inherit global defaults and use stable display identity when available; retain click-to-open-player on artwork/text and use the playback indicator for controls. Native labels/artifacts remain English. Approx. 400 authored changed lines is a reviewability heuristic, not a code-size gate.
