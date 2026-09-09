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

function Invoke-WebRequestConReintento($UriPrimaria, $OutFile, $UriFallback) {
    $intentos = 3
    for ($i = 1; $i -le $intentos; $i++) {
        try {
            if ($OutFile) {
                Invoke-WebRequest -Uri $UriPrimaria -OutFile $OutFile
            } else {
                return Invoke-WebRequest -Uri $UriPrimaria
            }
            return
        } catch {
            if ($i -eq $intentos) {
                if (-not $UriFallback) { throw }
                if ($OutFile) {
                    Invoke-WebRequest -Uri $UriFallback -OutFile $OutFile
                    return
                } else {
                    return Invoke-WebRequest -Uri $UriFallback
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
    icacls $ruta /inheritance:r *> $null
    icacls $ruta /deny "$($env:USERNAME):(W,D)" *> $null
}

Write-Host "[Olimpo] Instalando/actualizando..."

# Si es una corrida local (repo ya clonado, ejecutando el script desde adentro)
# usamos los archivos locales; si vino por 'irm | iex' no hay $PSScriptRoot
# util, asi que bajamos cada archivo del repo por HTTPS.
$EsLocal = $PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot "payload"))

try {
    foreach ($origen in $Payload.Keys) {
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
} catch [System.UnauthorizedAccessException] {
    Write-Host ""
    Write-Host "[Olimpo] No se pudo escribir en $destino por permisos de Windows."
    Write-Host "[Olimpo] Volvé a intentarlo desde una consola abierta como Administrador"
    Write-Host "[Olimpo] (click derecho sobre PowerShell -> 'Ejecutar como administrador')."
    exit 1
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
    (Invoke-WebRequestConReintento "$RepoRaw/VERSION" $null "$RepoRawFallback/VERSION").Content.Trim()
}
Set-Content (Join-Path $env:USERPROFILE ".olimpo\VERSION") $version -Encoding ascii

Write-Host ""
Write-Host "[Olimpo] Instalado (version $version)."
Write-Host "[Olimpo] Abrí una terminal nueva y corré 'hermes' en cualquier proyecto para arrancar."
Write-Host "[Olimpo] Para actualizar, volvé a correr este mismo instalador."
