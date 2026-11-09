# SmartWindow OpenCode Commands

## Custom Commands

```bash
# Publica un release completo (commit + GitHub + Homebrew)
/release 0.1.3

# Tambien acepta prefijo v
/release v0.1.3
```

## Release Behavior

El comando `/release` debe:

- analizar cambios desde la ultima tag
- actualizar referencias de version si hace falta
- crear commit(s) pendientes del release
- redactar notas de release con formato rico
- cargar `scripts/release-env.sh` si existe
- escribir las notas en `Resources/ReleaseNotes-X.Y.Z.md` y commitearlas
- ejecutar `./scripts/release.sh --dry-run X.Y.Z` y luego `./scripts/release.sh X.Y.Z`
- verificar GitHub release y Homebrew cask
