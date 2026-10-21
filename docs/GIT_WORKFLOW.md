# Flujo de trabajo Git

Este monorepo versiona la plataforma, la configuración de la GitHub App, la
identidad visual y los entregables. Su historial comienza el 21 de octubre de
2026: antes no existía ningún commit. La primera importación organiza el estado
acumulado en cambios funcionales; las fechas y los commits no pretenden
reconstruir una cronología de desarrollo anterior. Las comprobaciones de la
primera versión se realizan sobre el conjunto integrado.

## Ramas

| Rama | Uso | Origen y destino |
| --- | --- | --- |
| `main` | Versiones verificadas y etiquetadas. Una versión local no implica despliegue. | Recibe `release/*` y `hotfix/*`. |
| `develop` | Integración y punto de partida del siguiente trabajo. | Recibe `feature/*` y las correcciones de releases y hotfixes. |
| `feature/<tema>` | Una funcionalidad o un cambio coherente. | Nace de `develop` y vuelve a `develop`. |
| `release/<versión>` | Preparación, documentación y correcciones de una versión. | Nace de `develop`, se integra en `main` y vuelve a `develop`. |
| `hotfix/<tema>` | Corrección urgente de una versión estable. | Nace de `main`, se integra en `main` y vuelve a `develop`. |

Las integraciones usan `git merge --no-ff` para conservar el contexto de cada
rama. No se reescribe una rama compartida. Las ramas de la importación inicial
se conservan como referencias para facilitar su revisión; el grafo y los
commits de integración también preservan esa trazabilidad.

El flujo usa comandos nativos de Git; no requiere instalar la extensión
`git-flow`. Los nombres de ramas y prefijos también están configurados en la
configuración local `gitflow.*`.

## Commits

Usa `tipo(ámbito): cambio concreto`, con `feat`, `fix`, `test`, `refactor`,
`docs`, `design`, `chore` o `ci`. El cuerpo explica el propósito o los límites
cuando sea necesario. Cada commit reúne archivos relacionados; las pruebas
deben acompañar al comportamiento que verifican en el trabajo nuevo.

Antes de confirmar, revisa `git diff --cached` y `git diff --cached --check`.
`.env`, claves, dependencias locales, compilados, logs y archivos temporales
permanecen excluidos. `.env.example` contiene únicamente nombres y valores
de ejemplo. El ZIP de los entregables se conserva localmente como copia de los
archivos versionados y no se añade al historial.

## Nueva funcionalidad

```sh
git switch develop
git switch -c feature/tema
# Implementar, verificar y añadir explícitamente los archivos relacionados.
git add ruta/al/archivo
git commit -m "feat(ámbito): cambio concreto"
git switch develop
git merge --no-ff feature/tema
```

Al disponer de un remoto compartido, publica la rama y usa un pull request
dirigido a `develop`, conservando el commit de merge. Comprueba el CI antes
de integrarlo. No subas credenciales para hacer funcionar el CI: las pruebas
usan transportes simulados y no requieren claves de Google ni de GitHub.

## Preparar una versión

```sh
git switch develop
git switch -c release/0.2.0
# Actualizar CHANGELOG.md, verificar y confirmar la preparación de versión.
git switch main
git merge --no-ff release/0.2.0
git tag -a v0.2.0 -m "Fortop 0.2.0"
git switch develop
git merge --no-ff main
```

La última integración devuelve a `develop` las correcciones y la preparación
de la versión publicada en `main`. Una corrección urgente sigue el mismo
cierre, partiendo de `hotfix/*` creada desde `main`. Las etiquetas `vX.Y.Z` son
anotadas y señalan el commit de la versión en `main`.

## Comprobaciones

Desde `fortop_platform/`:

```sh
bin/rails test
bin/rails test:system
bin/rails zeitwerk:check
bin/rubocop
bin/brakeman --quiet --no-pager
bin/bundler-audit
bin/importmap audit
```

El workflow se encuentra en `.github/workflows/ci.yml`, en la raíz. Se ejecuta
en los pull requests y en los pushes de las ramas de integración y versión
configuradas. No despliega la aplicación.

Para revisar la historia desde la raíz:

```sh
git log --graph --decorate --oneline --all
git log --first-parent develop --oneline
git show v0.1.0
```
