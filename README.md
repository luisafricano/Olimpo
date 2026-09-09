```
================================================
 ██████╗ ██╗     ██╗███╗   ███╗██████╗  ██████╗ 
██╔═══██╗██║     ██║████╗ ████║██╔══██╗██╔═══██╗
██║   ██║██║     ██║██╔████╔██║██████╔╝██║   ██║
██║   ██║██║     ██║██║╚██╔╝██║██╔═══╝ ██║   ██║
╚██████╔╝███████╗██║██║ ╚═╝ ██║██║     ╚██████╔╝
 ╚═════╝ ╚══════╝╚═╝╚═╝     ╚═╝╚═╝      ╚═════╝ 

    Copyright © 2026 - Designed & Developed
             by Ing. Luis Africano
                  (Brexum.ar)

================================================
```

# Olimpo

**Olimpo** es un sistema de trabajo de tres roles — Zeus, Claude y Hefesto —
conectados por una sesión compartida de OpenCode, pensado para ejecutar
planes de programación de forma desatendida sin perder una cadena clara de
autorización: Hefesto ejecuta, Claude asiste técnicamente, y ninguna decisión
de alcance o arquitectura se toma sin que Zeus (el usuario) la apruebe.

Incluye el puente `hermes` (Python) que crea y administra la sesión
compartida, un protocolo de escalamiento con timeouts para que Hefesto nunca
quede bloqueado esperando indefinidamente, y comandos de Claude Code
(`/olimpo`, `/olimpout`, `/oloop`, `/noloop`) para arrancar, cortar y
controlar todo el sistema desde cualquier proyecto.

## Funcionalidades

- 🌉 Puente `hermes` ↔ OpenCode: crea la sesión compartida, prueba
  conectividad real con el modelo, y limpia sesiones huérfanas de corridas
  anteriores.
- 🔺 Cadena de escalamiento con tags `[ESCALADO]` → `[PARA CLAUDE]` →
  `[CLAUDE]`: Hefesto consulta a Zeus primero, y solo pasa a Claude si Zeus
  lo redirige (o pasan 10 minutos sin respuesta y la consulta no es un
  cambio de plan).
- 🔁 Chequeo automático cada 10 minutos vía `/olimpo` (con backoff hasta
  60min si no hay sesión activa) — Claude no necesita que Zeus le avise cada
  consulta.
- 🛑 Apagado con un comando: `/olimpout` cierra sesión y loop juntos;
  `/oloop`/`/noloop` controlan solo el chequeo automático.
- 📝 Guardado incremental de la sesión: Hefesto va dejando rastro (mensajes,
  salida de consola, tokens consumidos) en un único archivo por sesión, sin
  duplicar contenido en cada guardado.
- 🔒 Lock de escritura post-instalación sobre los archivos del sistema, para
  que no se pisen por accidente.
- 🌐 Portable: instalador de una línea para Windows/macOS/Linux, sin rutas
  hardcodeadas — todo se resuelve contra la config real de OpenCode y Claude
  Code en cada máquina.

## Stack

| Capa | Tecnologías |
|---|---|
| Puente de sesión | Python (`hermes.py`) |
| Ejecutor | OpenCode (Hefesto) |
| Arquitecto | Claude Code (skills `olimpo`/`olimpout`/`oloop`/`noloop`) |
| Protocolo/reglas | Markdown (`rules`/`SKILL.md`) |

## Estructura del proyecto

```
Olimpo/
├── README.md
├── VERSION
├── install.sh                       # instalador macOS/Linux
├── install.ps1                      # instalador Windows
└── payload/
    ├── bin/
    │   └── hermes.py                 # -> ~/.local/bin (Unix) o ~/.olimpo/bin (Windows)
    ├── opencode-rules/
    │   └── hefesto.md                 # -> ~/.config/opencode/rules/hefesto.md
    ├── opencode-skills/
    │   └── hefesto/SKILL.md           # -> ~/.config/opencode/skills/hefesto/SKILL.md
    └── claude-skills/
        ├── olimpo/SKILL.md            # -> ~/.claude/skills/olimpo/SKILL.md
        ├── olimpout/SKILL.md          # -> ~/.claude/skills/olimpout/SKILL.md
        ├── oloop/SKILL.md             # -> ~/.claude/skills/oloop/SKILL.md
        └── noloop/SKILL.md            # -> ~/.claude/skills/noloop/SKILL.md
```

## Instalación

```bash
# macOS / Linux
curl -fsSL https://raw.githubusercontent.com/luisafricano/Olimpo/main/install.sh | bash
```

```powershell
# Windows (PowerShell)
irm https://raw.githubusercontent.com/luisafricano/Olimpo/main/install.ps1 | iex
```

> Requiere `opencode` y `python3` ya instalados y en el PATH. El instalador
> no los instala por vos — solo conecta los archivos de Olimpo con lo que ya
> tenés.

## Cómo se usa

1. Parado en la carpeta del proyecto que querés que ejecute Hefesto, corré:

   ```bash
   hermes
   ```

2. `hermes` te va a mostrar un mensaje con la URL de la sesión y las
   instrucciones para pegarle a Claude — copialo (con la tecla `C`) y pegalo
   en tu conversación de Claude Code.
3. Claude arranca `/olimpo`: se conecta a la sesión y prende el chequeo
   automático cada 10 minutos. A partir de ahí, Hefesto puede trabajar
   desatendido — si necesita algo, primero te consulta a vos, y solo pasa a
   Claude si se lo indicás (o si pasan 10 minutos sin respuesta y no es una
   decisión de alcance).
4. Cuando termines: `/olimpout` cierra la sesión y corta el loop juntos.
   `/oloop`/`/noloop` controlan solo el chequeo automático si querés
   pausarlo sin cerrar la sesión.

## Solución de problemas

### `hermes` no arranca por variables de entorno (Windows)

A veces, justo después de instalar Olimpo (o cualquier otra herramienta que
modifique el `PATH`), la consola que ya tenías abierta no se entera del
cambio: sigue usando la "foto" del `PATH` que cargó cuando la abriste, antes
de que `install.ps1` agregara las rutas nuevas. Si al correr `hermes` te
tira un error relacionado con variables de entorno o con que no encuentra
algo que debería estar instalado, probablemente sea justo eso.

La solución más simple es cerrar la consola y abrir una nueva — Windows
vuelve a leer el `PATH` actualizado al abrir. Pero si no querés perder la
consola actual (por ejemplo porque tenés otras cosas corriendo ahí), podés
forzar la recarga a mano:

1. Abrí una consola **como administrador** (click derecho sobre PowerShell
   → "Ejecutar como administrador").
2. Pegá y ejecutá esta línea:

   ```powershell
   $env:Path = [System.Environment]::GetEnvironmentVariable("Path","User") + ";" + [System.Environment]::GetEnvironmentVariable("Path","Machine")
   ```

3. Volvé a probar `hermes` en esa misma ventana.

¿Qué hace exactamente ese comando? Windows guarda el `PATH` en dos lugares
separados: uno a nivel de **usuario** y otro a nivel de **máquina**
(sistema). El comando lee los dos valores actuales directamente del
registro de Windows y los junta en el `$env:Path` de la sesión de consola
actual, sin necesidad de reiniciarla. Es decir, le "refresca la memoria" a
esa consola puntual sobre dónde están instaladas las cosas, sin tener que
cerrarla y abrirla de nuevo.

## Actualización

Volvé a correr el mismo comando de instalación — reconcilia todo con la
última versión del repo sin pisar tu configuración de proveedores/modelos
de OpenCode.

## Documentación

El protocolo completo de escalamiento (cuándo Hefesto consulta a Zeus, cuándo
pasa a Claude, y qué puede resolver cada uno sin pedir permiso) vive en
`payload/opencode-skills/hefesto/SKILL.md` y `payload/claude-skills/olimpo/SKILL.md`
— son la fuente de verdad una vez instalados, no hace falta duplicarlos acá.

---
Copyright © 2026 - Designed & Developed by Ing. Luis Africano
