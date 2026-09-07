---
name: oloop
description: Prende el chequeo automático (loop) del sistema Olimpo para el proyecto actual, sin tocar la sesión de Hermes/Hefesto. Usar cuando Zeus pide arrancar/retomar/activar el loop o el chequeo automático por separado (no todo el bootstrap de `/olimpo`).
---

# Olimpo: activar el loop

Arrancá el loop de chequeo automático con cadencia base de 10 minutos
(backoff hasta 60min si no hay sesión activa), siguiendo el protocolo del
skill `olimpo` (sección "Chequeo automático"): cada tick corre
`hermes --recent 5` sin cargar el skill `olimpo`, y solo lo invoca si
encuentra algo pendiente (`[PARA CLAUDE]` sin responder o `[ESCALADO]` de
más de 10 min).

Confirmale a Zeus que el loop quedó activo y con qué cadencia, sin volver a
arrancar la sesión de Hermes ni pedir el bootstrap completo de `/olimpo`.
