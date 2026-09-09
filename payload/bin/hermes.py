#!/usr/bin/env python3
"""Levanta (o reutiliza) un servidor OpenCode, prueba la conexion real con el
modelo configurado, crea una sesion compartida y deja al usuario conectado a
ella (opencode attach) en la misma terminal.

Portable: no hardcodea rutas de ningun sistema operativo. Toda ubicacion de
archivos se resuelve delegando en el propio binario `opencode` (`opencode
debug paths` / `opencode debug config`), que ya sabe donde vive su config en
cada SO.
"""

import argparse
import datetime
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request

# En consolas con codepage distinto de UTF-8 (cp1252/850 en Windows), forzar
# utf-8 evita que el banner con caracteres de caja rompa con UnicodeEncodeError.
for _stream_name in ("stdout", "stderr", "stdin"):
    _stream = getattr(sys, _stream_name, None)
    if _stream is not None and hasattr(_stream, "reconfigure"):
        try:
            _stream.reconfigure(encoding="utf-8")
        except Exception:
            pass

DEFAULT_PORT = 4096
DEFAULT_HOST = "127.0.0.1"

_ES_WINDOWS = os.name == "nt"

# ---------------------------------------------------------------------------
# Banner ASCII (mismo estilo que Xtractor.py, fuente "ansi_shadow")
# ---------------------------------------------------------------------------

_BANNER_FILAS = [
    "██╗  ██╗███████╗██████╗ ███╗   ███╗███████╗███████╗",
    "██║  ██║██╔════╝██╔══██╗████╗ ████║██╔════╝██╔════╝",
    "███████║█████╗  ██████╔╝██╔████╔██║█████╗  ███████╗",
    "██╔══██║██╔══╝  ██╔══██╗██║╚██╔╝██║██╔══╝  ╚════██║",
    "██║  ██║███████╗██║  ██║██║ ╚═╝ ██║███████╗███████║",
    "╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝╚══════╝",
]
_BANNER_ANCHO = max(len(f) for f in _BANNER_FILAS)


def habilitar_ansi_windows():
    """Activa el procesamiento VT100 (colores/reverse video) en consolas
    Windows modernas. En Windows 10+, un os.system('') vacio alcanza para
    que la consola empiece a interpretar secuencias ANSI."""
    if _ES_WINDOWS:
        os.system("")


def limpiar_pantalla():
    """Reposiciona el cursor al origen y borra desde ahi hacia abajo via
    ANSI, para que el banner quede fijo/estatico al abrir la aplicacion."""
    sys.stdout.write("\033[H\033[J")
    sys.stdout.flush()


def imprimir_banner():
    limpiar_pantalla()
    print()
    print("   " + "=" * _BANNER_ANCHO)
    for fila in _BANNER_FILAS:
        print("   " + fila)
    print()
    for _linea_subtitulo in (
        "Copyright © 2026 - Designed & Developed",
        "by Ing. Luis Africano",
        "(Brexum.ar)",
    ):
        print("   " + _linea_subtitulo.center(_BANNER_ANCHO))
    print()
    print("   " + "=" * _BANNER_ANCHO)
    print()


def imprimir_barra_progreso(pct, ancho=40):
    """Dibuja/actualiza una barra de progreso de una sola linea (via \\r).
    Se usa durante la carga de la sesion compartida; el llamador es
    responsable de imprimir un salto de linea cuando termina (100%)."""
    pct = max(0, min(100, pct))
    completado = int(ancho * pct / 100)
    barra = "█" * completado + "░" * (ancho - completado)
    sys.stdout.write(f"\r   [{barra}] {pct:3d}%")
    sys.stdout.flush()


# Prefijo que uso (Claude) al mandar mensajes automatizados a la sesion via
# `opencode run --attach`, para poder distinguirlos de lo que Zeus tipea a mano
# en la TUI cuando se arma el transcript. Ambos llegan como role "user" en la
# API de opencode; sin esta marca no hay forma de diferenciarlos.
CLAUDE_MARKER = "[CLAUDE]"


def check_opencode_disponible():
    """Chequea que el binario 'opencode' este en PATH antes de hacer nada mas.
    Sin esto, un PATH mal configurado se manifestaba como un traceback crudo
    de FileNotFoundError en vez de un mensaje entendible."""
    if shutil.which("opencode") is None:
        fail(
            "No encontre el comando 'opencode' en el PATH. Instalalo o "
            "agregalo al PATH antes de correr Hermes."
        )


def run_opencode(args, timeout=120):
    """Corre un subcomando de opencode y devuelve (returncode, stdout, stderr) como texto utf-8."""
    try:
        proc = subprocess.run(
            ["opencode", *args],
            capture_output=True,
            timeout=timeout,
        )
    except FileNotFoundError:
        fail("No encontre el comando 'opencode' en el PATH.")
    stdout = proc.stdout.decode("utf-8", errors="replace")
    stderr = proc.stderr.decode("utf-8", errors="replace")
    return proc.returncode, stdout, stderr


def get_opencode_version():
    """Version del binario 'opencode' detectado, para dejar rastro en el
    estado guardado: si el parseo de 'create_session' se rompe algun dia por
    un cambio de formato en 'opencode run --format json', esto permite ver
    de entrada si el cambio de version coincide."""
    code, out, err = run_opencode(["--version"], timeout=10)
    if code != 0:
        return "desconocida"
    return out.strip() or err.strip() or "desconocida"


def _copiar_windows(texto):
    """Escribe directo a la API de portapapeles de Windows (CF_UNICODETEXT)
    via ctypes. 'clip.exe' interpreta su stdin con el codepage de la consola
    (cp1252/850), asi que tildes/enies quedan mal codificados (p.ej. 'ó' ->
    '├│'); pasando por la API con texto UTF-16 se evita ese problema."""
    import ctypes

    CF_UNICODETEXT = 13
    GMEM_MOVEABLE = 0x0002

    datos = (texto + "\0").encode("utf-16-le")

    user32 = ctypes.windll.user32
    kernel32 = ctypes.windll.kernel32

    # OpenClipboard puede fallar si otro proceso lo tiene abierto un
    # instante (historial de portapapeles de Windows, un clipboard manager,
    # antivirus); Microsoft recomienda reintentar en vez de rendirse al
    # primer intento, porque el lock suele liberarse enseguida.
    for _ in range(10):
        if user32.OpenClipboard(0):
            break
        time.sleep(0.05)
    else:
        return False
    try:
        user32.EmptyClipboard()
        h_mem = kernel32.GlobalAlloc(GMEM_MOVEABLE, len(datos))
        if not h_mem:
            return False
        p_mem = kernel32.GlobalLock(h_mem)
        ctypes.memmove(p_mem, datos, len(datos))
        kernel32.GlobalUnlock(h_mem)
        user32.SetClipboardData(CF_UNICODETEXT, h_mem)
    finally:
        user32.CloseClipboard()
    return True


def copiar_al_portapapeles(texto):
    """Copia texto al portapapeles del SO para que el usuario solo tenga que
    pegar (Ctrl+V); Ctrl+C en una terminal es SIGINT, no "copiar", asi que no
    hay atajo de teclado fiable para esto salvo hacerlo nosotros. Devuelve
    True si pudo copiar."""
    try:
        if _ES_WINDOWS:
            return _copiar_windows(texto)
        elif sys.platform == "darwin":
            cmd = ["pbcopy"]
        else:
            cmd = ["xclip", "-selection", "clipboard"]
        subprocess.run(cmd, input=texto.encode("utf-8"), check=True)
        return True
    except Exception:
        return False


def leer_tecla():
    """Lee una sola tecla sin esperar Enter (Ctrl+C en consola es SIGINT, no
    'copiar', asi que usamos una tecla simple como atajo). Devuelve '\\r'
    para Enter, o el caracter leido."""
    if _ES_WINDOWS:
        import msvcrt

        ch = msvcrt.getwch()
        return "\r" if ch in ("\r", "\n") else ch
    else:
        import termios
        import tty

        fd = sys.stdin.fileno()
        anterior = termios.tcgetattr(fd)
        try:
            tty.setraw(fd)
            ch = sys.stdin.read(1)
        finally:
            termios.tcsetattr(fd, termios.TCSADRAIN, anterior)
        return "\r" if ch in ("\r", "\n") else ch


def esperar_para_continuar(mensaje_para_claude):
    """Bloquea hasta que el usuario presione Enter. Mientras tanto, la tecla
    C copia el mensaje al portapapeles (atajo real dentro de la consola,
    ya que Ctrl+C ahi mata el proceso en vez de copiar)."""
    if not sys.stdin.isatty():
        # Sin terminal interactiva (invocado desde otro script, por ejemplo)
        # leer_tecla() colgaria o rompería: seguimos derecho a abrir Opencode.
        print("   (sin terminal interactiva, continuo automaticamente)")
        return
    print("   Presioná C para copiar el bloque al portapapeles, o Enter para abrir Opencode.")
    while True:
        tecla = leer_tecla()
        if tecla == "\r":
            print()
            return
        if tecla.lower() == "c":
            if copiar_al_portapapeles(mensaje_para_claude):
                print("   Copiado al portapapeles (Ctrl+V para pegarlo). Presioná Enter para continuar...")
            else:
                print("   No pude copiarlo automáticamente. Presioná Enter para continuar...")


def http_get_json(url, headers=None, timeout=10):
    req = urllib.request.Request(url, headers=headers or {})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.status, json.loads(resp.read().decode("utf-8"))


def server_is_up(base_url):
    try:
        req = urllib.request.Request(f"{base_url}/session")
        with urllib.request.urlopen(req, timeout=3) as resp:
            return resp.status == 200
    except Exception:
        return False


def get_config_dir():
    code, out, err = run_opencode(["debug", "paths"])
    if code != 0:
        fail(f"No pude correr 'opencode debug paths' (exit {code}):\n{err}")
    for line in out.splitlines():
        parts = line.split(None, 1)
        if len(parts) == 2 and parts[0].strip() == "config":
            return parts[1].strip()
    fail(f"'opencode debug paths' no devolvio una linea 'config':\n{out}")


def get_resolved_config():
    code, out, err = run_opencode(["debug", "config"])
    if code != 0:
        fail(f"No pude correr 'opencode debug config' (exit {code}):\n{err}")
    try:
        return json.loads(out)
    except json.JSONDecodeError as e:
        fail(f"La salida de 'opencode debug config' no es JSON valido: {e}\n{out}")


def fail(message):
    print(f"[Hermes] ERROR: {message}", file=sys.stderr)
    sys.exit(1)


def start_server(host, port, log_path):
    log_file = open(log_path, "w", encoding="utf-8")
    try:
        subprocess.Popen(
            ["opencode", "serve", "--port", str(port), "--hostname", host],
            stdout=log_file,
            stderr=subprocess.STDOUT,
        )
    except FileNotFoundError:
        fail("No encontre el comando 'opencode' en el PATH.")


def wait_for_server(base_url, timeout_seconds=20, log_path=None):
    start = time.time()
    while time.time() - start < timeout_seconds:
        if server_is_up(base_url):
            return True
        time.sleep(0.5)
    if log_path:
        try:
            with open(log_path, "r", encoding="utf-8", errors="replace") as f:
                tail = f.read()[-2000:]
        except OSError:
            tail = "(no se pudo leer el log)"
        fail(f"El servidor no respondio en {timeout_seconds}s. Log:\n{tail}")
    fail(f"El servidor no respondio en {timeout_seconds}s.")


def _check_backend(base_url, api_key):
    """Prueba GET {base_url}/models. Devuelve (ok, detalle_legible)."""
    headers = {}
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"
    try:
        status, _ = http_get_json(f"{base_url.rstrip('/')}/models", headers=headers, timeout=10)
    except urllib.error.HTTPError as e:
        return False, f"respondio {e.code}"
    except Exception as e:
        return False, f"no responde ({e})"
    return status == 200, f"respondio status {status}"


def pick_builtin_free_model():
    """Ultimo recurso cuando ningun provider propio (vast.ai, etc.) responde:
    opencode trae sus propios modelos gratuitos bajo el provider 'opencode/'
    (ver 'opencode models'), que no dependen de ningun backend nuestro.
    Devuelve el primero disponible, o None si no hay ninguno."""
    code, out, err = run_opencode(["models"])
    if code != 0:
        return None
    for line in out.splitlines():
        line = line.strip()
        if line.startswith("opencode/"):
            return line
    return None


def resolve_any_working_model():
    """Sin --model explicito: en vez de asumir un provider fijo, lista todos
    los modelos configurados en opencode.json con su estado (activo/caido) y
    deja elegir. Asi Hermes no depende de que un backend puntual (p.ej. una
    instancia de vast.ai) este levantado si hay otro disponible."""
    config = get_resolved_config()
    providers = config.get("provider") or {}
    if not providers:
        fail("No hay ningun provider configurado en opencode (revisa opencode.json).")

    opciones = []
    for provider_id, provider in providers.items():
        options = provider.get("options") or {}
        base_url = options.get("baseURL")
        if not base_url:
            continue
        ok, detalle = _check_backend(base_url, options.get("apiKey"))
        modelos = list((provider.get("models") or {}).keys()) or ["default"]
        for modelo_id in modelos:
            opciones.append({"model": f"{provider_id}/{modelo_id}", "base_url": base_url, "ok": ok, "detalle": detalle})

    if not opciones:
        fail("Ningun provider configurado en opencode tiene 'options.baseURL'.")

    print("   [HERMES] Modelos configurados en opencode:")
    default_idx = None
    for i, op in enumerate(opciones, start=1):
        estado = "activo" if op["ok"] else f"caido ({op['detalle']})"
        print(f"     {i}) {op['model']}  -  {estado}")
        if op["ok"] and default_idx is None:
            default_idx = i

    if default_idx is None:
        print("   [HERMES] Ningun backend propio configurado en opencode.json esta respondiendo:")
        for op in opciones:
            print(f"     - {op['model']} ({op['base_url']}): {op['detalle']}")
        fallback = pick_builtin_free_model()
        if fallback:
            print(f"   [HERMES] Sigo con el modelo gratuito incorporado de opencode: '{fallback}'.")
            return fallback
        print("   [HERMES] No encontre ni siquiera un modelo 'opencode/*' incorporado. Sigo sin --model.")
        return None

    respuesta = input(f"   Elegi un modelo [{default_idx}]: ").strip()
    if not respuesta:
        elegido = opciones[default_idx - 1]
    else:
        try:
            elegido = opciones[int(respuesta) - 1]
        except (ValueError, IndexError):
            fail(f"Opcion invalida: {respuesta}")
        if not elegido["ok"]:
            fail(f"El modelo '{elegido['model']}' no esta respondiendo ({elegido['detalle']}).")

    print(f"   [HERMES] Usando modelo '{elegido['model']}'.")
    return elegido["model"]


def test_model_connectivity(model):
    provider_id = model.split("/", 1)[0]
    config = get_resolved_config()
    provider = (config.get("provider") or {}).get(provider_id)
    if not provider:
        fail(
            f"No encontre el provider '{provider_id}' en la config resuelta de opencode. "
            f"Providers disponibles: {list((config.get('provider') or {}).keys())}"
        )
    options = provider.get("options") or {}
    base_url = options.get("baseURL")
    if not base_url:
        fail(f"El provider '{provider_id}' no tiene 'options.baseURL' configurado.")

    ok, detalle = _check_backend(base_url, options.get("apiKey"))
    if not ok:
        fail(f"El backend del modelo {detalle} en {base_url}/models. No sigo con una sesion sobre un backend caido.")


def create_session(base_url, model, name):
    # --format json: cada linea de stdout es un evento con 'sessionID' propio.
    # Parseamos ese campo en vez de asumir "la sesion con updated mas reciente"
    # en /session, que es ambiguo si hay otras sesiones con actividad concurrente.
    cmd = ["run", "--attach", base_url]
    if model:
        cmd += ["--model", model]
    cmd += ["--title", name, "--format", "json", "Sesion iniciada."]
    code, out, err = run_opencode(cmd)
    if code != 0:
        fail(f"No pude crear la sesion inicial (exit {code}):\n{err}\n{out}")

    for line in out.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            evento = json.loads(line)
        except json.JSONDecodeError:
            continue
        session_id = evento.get("sessionID")
        if session_id:
            return session_id

    fail(f"No pude extraer el sessionID de la salida de 'opencode run':\n{out}")


def delete_session(session_id):
    """Tumba (borra) la sesion recien cerrada via 'opencode session delete'.
    Este subcomando opera directo sobre el storage local (no toma --attach),
    asi que funciona igual con el server arriba."""
    code, out, err = run_opencode(["session", "delete", session_id])
    if code != 0:
        print(
            f"[Hermes] No pude borrar la sesion {session_id} (exit {code}):\n{err}\n{out}",
            file=sys.stderr,
        )
        return False
    print(f"[Hermes] Sesion {session_id} eliminada.")
    return True


def get_project_key():
    """Identificador estable del proyecto (directorio desde el que se corre
    Hermes), para que el estado de cada corrida quede en su propio archivo.
    Sin esto, dos proyectos usando el mismo config_dir de opencode
    terminaban compartiendo un unico '.hefesto_session.json': la sesion
    huerfana de un proyecto se detectaba/borraba desde el otro."""
    project_path = os.path.realpath(os.getcwd())
    digest = hashlib.sha1(project_path.encode("utf-8")).hexdigest()[:12]
    nombre = os.path.basename(project_path.rstrip(os.sep)) or "root"
    nombre = "".join(c if c.isalnum() or c in "-_" else "_" for c in nombre)
    return f"{nombre}-{digest}"


def _state_path(config_dir):
    sessions_dir = os.path.join(config_dir, "hermes_sessions")
    os.makedirs(sessions_dir, exist_ok=True)
    return os.path.join(sessions_dir, f"{get_project_key()}.json")


def save_state(config_dir, state):
    with open(_state_path(config_dir), "w", encoding="utf-8") as f:
        json.dump(state, f, indent=2)


def load_state(config_dir):
    try:
        with open(_state_path(config_dir), "r", encoding="utf-8") as f:
            return json.load(f)
    except OSError:
        return None


def clear_state(config_dir):
    try:
        os.remove(_state_path(config_dir))
    except OSError:
        pass


def session_exists(base_url, session_id):
    try:
        status, _ = http_get_json(f"{base_url}/session/{session_id}", timeout=5)
        return status == 200
    except Exception:
        return False


def reap_sesion_huerfana(base_url, config_dir):
    """Si un run anterior de Hermes murio sin exportar/borrar (p.ej. se cerro
    la ventana de golpe, caso que ningun proceso puede interceptar), el
    .hefesto_session.json apunta a una sesion que quedo viva en el server.
    Antes de crear una sesion nueva, la detectamos, exportamos su transcript
    y la borramos, para no acumular sesiones fantasma."""
    estado_previo = load_state(config_dir)
    if not estado_previo:
        return
    session_id = estado_previo.get("session_id")
    if not session_id or not session_exists(base_url, session_id):
        clear_state(config_dir)
        return

    print(f"[Hermes] Encontre una sesion huerfana de un run anterior ({session_id}), la limpio...")
    stop_active_session(config_dir)


def _estimate_tokens(text):
    """Estimacion aproximada (1 token ~= 4 caracteres) para mensajes de Claude
    o Zeus, de los que no tenemos un conteo real de tokenizer -- se marca
    explicitamente como estimado en el transcript, nunca como valor exacto."""
    return max(1, len(text) // 4)


def _extract_real_tokens(info):
    """Uso de tokens que reporta OpenCode para un mensaje de Hefesto, si esta
    disponible en 'info'. El nombre/forma exacta del campo no esta confirmado
    contra una sesion real todavia -- se prueban las formas mas comunes y se
    devuelve None si ninguna esta, en vez de asumir un numero incorrecto."""
    tokens = info.get("tokens")
    if isinstance(tokens, dict):
        total = tokens.get("total")
        if total is not None:
            return total
        input_t = tokens.get("input") or 0
        output_t = tokens.get("output") or 0
        if input_t or output_t:
            return input_t + output_t
    usage = info.get("usage")
    if isinstance(usage, dict):
        total = usage.get("total_tokens") or usage.get("total")
        if total is not None:
            return total
    return None


def _entry_lines(info, parts):
    """Descompone un mensaje en lineas etiquetadas: (tag, texto, tokens_info).
    tag es None para el texto propio de Hefesto (voz por default del log), o
    'CONSOLE'/'ZEUS'/'CLAUDE' segun corresponda. Los nombres de campo de
    salida de las partes 'tool' no estan confirmados contra una sesion real
    (se prueban los mas comunes, con fallback al resumen de status)."""
    role = info.get("role")
    out = []
    for part in parts:
        ptype = part.get("type")
        if ptype == "text":
            text = (part.get("text") or "").strip()
            if not text:
                continue
            if role == "assistant":
                out.append((None, text, ("real", _extract_real_tokens(info))))
            elif text.startswith(CLAUDE_MARKER):
                out.append(("CLAUDE", text[len(CLAUDE_MARKER):].strip(), ("est", None)))
            else:
                out.append(("ZEUS", text, ("est", None)))
        elif ptype == "tool":
            tool_name = part.get("tool", "?")
            state = part.get("state") or {}
            status = state.get("status", "?")
            salida = (
                state.get("output")
                or state.get("result")
                or (state.get("metadata") or {}).get("output")
            )
            if salida:
                out.append(("CONSOLE", f"$ {tool_name}\n{salida}", ("real", None)))
            else:
                out.append(("CONSOLE", f"(tool: {tool_name}, status: {status})", ("real", None)))
        elif ptype == "file":
            nombre = part.get("filename") or part.get("url") or "?"
            out.append((None, f"_(archivo adjunto: {nombre})_", ("real", None)))
        elif ptype in ("agent", "subtask"):
            nombre = part.get("name") or part.get("agent") or ptype
            out.append((None, f"_({ptype}: {nombre})_", ("real", None)))
        # step-start/step-finish/patch/etc: estructurales, sin contenido
        # propio para el transcript -> se ignoran a proposito.

    resueltos = []
    for tag, text, (kind, real_tokens) in out:
        if kind == "real":
            tokens = real_tokens
            tokens_label = f"{tokens} tokens" if tokens is not None else None
        else:
            tokens = _estimate_tokens(text)
            tokens_label = f"~{tokens} tokens (estimado)"
        resueltos.append((tag, text, tokens_label))
    return resueltos


def _format_entry(created_ms, tag, text, tokens_label):
    ts = (
        datetime.datetime.fromtimestamp(created_ms / 1000).strftime("%H:%M:%S")
        if created_ms
        else "??:??:??"
    )
    header = f"### {ts}" + (f" — [{tag}]" if tag else "")
    if tokens_label:
        header += f" _({tokens_label})_"
    return "\n".join([header, "", text, ""])


def fetch_recent_messages(base_url, session_id, n):
    """Trae el historial completo del lado del servidor pero solo devuelve
    las ultimas n lineas etiquetadas (tag/texto/tokens). Pensado para
    chequeos periodicos (el loop de Claude) sin cargar el historial entero
    en el contexto del modelo cada vez -- el recorte pasa aca, no en el
    llamado HTTP."""
    status, messages = http_get_json(f"{base_url}/session/{session_id}/message", timeout=15)
    if status != 200:
        fail(f"No pude leer los mensajes de la sesion (status {status}).")

    recientes = []
    for entry in messages:
        info = entry.get("info", {})
        parts = entry.get("parts", [])
        created_ms = info.get("time", {}).get("created")
        for tag, text, tokens_label in _entry_lines(info, parts):
            recientes.append({
                "tag": tag,
                "text": text,
                "created_ms": created_ms,
                "tokens": tokens_label,
            })

    return recientes[-n:] if n > 0 else recientes


def export_transcript(base_url, session_id, config_dir):
    """Vuelca el historial completo de la sesion (via la API del servidor) a un
    .md con hora, en <config_dir>/logs/. Independiente de como haya terminado
    el cliente attach (exit, Ctrl+C, o cierre de ventana si el proceso llego a
    correr esto)."""
    status, messages = http_get_json(f"{base_url}/session/{session_id}/message", timeout=15)
    if status != 200:
        print(f"[Hermes] No pude leer los mensajes de la sesion (status {status}), no exporto.", file=sys.stderr)
        return None

    logs_dir = os.path.join(config_dir, "logs")
    os.makedirs(logs_dir, exist_ok=True)

    now = datetime.datetime.now()
    out_path = os.path.join(logs_dir, f"{session_id}_{now.strftime('%Y%m%d-%H%M%S')}.md")

    lines = [f"# Sesion {session_id}", "", f"Exportado: {now.isoformat(timespec='seconds')}", ""]

    for entry in messages:
        info = entry.get("info", {})
        parts = entry.get("parts", [])
        created_ms = info.get("time", {}).get("created")
        for tag, text, tokens_label in _entry_lines(info, parts):
            lines.append(_format_entry(created_ms, tag, text, tokens_label))

    with open(out_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))

    print(f"[Hermes] Transcript exportado a {out_path}")
    return out_path


_SAVE_MARKER_RE_PREFIX = "<!-- olimpo:last_id="


def save_incremental(base_url, session_id, config_dir):
    """Guarda SOLO lo nuevo desde el ultimo 'hermes --save' en un archivo
    persistente por sesion (logs/<session_id>.md), en vez de crear un archivo
    nuevo por llamada como hace export_transcript. Pensado para que Hefesto
    lo corra seguido (fin de fase, error, instruccion recibida) sin duplicar
    contenido ni generar decenas de archivos.

    El cursor de 'hasta donde ya se guardo' se guarda como comentario HTML al
    final del propio archivo (<!-- olimpo:last_id=... -->) en vez de un
    archivo de estado aparte, para que sea auto-contenido: alcanza con leer
    el archivo para saber por donde seguir."""
    status, messages = http_get_json(f"{base_url}/session/{session_id}/message", timeout=15)
    if status != 200:
        return {"active": True, "saved": 0, "error": f"status {status} al leer mensajes"}

    logs_dir = os.path.join(config_dir, "logs")
    os.makedirs(logs_dir, exist_ok=True)
    out_path = os.path.join(logs_dir, f"{session_id}.md")

    last_id = None
    if os.path.exists(out_path):
        with open(out_path, "r", encoding="utf-8") as f:
            contenido = f.read()
        for linea in contenido.splitlines():
            if linea.startswith(_SAVE_MARKER_RE_PREFIX):
                last_id = linea[len(_SAVE_MARKER_RE_PREFIX):].rstrip(" -->").strip()

    nuevos_desde = last_id is None
    bloques_nuevos = []
    ultimo_id_visto = last_id
    for entry in messages:
        info = entry.get("info", {})
        msg_id = info.get("id") or str(info.get("time", {}).get("created"))
        parts = entry.get("parts", [])
        created_ms = info.get("time", {}).get("created")

        if not nuevos_desde:
            if msg_id == last_id:
                nuevos_desde = True
            continue

        for tag, text, tokens_label in _entry_lines(info, parts):
            bloques_nuevos.append(_format_entry(created_ms, tag, text, tokens_label))
        ultimo_id_visto = msg_id

    if not bloques_nuevos:
        return {"active": True, "saved": 0, "path": out_path}

    es_archivo_nuevo = not os.path.exists(out_path)
    with open(out_path, "a", encoding="utf-8") as f:
        if es_archivo_nuevo:
            f.write(f"# Sesion {session_id}\n\n")
        f.write("\n".join(bloques_nuevos))
        f.write(f"\n{_SAVE_MARKER_RE_PREFIX}{ultimo_id_visto} -->\n")

    return {"active": True, "saved": len(bloques_nuevos), "path": out_path}


def stop_active_session(config_dir):
    """Cierre completo standalone (sin necesitar el proceso 'attach' vivo):
    exporta, borra la sesion y limpia el estado. Es el mismo trabajo que ya
    hace el 'finally' de main(), factorizado para poder llamarse desde
    '--stop' o desde el cierre normal, sin duplicar la logica."""
    estado = load_state(config_dir)
    if not estado:
        return None
    export_transcript(estado["url"], estado["session_id"], config_dir)
    delete_session(estado["session_id"])
    clear_state(config_dir)
    return estado


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default=DEFAULT_HOST)
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument(
        "--model",
        default=None,
        help=(
            "Modelo a usar (provider/modelo). Si no se indica, Hermes prueba "
            "cada provider configurado en opencode y usa el primero cuyo "
            "backend responda, en vez de depender de uno fijo."
        ),
    )
    parser.add_argument(
        "--name",
        default=None,
        help=(
            "Nombre/titulo para la sesion compartida. Si no se indica se genera "
            "uno con la fecha/hora (p.ej. hermes-20260904-153000). Pasarselo a "
            "Claude junto con la URL de la API para que ubique la sesion."
        ),
    )
    parser.add_argument(
        "--export-only",
        metavar="SESSION_ID",
        help=(
            "No levanta nada ni conecta attach: solo exporta el transcript de esa "
            "sesion (util si la terminal se cerro de golpe y el server sigue vivo)."
        ),
    )
    parser.add_argument(
        "--current",
        action="store_true",
        help=(
            "No levanta nada ni conecta attach: imprime como JSON el estado de la "
            "sesion activa del proyecto actual (o {\"active\": false} si no hay "
            "ninguna), para que otro proceso (p.ej. un loop de Claude) sepa a que "
            "url/session_id consultar sin reimplementar la logica de estado."
        ),
    )
    parser.add_argument(
        "--recent",
        type=int,
        metavar="N",
        default=None,
        help=(
            "No levanta nada ni conecta attach: imprime como JSON los ultimos N "
            "mensajes (label, texto, timestamp) de la sesion activa del proyecto "
            "actual, sin volcar el historial completo. Pensado para chequeos "
            "periodicos baratos (loop de Claude) en vez de pedir todo cada vez."
        ),
    )
    parser.add_argument(
        "--save",
        action="store_true",
        help=(
            "No levanta nada ni conecta attach: guarda SOLO lo nuevo desde el "
            "ultimo '--save' en logs/<session_id>.md (archivo persistente por "
            "sesion, no uno nuevo por llamada). Pensado para que Hefesto lo "
            "corra seguido (fin de fase, error, instruccion recibida)."
        ),
    )
    parser.add_argument(
        "--stop",
        action="store_true",
        help=(
            "No levanta nada ni conecta attach: si hay sesion activa del "
            "proyecto actual, la cierra por completo (exporta, borra la "
            "sesion, limpia el estado) sin necesitar el proceso 'attach' vivo."
        ),
    )
    args = parser.parse_args()

    check_opencode_disponible()

    if args.current:
        config_dir = get_config_dir()
        estado = load_state(config_dir)
        if not estado:
            print(json.dumps({"active": False}))
        else:
            print(json.dumps({"active": True, **estado}))
        return

    if args.recent is not None:
        config_dir = get_config_dir()
        estado = load_state(config_dir)
        if not estado:
            print(json.dumps({"active": False}))
        else:
            recientes = fetch_recent_messages(estado["url"], estado["session_id"], args.recent)
            print(json.dumps({"active": True, "messages": recientes}))
        return

    if args.save:
        config_dir = get_config_dir()
        estado = load_state(config_dir)
        if not estado:
            print(json.dumps({"active": False}))
        else:
            resultado = save_incremental(estado["url"], estado["session_id"], config_dir)
            print(json.dumps(resultado))
        return

    if args.stop:
        config_dir = get_config_dir()
        estado = stop_active_session(config_dir)
        if not estado:
            print(json.dumps({"active": False}))
        else:
            print(json.dumps({
                "active": True,
                "stopped": True,
                "session_id": estado["session_id"],
                "session_name": estado["session_name"],
            }))
        return

    habilitar_ansi_windows()
    imprimir_banner()

    base_url = f"http://{args.host}:{args.port}"
    config_dir = get_config_dir()

    if args.export_only:
        if not server_is_up(base_url):
            fail(f"No hay servidor corriendo en {base_url}, no hay nada que exportar.")
        export_transcript(base_url, args.export_only, config_dir)
        return

    print("   [HERMES] Creando y cargando sesión compartida entre Opencode y Claude...")
    print()
    imprimir_barra_progreso(1)

    if not server_is_up(base_url):
        import tempfile

        log_path = os.path.join(tempfile.gettempdir(), f"opencode-serve-{args.port}.log")
        start_server(args.host, args.port, log_path)
        wait_for_server(base_url, log_path=log_path)
    imprimir_barra_progreso(25)

    reap_sesion_huerfana(base_url, config_dir)

    if args.model:
        test_model_connectivity(args.model)
    else:
        args.model = resolve_any_working_model()
    imprimir_barra_progreso(55)
    print()

    default_name = f"hermes-{datetime.datetime.now().strftime('%Y%m%d-%H%M%S')}"
    if args.name:
        session_name = args.name
    else:
        respuesta = input(
            f"   Nombre para la sesión compartida [{default_name}]: "
        ).strip()
        session_name = respuesta or default_name

    session_id = create_session(base_url, args.model, session_name)
    imprimir_barra_progreso(80)

    save_state(
        config_dir,
        {
            "url": base_url,
            "session_id": session_id,
            "session_name": session_name,
            "model": args.model or "(default de opencode)",
            "created": time.time(),
            "opencode_version": get_opencode_version(),
            "project_dir": os.path.realpath(os.getcwd()),
        },
    )
    imprimir_barra_progreso(100)
    print("\n")
    print("   [HERMES] Sesión creada y activa.")
    print()

    project_dir = os.path.realpath(os.getcwd())
    hermes_path = os.path.abspath(__file__)

    mensaje_para_claude = (
        "Conectate por API a mi sesión compartida de Opencode/Hermes:\n"
        f"- URL del servidor: {base_url}\n"
        f"- Nombre de sesión: {session_name}\n"
        f"- Session ID: {session_id}\n"
        f"- Directorio del proyecto: {project_dir}\n"
        f"- Script Hermes: {hermes_path}\n"
        f"Consultá GET {base_url}/session/{session_id}/message cada vez que "
        "te lo pida para ver mis entradas y las salidas de la IA en tiempo real.\n"
        "Arrancá ahora el chequeo automático de esta sesión (con tu propio "
        f"protocolo de este proyecto): revisá 'python \"{hermes_path}\" "
        "--recent 5' cada pocos minutos y atendé los [PARA CLAUDE]/[ESCALADO] "
        "pendientes, así no hace falta que te avise cada consulta a mano."
    )

    print("   " + "-" * _BANNER_ANCHO)
    for linea in mensaje_para_claude.splitlines():
        print(f"   {linea}")
    print("   " + "-" * _BANNER_ANCHO)
    print()

    try:
        # Envuelve tambien la espera de tecla: un Ctrl+C aca (antes de entrar
        # a Opencode) antes se perdia sin exportar ni borrar la sesion recien
        # creada, porque el try/finally solo cubria el subprocess.run(attach).
        esperar_para_continuar(mensaje_para_claude)
        result = subprocess.run(["opencode", "attach", base_url, "--session", session_id])
        returncode = result.returncode
    except KeyboardInterrupt:
        # Ctrl+C: el padre sigue vivo, alcanza a exportar antes de salir.
        returncode = 130
    finally:
        # Cubre "exit" dentro de la TUI y Ctrl+C. Un cierre de ventana que mata
        # todo el arbol de procesos de un golpe no puede interceptarse desde
        # ningun proceso (limitacion del SO) — para ese caso queda el modo
        # standalone `--export-only <session_id>` / `--stop` mientras el
        # server siga vivo, o el barrido automatico de sesion huerfana al
        # proximo arranque.
        stop_active_session(config_dir)

    sys.exit(returncode)


if __name__ == "__main__":
    main()
