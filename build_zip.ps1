# ============================================================================
# build_zip.ps1 - Package the Bootloop Guard Magisk module (repo layout)
# Usage:  powershell -ExecutionPolicy Bypass -File .\build_zip.ps1
# Output: bootloop_guard_<version>.zip  (version auto-read from module.prop)
# Note:   ASCII-only on purpose (PS5.1 reads BOM-less UTF-8 as ANSI).
#         Packs an explicit file list so LICENSE/.gitignore/etc stay out.
# ============================================================================
$ErrorActionPreference = 'Stop'

$ModuleFiles = @(
    'module.prop', 'post-fs-data.sh', 'service.sh', 'action.sh',
    'customize.sh', 'config.conf', 'whitelist.conf', 'README.md'
)

# version from module.prop -> zip file name
$propText = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'module.prop'))
$m = [regex]::Match($propText, '(?m)^version=(.+)$')
if (-not $m.Success) { throw 'version= not found in module.prop' }
$Version = $m.Groups[1].Value.Trim()
$ZipOut = Join-Path $PSScriptRoot ("bootloop_guard_" + $Version + ".zip")

if (Test-Path $ZipOut) { Remove-Item $ZipOut -Force }

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$zip = [System.IO.Compression.ZipFile]::Open($ZipOut, 'Create')
try {
    foreach ($name in $ModuleFiles) {
        $p = Join-Path $PSScriptRoot $name
        if (-not (Test-Path $p)) { throw "missing module file: $name" }
        $text = [System.IO.File]::ReadAllText($p)
        $text = $text -replace "`r`n", "`n" -replace "`r", "`n"   # force LF
        $entry = $zip.CreateEntry($name)
        $sw = New-Object System.IO.StreamWriter($entry.Open(), (New-Object System.Text.UTF8Encoding($false)))
        try { $sw.Write($text) } finally { $sw.Dispose() }
        Write-Host ("  packed: " + $name)
    }
} finally {
    $zip.Dispose()
}

Write-Host "[OK] Created: $ZipOut" -ForegroundColor Green
$zip = [System.IO.Compression.ZipFile]::OpenRead($ZipOut)
try {
    if (-not ($zip.Entries | Where-Object { $_.FullName -eq 'module.prop' })) {
        throw "module.prop is missing at zip root!"
    }
    Write-Host ("[OK] " + $zip.Entries.Count + " entries, module.prop at zip root, LF enforced")
} finally {
    $zip.Dispose()
}
