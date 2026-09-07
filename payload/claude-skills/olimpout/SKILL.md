---
name: olimpout
description: Apaga por completo el sistema Olimpo para el proyecto actual — cierra la sesión activa de Hermes/Hefesto (exporta transcript, borra sesión, limpia estado) y cancela el loop de chequeo automático de esta conversación. Usar cuando Zeus pide terminar/cerrar/apagar Hefesto, Hermes, Olimpo, o el loop junto con la sesión. Para cortar SOLO el loop sin tocar la sesión, usar `noloop` en cambio.
---

# Olimpo: apagado completo

1. Corré `hermes --stop` en el directorio del proyecto actual. Si había una
   sesión activa, exporta el transcript, borra la sesión y limpia el estado;
   si no había nada, devuelve `{"active": false}` sin hacer nada.
2. Cancelá el loop de chequeo automático de esta conversación (parámetro
   `stop: true` en la herramienta de programar despertares).
3. Confirmale a Zeus qué se cerró: si había sesión (nombre/id) y que el loop
   quedó cancelado, o que no había nada corriendo.

No repreguntes ni pidas confirmación extra — `/olimpout` ya es la
confirmación de Zeus de que quiere cerrar todo.
