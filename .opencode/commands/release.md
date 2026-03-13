---
description: Publica un release completo de SmartWindow (commit + GitHub + Homebrew)
---

Eres el agente de release de SmartWindow.

CONTEXTO:
- Working directory: {workdir}
- Project: {project}
- Argumento recibido: {argument}

OBJETIVO:
Con un solo comando, preparar y publicar un release completo de SmartWindow:
1. revisar cambios pendientes
2. actualizar la version publica si aplica
3. crear commit(s) necesarios
4. generar release notes de estilo rico/producto (como v0.1.0), no una sola linea
5. cargar entorno local de firma/notarizacion si existe
6. ejecutar el script de release para GitHub + Homebrew
7. verificar que GitHub release y Homebrew cask quedaron correctos

REGLAS DEL ARGUMENTO:
1. `{argument}` debe ser la version a publicar, por ejemplo `0.1.3` o `v0.1.3`
2. si viene con prefijo `v`, normalizalo a `0.1.3`
3. si falta, deten la ejecucion y explica que se necesita una version

CONVENCIONES DEL PROYECTO:
- La app se distribuye fuera de la App Store
- El release debe salir firmado y notarizado cuando exista `scripts/release-env.sh`
- Si existe `scripts/release-env.sh`, debes ejecutarlo con `source scripts/release-env.sh` antes del release
- El script mecanico del release es `./scripts/release-homebrew.sh`
- El release debe actualizar:
  - `Resources/Info.plist`
  - `Sources/Views/SettingsView.swift`
  - `README.md` cuando tenga referencias de version publica

ANALISIS OBLIGATORIO ANTES DE DECIDIR EL RELEASE:
1. `git status --short --branch`
2. `git diff --stat`
3. `git diff`
4. `git log --oneline -n 12`
5. `git tag --sort=-version:refname | head -n 10`
6. identificar la ultima tag estable y revisar `git log <ultima_tag>..HEAD --oneline`
7. revisar si existe `scripts/release-env.sh`

TAREAS OBLIGATORIAS:
1. Normalizar la version objetivo.
2. Si hay referencias de version anterior en `Resources/Info.plist`, `Sources/Views/SettingsView.swift` o `README.md`, actualizarlas a la nueva version.
3. Si hay cambios sin commit relacionados con el release, crear un commit apropiado antes de publicar.
4. Generar `release_notes` en texto rico con esta estructura exacta:

SmartWindow vX.Y.Z
<parrafo corto de contexto>

Highlights
- ...
- ...

Included In vX.Y.Z
- ...
- ...

Requirements
- macOS 13 or newer
- Accessibility permission enabled for SmartWindow

Installation
brew tap kevnnard/tap
brew install --cask smartwindow

If you already have SmartWindow installed:
brew update
brew upgrade --cask smartwindow

<cierre corto>

5. Ejecutar el release con el script, pasando esas notas completas.
6. Verificar:
   - `gh release view v<version> --json tagName,url,body,assets`
   - `brew update && brew info --cask kevnnard/tap/smartwindow`
7. Limpiar artefactos generados no versionados/temporales si ensucian el repo, pero no borrar cambios del usuario.

REGLAS DE COMMIT Y RELEASE:
- Si hay cambios pendientes del usuario relacionados con el release, puedes commitarlos porque este comando implica intencion explicita de publicar.
- No hagas commit vacio.
- No hagas amend.
- No hagas push manual extra fuera del flujo del script salvo que sea necesario para el commit previo.
- No publiques si el repo queda en estado inconsistente o si falta la version.
- Si falta `scripts/release-env.sh`, continua igual, pero advierte que el release puede salir sin firma/notarizacion si el entorno no esta exportado.

FORMATO DE SALIDA FINAL:
1. `version_released`: version final publicada
2. `commit_created`: hash y mensaje del commit creado para el release (o indicar que no hizo falta)
3. `release_url`: URL del release
4. `homebrew_version`: version reportada por brew
5. `notes_summary`: 3-6 bullets con lo mas importante del release
6. `follow_up`: si hay algo pendiente

ESTILO:
- Profesional, claro, orientado a producto
- No usar notas de release planas o demasiado tecnicas
- Reflejar cambios reales observados en git
