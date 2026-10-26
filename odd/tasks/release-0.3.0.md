# SmartWindow 0.3.0 release
Publish the approved desktop-controls work to main, a signed/notarized GitHub ZIP and the authorized Homebrew tap. No local installation; no force-push; preserve pre-existing artifacts and unrelated changes.
The user accepted the remaining independent, physical-notch and signed-installed-app verification gaps before authorizing publication.

## Specs

S1. User: "dale entonces vamos a generar el zip , todos los commits y push a main y en brew tap actualizar la veersoin no ?? o que ??".
S2. User selected: "Publicar v0.3.0 y actualizar Homebrew" (answer token: "publish_v030_and_tap"). Approved description: "Integro los commits en main sin force-push, publico el ZIP y la release, y actualizo versión/checksum en el tap indicado. Preservo una copia del ZIP previo y documento las pruebas pendientes."
S3. Accepted authorization question: "¿Confirmás publicar v0.3.0 con esas validaciones pendientes y autorizar trabajar en /Users/kevnnard/Repositories/homebrew-tap para actualizar, commitear y pushear el cask?".

## Tasks

T1 | S1-S3 | inline, quota unavailable; preflight and packaging path correctness | in_progress | commit: pending; Risk: item 5 (release packaging/environment).
T2 | S1-S3 | inline version/notes and signed/notarized ZIP generation, preserve prior ZIP and bundle | pending | commit: pending; no installation.
T3 | S1-S2 | inline fast-forward main, push reviewed local commits, publish exact tag/asset | pending | commit: pending; no force, no existing release clobber.
T4 | S1-S3 | inline authorized sibling tap, version + checksum, cask checks, commit/push | pending | commit: pending; preserve unrelated .DS_Store.
T5 | S1-S3 | verify remote asset/version/hash and repository delivery; record limitations | pending | commit: pending.

## Log

L1. User request verbatim: "dale entonces vamos a generar el zip , todos los commits y push a main y en brew tap actualizar la veersoin no ?? o que ??".
L2. The user chose publish_v030_and_tap after being told the release order and explicitly warned that physical-notch, signed-installed login and independent verification remain pending. Explicit session authorization covers /Users/kevnnard/Repositories/homebrew-tap, including cask edits, commit and push. No quota-consuming worker retry, local installation or force-push is authorized.
L3. Preflight: smart-window is on feat/desktop-controls with committed feature/source/docs through 77e9b30; only SmartWindow.zip is modified. Its SHA-256 adde4548bb97efe4d1120486c56aa201a5aaaa5c57a6cd6c9ea25290765445cc equals the current tap's 0.2.3 release checksum. Preserve it before generating a replacement. Local Info.plist is 0.2.3 build 8. Tap main is 5bfe52a with unrelated untracked .DS_Store only. The existing release-homebrew helper overwrites ZIP, pushes whichever branch is active and can clobber release assets; do not run it blindly.
L4. Separate tooling incident: install-app.sh chooses the first existing .build/release executable after building, but that symlink points to an old March build while current debug output is .build/out/Products/Debug. Preflight will query Swift's authoritative release bin path. Add a bounded isolated fake-swift regression probe before fixing the packager, with no actual /Applications write or signing. Source the inspected project-local release-env.sh for configured Developer ID identity and notary profile; never print credentials.
