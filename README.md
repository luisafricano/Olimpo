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
compartida sin depender de un modelo o backend fijo, un protocolo de
escalamiento con timeouts para que Hefesto nunca quede bloqueado esperando
indefinidamente, y comandos de Claude Code (`/olimpo`, `/olimpout`, `/oloop`,
`/noloop`) para arrancar, cortar y controlar todo el sistema desde cualquier
proyecto.

## Los tres roles

| Rol | Quién/qué es | Responsabilidad |
|---|---|---|
| **Zeus** | El usuario | Autoridad final. Decide todo lo que el plan no cubre explícitamente — ninguna decisión de alcance o arquitectura se toma sin él. |
| **Claude** | Claude Code, vía skills `olimpo`/`olimpout`/`oloop`/`noloop` | Arquitecto. Redacta el plan de implementación y responde consultas técnicas dentro de ese alcance. Nunca ejecuta el plan él mismo. |
| **Hefesto** | OpenCode, vía `hermes` | Ejecutor. Implementa el plan tal cual está escrito; ante cualquier ambigüedad o necesidad de salirse del alcance, escala en vez de decidir solo. |

## Funcionalidades

- 🌉 **Puente `hermes` ↔ OpenCode**: crea la sesión compartida, prueba
  conectividad real contra el backend antes de arrancar, y limpia sesiones
  huérfanas dejadas por corridas anteriores (por ejemplo, si se cerró la
  ventana de golpe).
- 🎯 **Selección de modelo sin backend fijo**: sin pasarle `--model`, `hermes`
  no depende de un provider hardcodeado — lee todos los providers
  configurados en `opencode`, chequea en vivo cuál está respondiendo, y te
  deja elegir (por default, el primero activo). Si ninguno de tus providers
  propios responde, cae automáticamente a un modelo gratuito incorporado de
  OpenCode (`opencode/...`) en vez de cortar la ejecución.
- 🔺 **Cadena de escalamiento con tags** `[ESCALADO]` → `[PARA CLAUDE]` →
  `[INST]`/`[CLAUDE]`: Hefesto consulta a Zeus primero, y solo pasa a Claude
  si Zeus lo redirige (o pasan 10 minutos sin respuesta y la consulta no es
  un cambio de plan).
- 🏷️ **Dos tags distintos para las respuestas de Claude**: `[INST]` marca una
  instrucción real que Hefesto debe aplicar; `[CLAUDE]` marca chat o
  contexto sin acción esperada (confirmaciones, mensajes de prueba de
  conexión). Evita que Hefesto interprete un mensaje de prueba como una
  orden a ejecutar.
- 🔁 **Chequeo automático cada 10 minutos** vía `/olimpo` (con backoff hasta
  60min si no hay sesión activa) — Claude no necesita que Zeus le avise cada
  consulta.
- 🛑 **Apagado con un comando**: `/olimpout` cierra sesión y loop juntos;
  `/oloop`/`/noloop` controlan solo el chequeo automático sin tocar la
  sesión.
- 📝 **Guardado incremental de la sesión**: Hefesto va dejando rastro
  (mensajes, salida de consola, tokens consumidos —reales cuando OpenCode
  los reporta, estimados si no— ) en un único archivo por sesión
  (`logs/<session_id>.md`), sin duplicar contenido en cada guardado.
- 📤 **Exportación y cierre resilientes**: `--export-only` vuelca el
  transcript completo de una sesión puntual aunque la terminal original ya
  se haya cerrado (mientras el servidor siga vivo); `--stop` cierra una
  sesión activa por completo (exporta, borra, limpia estado) sin necesitar
  el proceso `attach` vivo.
- 🔒 **Lock de escritura post-instalación** sobre los archivos del sistema,
  para que no se pisen por accidente (ni siquiera por el propio Hefesto).
- 🌐 **Portable**: instalador de una línea para Windows/macOS/Linux, sin
  rutas hardcodeadas — todo se resuelve contra la config real de OpenCode y
  Claude Code en cada máquina.

## Stack

| Capa | Tecnologías |
|---|---|
| Puente de sesión | Python (`hermes.py`) |
| Ejecutor | OpenCode (Hefesto) |
| Arquitecto | Claude Code (skills `olimpo`/`olimpout`/`oloop`/`noloop`) |
| Protocolo/reglas | Markdown (`opencode-rules/hefesto.md`, `SKILL.md`) |

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

> Requiere `opencode` y `python3` ya instalados y en el PATH, y al menos un
> provider configurado en `opencode` (o conformarte con el modelo gratuito
> incorporado de OpenCode como fallback). El instalador no instala nada de
> eso por vos — solo conecta los archivos de Olimpo con lo que ya tenés.

## Cómo se usa

1. Parado en la carpeta del proyecto que querés que ejecute Hefesto, corré:

   ```bash
   hermes
   ```

2. `hermes` prueba primero si hay un servidor OpenCode arriba (si no, lo
   levanta), limpia cualquier sesión huérfana de una corrida anterior, y
   resuelve el modelo:
   - Si le pasaste `--model provider/modelo`, prueba conectividad real
     contra ese backend puntual y corta si no responde.
   - Si no le pasaste nada, te muestra todos los providers configurados en
     `opencode` con su estado (activo/caído) y te deja elegir — por default
     el primero activo. Si ninguno responde, cae solo al modelo gratuito
     incorporado de OpenCode.
3. Te pide un nombre para la sesión (o generá uno automático con fecha/hora)
   y te muestra un bloque de texto con la URL de la sesión, el session ID y
   las instrucciones para pegarle a Claude — copialo (con la tecla `C`, que
   lo manda al portapapeles) y pegalo en tu conversación de Claude Code.
4. Claude arranca `/olimpo`: se conecta a la sesión y prende el chequeo
   automático cada 10 minutos. A partir de ahí, Hefesto puede trabajar
   desatendido — si necesita algo, primero consulta a Zeus, y solo pasa a
   Claude si Zeus lo indica (o si pasan 10 minutos sin respuesta y no es una
   decisión de alcance).
5. Cuando termines: `/olimpout` cierra la sesión y corta el loop juntos.
   `/oloop`/`/noloop` controlan solo el chequeo automático si querés
   pausarlo sin cerrar la sesión.

### El protocolo de escalamiento, en corto

```
Hefesto encuentra algo fuera del plan
        │
        ▼
   [ESCALADO]  ──(Zeus no responde en 10min, y no es cambio de plan)──▶  [PARA CLAUDE]
        │                                                                      │
   Zeus decide                                                          Claude responde
        │                                                                      │
        ▼                                                                      ▼
  [PARA CLAUDE]  (si Zeus deriva a Claude)                          [INST]  → Hefesto lo aplica
                                                                     [CLAUDE] → solo chat/contexto,
                                                                                Hefesto NO ejecuta nada
```

Un cambio de plan o de arquitectura **nunca** tiene timeout — ahí Hefesto
espera a Zeus sin límite de tiempo, sea cual sea la demora.

## Comandos de `hermes` (CLI)

Además del uso interactivo normal (sin flags), `hermes` expone subcomandos
"standalone" que no levantan nada ni abren `attach` — pensados para que
Hefesto y el loop de Claude consulten/actualicen el estado de la sesión sin
interrumpir el flujo:

| Comando | Qué hace |
|---|---|
| `hermes` | Flujo completo: levanta/reutiliza el servidor, resuelve modelo, crea la sesión y conecta `attach`. |
| `hermes --model provider/modelo` | Fuerza un modelo puntual en vez de la selección automática; falla si ese backend no responde. |
| `hermes --name "nombre"` | Fija el nombre/título de la sesión en vez de pedirlo por input o generarlo con fecha/hora. |
| `hermes --host / --port` | Cambia dónde escucha el servidor OpenCode local (por default `127.0.0.1:4096`). |
| `hermes --current` | Imprime como JSON el estado de la sesión activa del proyecto actual (o `{"active": false}`). |
| `hermes --recent N` | Imprime como JSON los últimos N mensajes de la sesión activa — el chequeo barato que usa el loop de Claude. |
| `hermes --save` | Guarda en `logs/<session_id>.md` solo lo nuevo desde el último `--save` (no duplica contenido). Lo corre Hefesto en varios puntos del flujo. |
| `hermes --stop` | Cierra por completo la sesión activa (exporta, borra, limpia estado) sin necesitar el proceso `attach` vivo. |
| `hermes --export-only SESSION_ID` | Vuelca el transcript completo de esa sesión puntual, útil si la terminal se cerró de golpe pero el servidor sigue vivo. |

## Comandos de Claude Code

| Comando | Qué hace |
|---|---|
| `/olimpo` | Conecta Claude a la sesión de Hermes/Hefesto ya activa (arrancada antes con `hermes` en una terminal) y prende el chequeo automático cada 10 minutos. Define el protocolo de lectura/escritura sobre esa sesión. |
| `/olimpout` | Apaga todo: cierra la sesión activa (`hermes --stop`) y cancela el loop de chequeo automático. |
| `/oloop` | Prende solo el chequeo automático, sin tocar la sesión de Hermes/Hefesto. |
| `/noloop` | Corta solo el chequeo automático — la sesión de Hefesto sigue trabajando sola, pero Claude deja de enterarse de nuevos `[PARA CLAUDE]`/`[ESCALADO]` hasta que se lo pidan a mano o se corra `/oloop` de nuevo. |

## Actualización

Volvé a correr el mismo comando de instalación — reconcilia todo con la
última versión del repo sin pisar tu configuración de proveedores/modelos
de OpenCode.

## Documentación

El protocolo completo de escalamiento (cuándo Hefesto consulta a Zeus, cuándo
pasa a Claude, y qué puede resolver cada uno sin pedir permiso) vive en
`payload/opencode-rules/hefesto.md`, `payload/opencode-skills/hefesto/SKILL.md`
y `payload/claude-skills/olimpo/SKILL.md` — son la fuente de verdad una vez
instalados, no hace falta duplicarlos acá.

---
Copyright © 2026 - Designed & Developed by Ing. Luis Africano
