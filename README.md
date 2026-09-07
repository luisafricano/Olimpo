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
