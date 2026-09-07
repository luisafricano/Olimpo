# Instalador de Olimpo para Windows.
# Uso: irm https://raw.githubusercontent.com/luisafricano/Olimpo/main/install.ps1 | iex
#
# Copia los archivos de sesion compartida Zeus/Claude/Hefesto a los lugares
# donde OpenCode y Claude Code los leen, y deja `hermes` disponible en el
# PATH del usuario. Correr de nuevo este mismo script actualiza todo
# (reconcilia con lo ultimo del repo).

$ErrorActionPreference = "Stop"

$RepoRaw = "https://raw.githubusercontent.com/luisafricano/Olimpo/main"
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

function Quitar-Lock($ruta) {
    if (Test-Path $ruta) {
        try { icacls $ruta /remove:d "$env:USERNAME" *> $null } catch {}
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

foreach ($origen in $Payload.Keys) {
    $destino = $Payload[$origen]
    New-Item -ItemType Directory -Force -Path (Split-Path $destino) | Out-Null
    Quitar-Lock $destino
    if ($EsLocal) {
        Copy-Item (Join-Path $PSScriptRoot $origen) $destino -Force
    } else {
        Invoke-WebRequest -Uri "$RepoRaw/$origen" -OutFile $destino
    }
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
    (Invoke-WebRequest -Uri "$RepoRaw/VERSION").Content.Trim()
}
Set-Content (Join-Path $env:USERPROFILE ".olimpo\VERSION") $version -Encoding ascii

Write-Host ""
Write-Host "[Olimpo] Instalado (version $version)."
Write-Host "[Olimpo] Abrí una terminal nueva y corré 'hermes' en cualquier proyecto para arrancar."
Write-Host "[Olimpo] Para actualizar, volvé a correr este mismo instalador."
