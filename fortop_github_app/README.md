# Fortop GitHub App

Esta carpeta contiene el registro y la configuración de la GitHub App de Fortop. El código que atiende el acceso, las instalaciones y los tokens se ejecuta dentro del monolito hermano `../fortop_platform/app/services/github` y sus controladores `app/controllers/github`.

## Registrar la aplicación

1. Arranca Rails desde `../fortop_platform` con `bin/dev` o ejecuta `./bin/setup` desde esta carpeta.
2. Abre `http://localhost:3000/setup/github` en tu navegador local.
3. Pulsa **Registrar GitHub App** y confirma su creación en GitHub. El nombre propuesto es único y se puede cambiar.
4. GitHub devuelve el navegador a Rails. El servidor canjea el código, guarda las credenciales automáticamente en `../fortop_platform/.env` con permisos `0600` y las carga en el proceso actual. Las credenciales nunca aparecen en la página.
5. Inicia sesión con GitHub en Fortop e instala la app en los repositorios que elijas desde **Conectar un repositorio**.

La confirmación en GitHub pertenece a la cuenta que será dueña de la app. La sesión de `gh` de la máquina no sustituye la identidad de los usuarios de Fortop.

Los workers de desarrollo cargan las nuevas credenciales de GitHub desde el archivo local antes de usarlas, así que el registro permite ejecutar análisis sin reiniciar `bin/dev`. Esa lectura se limita a las variables de GitHub; las claves de IA mantienen su configuración propia.

El registro automático solo está habilitado en desarrollo y desde una conexión local. Una vez configurada la app, la ruta no permite reemplazar sus credenciales. Para registrar otra instancia, configura un entorno independiente.

## Permisos y acceso

- Metadatos: lectura.
- Contenido, issues y pull requests: escritura.
- Instalación: el usuario elige todos sus repositorios o un subconjunto.
- Webhooks: desactivados, con URL vacía en el manifiesto; no hace falta un túnel público. GitHub rechaza una URL de webhook que apunte a `localhost` incluso cuando está desactivado.

La identidad utiliza autorización de GitHub App con `state`, PKCE y tokens de usuario renovables. Los trabajos comprueban que el usuario sigue teniendo acceso a la instalación y al repositorio. Publican con tokens de instalación efímeros restringidos a ese repositorio, en ramas `fortop/*`, y dejan los PRs para revisión.

## Logo en GitHub

[`avatar.png`](avatar.png) contiene el avatar oficial del brandkit (1024 × 1024,
PNG de 33 kB). En la [configuración de Fortop App](https://github.com/settings/apps/fortop-app),
busca **Display information → Upload a logo**, selecciona ese archivo y pulsa
**Set new avatar**. Si solicita color de fondo, utiliza `#FFFFF3`.
El autor de los PRs es `fortop-app[bot]`; su avatar se configura en GitHub,
independientemente del logo de la web de Rails.
[Instrucciones oficiales](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/creating-a-custom-badge-for-your-github-app).

## Configuración

El registro completa estas variables en el entorno de Rails:

```dotenv
GITHUB_APP_ID=
GITHUB_APP_SLUG=
GITHUB_CLIENT_ID=
GITHUB_CLIENT_SECRET=
GITHUB_APP_PRIVATE_KEY=
GITHUB_WEBHOOK_SECRET=
```

La clave privada se guarda como base64 para que la carga del archivo `.env` conserve exactamente el PEM tras reiniciar. También se acepta un PEM normal al configurar variables directamente.

`APP_URL` define el origen de la plataforma, por ejemplo `http://localhost:3000`. Usa un origen HTTPS real para producción y registra sus URLs en una app de producción independiente. El alta mediante `/setup/github` está deshabilitada en producción.

`./bin/manifest` muestra el manifiesto público con las URLs actuales, sin credenciales. El manifiesto no activa webhooks; si se incorporan después habrá que implementar la validación de firma antes de habilitarlos.

Referencias oficiales: [registro por manifiesto](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest), [tokens de usuario](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-user-access-token-for-a-github-app), [renovación](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/refreshing-user-access-tokens).
