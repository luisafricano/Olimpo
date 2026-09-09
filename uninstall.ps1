# Desinstalador de Olimpo para Windows.
# Uso: irm https://raw.githubusercontent.com/luisafricano/Olimpo/main/uninstall.ps1 | iex
#      Para saltear la confirmacion (uso no interactivo): setear $Force
#      ANTES del iex, ya que un 'param()' dentro de un string ejecutado con
#      iex no hereda variables del scope que lo llama:
#        $Force = $true; irm .../uninstall.ps1 | iex
#
# Espejo inverso de install.ps1: saca exactamente lo que ese instalador puso
# (mismo $Payload, mismo shim, misma entrada de PATH, misma entrada de
# config.json) y nada mas. Si install.ps1 agrega un archivo nuevo al
# payload, hay que agregarlo tambien aca para que no quede huerfano.
#
# No toca los transcripts de sesiones reales (logs/*.md bajo el config_dir
# de OpenCode) — son contenido del usuario, no archivos de instalacion.

# No se usa 'param([switch]$Force)' a proposito: cuando este script se
# ejecuta pegado dentro de un string via 'iex' (el uso normal, ver arriba),
# un param() de nivel superior no hereda nada del scope que llamo a iex y
# siempre vuelve al default. Una variable suelta si "cae" al scope de
# afuera si ya esta definida ahi.
if (-not (Test-Path variable:Force)) { $Force = $false }

$ErrorActionPreference = "Stop"

$OpencodeConfig = Join-Path $env:USERPROFILE ".config\opencode"
$ClaudeSkills = Join-Path $env:USERPROFILE ".claude\skills"
$OlimpoBin = Join-Path $env:USERPROFILE ".olimpo\bin"
$OlimpoHome = Join-Path $env:USERPROFILE ".olimpo"

# Mismo mapa que install.ps1 (payload/bin/hermes.py -> destino, etc.) —
# solo se usan los valores (los destinos), no hace falta bajar nada del repo.
$Payload = @{
    "payload/bin/hermes.py"                      = Join-Path $OlimpoBin "hermes.py"
    "payload/opencode-rules/hefesto.md"          = Join-Path $OpencodeConfig "rules\hefesto.md"
    "payload/opencode-skills/hefesto/SKILL.md"   = Join-Path $OpencodeConfig "skills\hefesto\SKILL.md"
    "payload/claude-skills/olimpo/SKILL.md"      = Join-Path $ClaudeSkills "olimpo\SKILL.md"
    "payload/claude-skills/olimpout/SKILL.md"    = Join-Path $ClaudeSkills "olimpout\SKILL.md"
    "payload/claude-skills/oloop/SKILL.md"       = Join-Path $ClaudeSkills "oloop\SKILL.md"
    "payload/claude-skills/noloop/SKILL.md"      = Join-Path $ClaudeSkills "noloop\SKILL.md"
}
$hermesCmd = Join-Path $OlimpoBin "hermes.cmd"

function Quitar-Lock($ruta) {
    if (Test-Path $ruta) {
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

function Quitar-LockCarpeta($carpeta) {
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

# hermes.py resuelve el config_dir real via 'opencode debug paths' (puede no
# coincidir con ~/.config/opencode si el usuario tiene XDG_CONFIG_HOME u
# otra config). Intentamos lo mismo; si opencode no esta disponible o falla,
# caemos al default que usa install.ps1.
function Resolver-ConfigDirOpencode {
    try {
        $salida = & opencode debug paths 2>$null
        if ($LASTEXITCODE -eq 0) {
            foreach ($linea in $salida) {
                $partes = $linea -split '\s+', 2
                if ($partes.Count -eq 2 -and $partes[0].Trim() -eq "config") {
                    return $partes[1].Trim()
                }
            }
        }
    } catch {}
    return $OpencodeConfig
}

Write-Host "[Olimpo] Se va a desinstalar lo siguiente:"
Write-Host "  - $OlimpoHome (binario hermes, shim, VERSION)"
foreach ($destino in $Payload.Values) { Write-Host "  - $destino" }
Write-Host "  - $ClaudeSkills\olimpo\, olimpout\, oloop\, noloop\"
Write-Host "  - Entrada de PATH de usuario apuntando a $OlimpoBin"
Write-Host "  - La entrada de Olimpo en config.json (instructions)"
Write-Host "  - El estado operativo de sesiones (hermes_sessions\)"
Write-Host ""
Write-Host "[Olimpo] NO se va a tocar: los transcripts de sesiones (logs\*.md)."
Write-Host ""

if (-not $Force) {
    $resp = Read-Host "Confirmar desinstalacion? (s/N)"
    if ($resp -notmatch '^[sS]$') {
        # No usar 'exit' aca: en una consola interactiva (uso normal via
        # iex) cierra la consola entera en vez de solo cortar el script.
        Write-Host "[Olimpo] Cancelado, no se borro nada."
        return
    }
}

# Archivos del payload + shim.
foreach ($destino in $Payload.Values) {
    Quitar-Lock $destino
    Remove-Item $destino -Force -ErrorAction SilentlyContinue
}
Quitar-Lock $hermesCmd
Remove-Item $hermesCmd -Force -ErrorAction SilentlyContinue

# Carpeta de la skill de Hefesto en OpenCode (queda vacia tras borrar el
# SKILL.md de arriba, pero por las dudas la borramos completa).
$hefestoSkillDir = Join-Path $OpencodeConfig "skills\hefesto"
Quitar-LockCarpeta $hefestoSkillDir
Remove-Item $hefestoSkillDir -Recurse -Force -ErrorAction SilentlyContinue

# Carpetas de las 4 skills de Claude.
foreach ($nombre in @("olimpo", "olimpout", "oloop", "noloop")) {
    $carpeta = Join-Path $ClaudeSkills $nombre
    Quitar-LockCarpeta $carpeta
    Remove-Item $carpeta -Recurse -Force -ErrorAction SilentlyContinue
}

# ~/.olimpo completo (bin/hermes.py, bin/hermes.cmd, bin/__pycache__/, VERSION).
Quitar-LockCarpeta $OlimpoBin
Quitar-LockCarpeta $OlimpoHome
Remove-Item $OlimpoHome -Recurse -Force -ErrorAction SilentlyContinue

# Entrada de Olimpo en config.json, sin tocar el resto (providers/modelos/
# otras instructions que el usuario haya agregado).
$configJsonPath = Join-Path $OpencodeConfig "config.json"
$instructionsPath = "~/.config/opencode/rules/hefesto.md"
if (Test-Path $configJsonPath) {
    $config = Get-Content $configJsonPath -Raw | ConvertFrom-Json
    if ($config.instructions -and ($config.instructions -contains $instructionsPath)) {
        $config.instructions = @($config.instructions | Where-Object { $_ -ne $instructionsPath })
        $config | ConvertTo-Json -Depth 20 | Set-Content $configJsonPath -Encoding utf8
    }
}

# Estado operativo puro de hermes.py (no son transcripts, son solo el
# puntero a la sesion activa por proyecto). Los logs/*.md quedan intactos.
$configDirReal = Resolver-ConfigDirOpencode
$sessionsDir = Join-Path $configDirReal "hermes_sessions"
if (Test-Path $sessionsDir) {
    Remove-Item $sessionsDir -Recurse -Force -ErrorAction SilentlyContinue
}

# Entrada de PATH de usuario — solo el segmento exacto de Olimpo.
$pathUsuario = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($pathUsuario -and ($pathUsuario -like "*$OlimpoBin*")) {
    $segmentos = $pathUsuario -split ';' | Where-Object { $_ -and ($_.TrimEnd('\') -ne $OlimpoBin.TrimEnd('\')) }
    [Environment]::SetEnvironmentVariable("PATH", ($segmentos -join ';'), "User")
}

Write-Host ""
Write-Host "[Olimpo] Desinstalado."
$logsDir = Join-Path $configDirReal "logs"
Write-Host "[Olimpo] Los transcripts de sesiones (si los hay) quedaron en $logsDir — no se tocaron."
Write-Host "[Olimpo] Abrí una terminal nueva para que el PATH actualizado tome efecto."
