param(
    [ValidateSet("Win64", "Win32")]
    [string]$Platform = "Win64",
    [string]$RsvarsPath = "",
    [switch]$Synapse,
    [string]$SynapsePath = ""
)

$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $PSScriptRoot
$BinDir = Join-Path $RootDir "bin\delphi-$Platform"
$DcuDir = Join-Path $RootDir "lib\delphi-$Platform"

New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
New-Item -ItemType Directory -Force -Path $DcuDir | Out-Null

if ($RsvarsPath -eq "") {
    $Candidates = @(
        "C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\rsvars.bat",
        "C:\Program Files (x86)\Embarcadero\Studio\22.0\bin\rsvars.bat"
    )
    foreach ($C in $Candidates) {
        if (Test-Path $C) {
            $RsvarsPath = $C
            break
        }
    }
}

if ($RsvarsPath -ne "" -and (Test-Path $RsvarsPath)) {
    cmd /c "`"$RsvarsPath`" && set" | ForEach-Object {
        if ($_ -match "^([^=]+)=(.*)$") {
            [System.Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], "Process")
        }
    }
}

$Compiler = if ($Platform -eq "Win64") { "dcc64.exe" } else { "dcc32.exe" }
if (-not (Get-Command $Compiler -ErrorAction SilentlyContinue)) {
    throw "$Compiler not found on PATH. Provide -RsvarsPath pointing to Delphi 11+ rsvars.bat."
}

$CommonFlags = @(
    "-B",
    "-W+",
    "-H+",
    "-I$RootDir\src",
    "-U$RootDir\src;$RootDir\tests",
    "-N0$DcuDir",
    "-E$BinDir"
)

if ($Synapse) {
    $CommonFlags += "-DRSTMDB_TRANSPORT_SYNAPSE"
    if ($SynapsePath -ne "") {
        $CommonFlags += "-U$SynapsePath"
    }
}

function Invoke-Dcc {
    param([string]$Target)
    Write-Host "==> Compiling $Target ($Platform)"
    & $Compiler @CommonFlags $Target
    if ($LASTEXITCODE -ne 0) {
        throw "Compilation failed for $Target (exit $LASTEXITCODE)"
    }
}

Invoke-Dcc (Join-Path $RootDir "packages\rstmdb_pascal.dpk")
Invoke-Dcc (Join-Path $RootDir "tests\RunTests.dpr")
Invoke-Dcc (Join-Path $RootDir "tests\RunLiveIntegration.dpr")
Invoke-Dcc (Join-Path $RootDir "examples\BasicUsage.dpr")
Invoke-Dcc (Join-Path $RootDir "examples\WatchEvents.dpr")

Write-Host "==> Running Delphi unit tests (ReportMemoryLeaksOnShutdown active)"
& (Join-Path $BinDir "RunTests.exe")
if ($LASTEXITCODE -ne 0) {
    throw "RunTests.exe failed with exit code $LASTEXITCODE"
}

Write-Host "Delphi verification completed cleanly."
