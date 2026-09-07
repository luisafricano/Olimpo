---
name: noloop
description: Corta el chequeo automático (loop) del sistema Olimpo sin cerrar la sesión de Hermes/Hefesto, que sigue trabajando sola. Usar cuando Zeus pide parar/cortar/pausar el loop o el chequeo automático por separado (no cerrar todo — para eso está `olimpout`).
---

# Olimpo: cortar el loop

Cancelá el loop de chequeo automático de esta conversación (`stop: true` en
la herramienta de programar despertares). No toques la sesión de Hermes ni
la de Hefesto — siguen activas y trabajando.

Avisale a Zeus explícitamente que, sin el loop corriendo, no vas a enterarte
sola de nuevos `[PARA CLAUDE]`/`[ESCALADO]` — para revisar la conversación
va a tener que pedírtelo a mano (o correr `/oloop` de nuevo).
