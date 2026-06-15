# One-click installer for Claude Code (Windows / PowerShell).
# - Detects architecture
# - Detects whether you're on a China IP and, if so, uses mirror sources
# - Installs Node.js (MSI silent install, mirror-supported) if it's missing
# - Installs @anthropic-ai/claude-code globally via npm
#
# Run in PowerShell:  irm <url>/install.ps1 | iex
#   or:               powershell -ExecutionPolicy Bypass -File install.ps1

$ErrorActionPreference = 'Stop'

$Pkg          = '@anthropic-ai/claude-code'
$MinNodeMajor = 18
$NpmMirror    = 'https://registry.npmmirror.com'
$NodeDist     = 'https://nodejs.org/dist'
$NodeMirror   = 'https://npmmirror.com/mirrors/node'

function Write-Info { param($m) Write-Host "[*] $m" -ForegroundColor Blue }
function Write-Ok   { param($m) Write-Host "[+] $m" -ForegroundColor Green }
function Write-Warn { param($m) Write-Host "[!] $m" -ForegroundColor Yellow }
function Die        { param($m) Write-Host "[x] $m" -ForegroundColor Red; exit 1 }

# --- detect architecture -----------------------------------------------------
function Get-Arch {
    $a = $env:PROCESSOR_ARCHITECTURE
    switch -Regex ($a) {
        'ARM64'        { return 'arm64' }
        'AMD64|x86_64' { return 'x64' }
        'x86'          { return 'x86' }
        default        { Write-Warn "Unrecognized architecture '$a' — proceeding anyway."; return $a }
    }
}

# --- detect China IP ---------------------------------------------------------
function Test-China {
    try {
        $trace = (Invoke-WebRequest -Uri 'https://www.cloudflare.com/cdn-cgi/trace' `
                    -UseBasicParsing -TimeoutSec 3).Content
        $m = [regex]::Match($trace, '(?m)^loc=(\w+)')
        if ($m.Success) { return ($m.Groups[1].Value -eq 'CN') }
    } catch {}

    try {
        $country = (Invoke-WebRequest -Uri 'https://ipinfo.io/country' `
                      -UseBasicParsing -TimeoutSec 3).Content.Trim()
        if ($country) { return ($country -eq 'CN') }
    } catch {}

    $googleOk = $false; $mirrorOk = $false
    try { Invoke-WebRequest -Uri 'https://www.google.com' -UseBasicParsing -TimeoutSec 2 | Out-Null; $googleOk = $true } catch {}
    try { Invoke-WebRequest -Uri $NpmMirror -UseBasicParsing -TimeoutSec 2 | Out-Null; $mirrorOk = $true } catch {}
    if (-not $googleOk -and $mirrorOk) { return $true }

    return $false
}

# --- node version check ------------------------------------------------------
function Test-NodeOk {
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) { return $false }
    try {
        $major = [int](& node -p 'process.versions.node.split(".")[0]')
        return ($major -ge $MinNodeMajor)
    } catch { return $false }
}

function Update-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('Path','User')
}

# --- get latest LTS version --------------------------------------------------
function Get-LtsVersion {
    $baseUrl = if ($script:China) { $NodeMirror } else { $NodeDist }
    try {
        $json = (Invoke-WebRequest -Uri "$baseUrl/index.json" -UseBasicParsing -TimeoutSec 10).Content
        $data = $json | ConvertFrom-Json
        $lts = $data | Where-Object { $_.lts -and $_.lts -ne '' } | Select-Object -First 1
        if ($lts) { return $lts.version }  # e.g. "v22.16.0"
    } catch {}
    Die "Failed to fetch Node.js LTS version from $baseUrl/index.json."
}

# --- install node via MSI silent install --------------------------------------
function Install-Node {
    $arch = Get-Arch
    Write-Info "Node.js >= $MinNodeMajor not found. Downloading and installing..."

    $ver = Get-LtsVersion
    $baseUrl = if ($script:China) { $NodeMirror } else { $NodeDist }
    $msiName = "node-$ver-x64.msi"
    if ($arch -eq 'arm64') { $msiName = "node-$ver-arm64.msi" }
    $msiUrl  = "$baseUrl/$ver/$msiName"
    $msiPath = "$env:TEMP\$msiName"

    Write-Info "Downloading $msiUrl ..."
    try {
        Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath -UseBasicParsing -TimeoutSec 120
    } catch {
        Die "Failed to download Node.js from $msiUrl. Check your network or install Node $MinNodeMajor+ manually from https://nodejs.org/en/download."
    }

    Write-Info "Installing Node.js (silent MSI)..."
    $proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList '/i',$msiPath,'/qn','/norestart' -Wait -PassThru
    Remove-Item $msiPath -Force -ErrorAction SilentlyContinue
    if ($proc.ExitCode -ne 0) {
        Die "Node.js MSI install failed (exit code $($proc.ExitCode)). Install Node $MinNodeMajor+ manually from https://nodejs.org/en/download."
    }

    # MSI installer updates Machine PATH automatically; refresh current session
    Update-Path

    if (-not (Test-NodeOk)) {
        Die "Node.js installed but not on PATH yet. Open a NEW PowerShell window and run 'claude'."
    }
    Write-Ok "Node.js installed: $(& node -v)"
}

# --- main --------------------------------------------------------------------
$arch = Get-Arch
Write-Info "Platform: windows/$arch"

if (Get-Command claude -ErrorAction SilentlyContinue) {
    $ver = (& claude --version) 2>$null
    if (-not $ver) { $ver = 'present' }
    Write-Ok "Claude Code already installed: $ver"
    Write-Info "Nothing to do. To upgrade, run: npm update -g $Pkg"
    exit 0
}

$script:China = Test-China
if ($script:China) {
    Write-Ok  "China IP detected — using mirror sources."
} else {
    Write-Info "Non-China IP (or undetermined) — using default sources."
}

if (Test-NodeOk) {
    Write-Ok "Node.js present: $(& node -v)"
} else {
    Install-Node
}

if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    Die "npm not found even though Node is installed. Open a new PowerShell window and re-run."
}

$regArgs = @()
if ($script:China) {
    $regArgs = @('--registry', $NpmMirror)
    Write-Info "Installing $Pkg via npmmirror registry..."
} else {
    Write-Info "Installing $Pkg via default npm registry..."
}

& npm install -g $Pkg @regArgs
if ($LASTEXITCODE -ne 0) {
    Die "npm install failed. Try a new elevated PowerShell, or see https://docs.npmjs.com/resolving-eacces-permissions-errors"
}

Update-Path
if (Get-Command claude -ErrorAction SilentlyContinue) {
    $ver = (& claude --version) 2>$null
    if (-not $ver) { $ver = $Pkg }
    Write-Ok "Done. Installed: $ver"
    Write-Info "Run 'claude' to get started."
} else {
    Write-Ok "Package installed."
    Write-Warn "'claude' isn't on PATH yet — open a new terminal, then run: claude"
}
