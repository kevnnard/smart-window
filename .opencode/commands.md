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
- ejecutar `./scripts/release-homebrew.sh`
- verificar GitHub release y Homebrew cask
