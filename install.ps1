# Instalador de Olimpo para Windows.
# Uso: irm https://raw.githubusercontent.com/luisafricano/Olimpo/main/install.ps1 | iex
#
# Copia los archivos de sesion compartida Zeus/Claude/Hefesto a los lugares
# donde OpenCode y Claude Code los leen, y deja `hermes` disponible en el
# PATH del usuario. Correr de nuevo este mismo script actualiza todo
# (reconcilia con lo ultimo del repo).

$ErrorActionPreference = "Stop"

$RepoRaw = "https://raw.githubusercontent.com/luisafricano/Olimpo/main"
$RepoRawFallback = "https://brexum.ar/repos/Olimpo"
$OpencodeConfig = Join-Path $env:USERPROFILE ".config\opencode"
$ClaudeSkills = Join-Path $env:USERPROFILE ".claude\skills"
$OlimpoBin = Join-Path $env:USERPROFILE ".olimpo\bin"

$Payload = @{
    "payload/bin/hermes.py"                      = Join-Path $OlimpoBin "hermes.py"
    "payload/opencode-rules/hefesto.md"          = Join-Path $OpencodeConfig "rules\hefesto.md"
    "payload/opencode-skills/hefesto/SKILL.md"   = Join-Path $OpencodeConfig "skills\hefesto\SKILL.md"
    "payload/claude-skills/olimpo/SKILL.md"      = Join-Path $ClaudeSkills "olimpo\SKILL.md"
    "payload/claude-skills/olimpout/SKILL.md"    = Join-Path $ClaudeSkills "olimpout\SKILL.md"
    "payload/claude-skills/oloop/SKILL.md"       = Join-Path $ClaudeSkills "oloop\SKILL.md"
    "payload/claude-skills/noloop/SKILL.md"      = Join-Path $ClaudeSkills "noloop\SKILL.md"
}

function Obtener-TextoDeRespuesta($resp) {
    # .Content puede llegar como byte[] en vez de string cuando el
    # servidor no manda un Content-Type reconocible como texto (ej.
    # 'VERSION', sin extension: brexum.ar/Apache ni siquiera manda
    # Content-Type para ese archivo, y GitHub a veces tampoco es
    # consistente). Forzamos la decodificacion UTF-8 a mano en ese caso en
    # vez de confiar en que Invoke-WebRequest la haga sola.
    if ($resp.Content -is [byte[]]) {
        return [System.Text.Encoding]::UTF8.GetString($resp.Content)
    }
    return $resp.Content
}

function Invoke-WebRequestConReintento($UriPrimaria, $OutFile, $UriFallback) {
    $intentos = 3
    for ($i = 1; $i -le $intentos; $i++) {
        try {
            if ($OutFile) {
                Invoke-WebRequest -Uri $UriPrimaria -OutFile $OutFile -UseBasicParsing
            } else {
                return Obtener-TextoDeRespuesta (Invoke-WebRequest -Uri $UriPrimaria -UseBasicParsing)
            }
            return
        } catch {
            if ($i -eq $intentos) {
                if (-not $UriFallback) { throw }
                if ($OutFile) {
                    Invoke-WebRequest -Uri $UriFallback -OutFile $OutFile -UseBasicParsing
                    return
                } else {
                    return Obtener-TextoDeRespuesta (Invoke-WebRequest -Uri $UriFallback -UseBasicParsing)
                }
            }
            $espera = [Math]::Pow(2, $i)
            Start-Sleep -Seconds $espera
        }
    }
}

function Reparar-CarpetaSiHaceFalta($carpeta) {
    # La corrupcion de ACL (History restored, etc.) puede afectar tambien
    # a la carpeta contenedora, no solo al archivo: si no se puede crear
    # un archivo nuevo ahi adentro, Invoke-WebRequest tira
    # UnauthorizedAccessException aunque el archivo destino ni exista
    # todavia. Probamos crear un archivo de prueba; si falla, reparamos
    # la carpeta entera (recursivo) igual que a un archivo suelto.
    if (-not (Test-Path $carpeta)) { return }
    $prueba = Join-Path $carpeta ".olimpo-test-$([guid]::NewGuid().ToString('N'))"
    try {
        [System.IO.File]::Create($prueba).Close()
        Remove-Item $prueba -Force -ErrorAction SilentlyContinue
    } catch {
        takeown /F $carpeta /R /D Y *> $null
        icacls $carpeta /reset /T *> $null
        icacls $carpeta /grant "$($env:USERNAME):(OI)(CI)F" /T *> $null
    }
}

function Quitar-Lock($ruta) {
    if (Test-Path $ruta) {
        # /remove:d alcanza para el caso normal (DENY explicito puesto por
        # Aplicar-Lock en una instalacion anterior). Pero si la ACL del
        # archivo quedo corrupta (vacia o con permisos rotos, por ejemplo
        # tras un "History restored" de Windows) esto no alcanza y
        # Invoke-WebRequest tira UnauthorizedAccessException al escribir.
        # Repetimos ahi la reparacion manual: tomar posesion y resetear la
        # ACL a los permisos heredados por defecto.
        try { icacls $ruta /remove:d "$env:USERNAME" *> $null } catch {}
        # El atributo de "solo lectura" de Windows (FILE_ATTRIBUTE_READONLY)
        # es independiente del ACL y icacls/takeown no lo tocan. Si alguna
        # vez se corrio install.sh por error via Git Bash en esta misma
        # carpeta (mismo path ~/.config/opencode/... que usa la version
        # Windows), su "chmod 444" activa este atributo en NTFS y bloquea
        # la escritura aunque el ACL este perfecto.
        try { (Get-Item $ruta -Force).Attributes = (Get-Item $ruta -Force).Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly) } catch {}
        try {
            [System.IO.File]::OpenWrite($ruta).Close()
        } catch {
            takeown /F $ruta *> $null
            icacls $ruta /reset *> $null
            icacls $ruta /grant "$($env:USERNAME):(F)" *> $null
        }
    }
}

function Aplicar-Lock($ruta) {
    # Antes esto hacia icacls /inheritance:r + /deny (W,D). Se detecto que
    # ese mecanismo rompe la ejecucion de archivos .cmd: /inheritance:r
    # borra TODOS los permisos heredados (incluido Control Total de
    # SYSTEM/Administradores/el propio usuario) sin reemplazarlos, y aun
    # agregando de vuelta un grant explicito de Read&Execute, cualquier
    # DENY explicito en el archivo (de cualquier bit, W o D por separado)
    # terminaba bloqueando tambien la ejecucion — reproducido y confirmado
    # a mano. El atributo de "solo lectura" de Windows no tiene este
    # problema: bloquea escritura/borrado normal sin tocar permisos de
    # ejecucion para nada, y Quitar-Lock ya sabe limpiarlo (se agrego para
    # el caso del chmod 444 de Git Bash).
    (Get-Item $ruta -Force).Attributes = (Get-Item $ruta -Force).Attributes -bor [System.IO.FileAttributes]::ReadOnly
}

function Mostrar-Progreso($actual, $total) {
    # ASCII simple a proposito: los caracteres de bloque UTF-8 (█/░) se
    # corrompen ("ââââ") cuando este script se descarga y ejecuta via
    # Invoke-WebRequest/iex en PowerShell 5.1 sin control fino del
    # encoding. '#'/'.' funcionan siempre, sin importar el codepage de la
    # consola.
    $pct = [int](($actual / $total) * 100)
    $llenas = [int]($pct / 5)
    $vacias = 20 - $llenas
    $barra = ('#' * $llenas) + ('.' * $vacias)
    Write-Host -NoNewline "`r[Olimpo] [$barra] $pct%"
}

Write-Host "[Olimpo] Instalando/actualizando..."

# Si es una corrida local (repo ya clonado, ejecutando el script desde adentro)
# usamos los archivos locales; si vino por 'irm | iex' no hay $PSScriptRoot
# util, asi que bajamos cada archivo del repo por HTTPS.
$EsLocal = $PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot "payload"))

try {
    $totalPasos = $Payload.Count
    $pasoActual = 0
    foreach ($origen in $Payload.Keys) {
        $pasoActual++
        Mostrar-Progreso $pasoActual $totalPasos
        $destino = $Payload[$origen]
        $carpeta = Split-Path $destino
        New-Item -ItemType Directory -Force -Path $carpeta | Out-Null
        Reparar-CarpetaSiHaceFalta $carpeta
        Quitar-Lock $destino
        if ($EsLocal) {
            Copy-Item (Join-Path $PSScriptRoot $origen) $destino -Force
        } else {
            Invoke-WebRequestConReintento "$RepoRaw/$origen" $destino "$RepoRawFallback/$origen"
        }
    }
    Write-Host ""
} catch [System.UnauthorizedAccessException] {
    # OJO: nunca usar 'exit' aca. Cuando este script corre pegado dentro de
    # una consola interactiva (via iex, el uso normal), 'exit' cierra la
    # consola ENTERA en vez de solo cortar el script — se pierde el mensaje
    # de error antes de que de tiempo a leerlo. 'return' corta la ejecucion
    # del script sin tocar la consola que lo esta corriendo.
    Write-Host ""
    Write-Host "[Olimpo] No se pudo escribir en $destino por permisos de Windows."
    Write-Host "[Olimpo] Volvé a intentarlo desde una consola abierta como Administrador"
    Write-Host "[Olimpo] (click derecho sobre PowerShell -> 'Ejecutar como administrador')."
    return
}

# Registrar el archivo de instructions en la config de OpenCode sin pisar el
# resto (provider/model que ya tenga configurado el usuario).
$configJsonPath = Join-Path $OpencodeConfig "config.json"
$instructionsPath = "~/.config/opencode/rules/hefesto.md"
if (Test-Path $configJsonPath) {
    $config = Get-Content $configJsonPath -Raw | ConvertFrom-Json
    if (-not $config.instructions) {
        $config | Add-Member -NotePropertyName instructions -NotePropertyValue @($instructionsPath)
    } elseif ($config.instructions -notcontains $instructionsPath) {
        $config.instructions += $instructionsPath
    }
    $config | ConvertTo-Json -Depth 20 | Set-Content $configJsonPath -Encoding utf8
} else {
    New-Item -ItemType Directory -Force -Path $OpencodeConfig | Out-Null
    @{ instructions = @($instructionsPath) } | ConvertTo-Json | Set-Content $configJsonPath -Encoding utf8
}

# Shim para poder llamar "hermes" en vez de "python hermes.py" desde el PATH.
$hermesCmd = Join-Path $OlimpoBin "hermes.cmd"
Quitar-Lock $hermesCmd
@"
@echo off
python "%~dp0hermes.py" %*
"@ | Set-Content $hermesCmd -Encoding ascii

$pathUsuario = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($pathUsuario -notlike "*$OlimpoBin*") {
    [Environment]::SetEnvironmentVariable("PATH", "$pathUsuario;$OlimpoBin", "User")
    Write-Host "[Olimpo] Agregado $OlimpoBin al PATH de usuario (abrí una terminal nueva para que tome efecto)."
}

# Lock de escritura: protege los archivos instalados de una escritura
# accidental (por ejemplo, de Hefesto mismo) fuera del flujo de instalacion.
foreach ($destino in $Payload.Values) {
    Aplicar-Lock $destino
}
Aplicar-Lock $hermesCmd

# Version instalada, para poder comparar en el futuro.
$version = if ($EsLocal) { (Get-Content (Join-Path $PSScriptRoot "VERSION") -Raw).Trim() } else {
    (Invoke-WebRequestConReintento "$RepoRaw/VERSION" $null "$RepoRawFallback/VERSION").Trim()
}
Set-Content (Join-Path $env:USERPROFILE ".olimpo\VERSION") $version -Encoding ascii

Write-Host ""
Write-Host "[Olimpo] Instalación completada."
Write-Host "[Olimpo] Versión instalada: $version."
Write-Host "[Olimpo] Abrí una terminal nueva y corré 'hermes' en cualquier proyecto para arrancar."
Write-Host "[Olimpo] Para actualizar, volvé a correr este mismo instalador."
