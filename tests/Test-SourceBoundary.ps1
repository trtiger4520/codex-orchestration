[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$guard = Join-Path $root 'src\.agents\skills\verify\scripts\Test-SourceBoundary.ps1'
$pwsh = (Get-Process -Id $PID).Path
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "codex-boundary-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $tempRoot | Out-Null

try {
    & git -C $tempRoot init --quiet
    Set-Content -LiteralPath (Join-Path $tempRoot 'source.txt') -Value 'baseline' -NoNewline
    & git -C $tempRoot add source.txt
    New-Item -ItemType Directory -Path (Join-Path $tempRoot 'bin') | Out-Null
    Set-Content -LiteralPath (Join-Path $tempRoot '.gitignore') -Value "ignored/`n" -NoNewline
    & git -C $tempRoot add .gitignore

    $snapshot = Join-Path $tempRoot '.git\boundary.json'
    & $pwsh -NoProfile -File $guard -Mode Capture -Repository $tempRoot -SnapshotFile $snapshot
    if ($LASTEXITCODE -ne 0) { throw 'Boundary capture failed' }

    Set-Content -LiteralPath (Join-Path $tempRoot 'bin\artifact.dll') -Value 'artifact' -NoNewline
    & $pwsh -NoProfile -File $guard -Mode Verify -Repository $tempRoot -SnapshotFile $snapshot -AllowedWrite '**/bin/**'
    if ($LASTEXITCODE -ne 0) { throw 'Allowed artifact was rejected' }

    Set-Content -LiteralPath (Join-Path $tempRoot 'source.txt') -Value 'changed' -NoNewline
    & $pwsh -NoProfile -File $guard -Mode Verify -Repository $tempRoot -SnapshotFile $snapshot -AllowedWrite '**/bin/**' 2>$null
    if ($LASTEXITCODE -eq 0) { throw 'Tracked source change was not rejected' }

    Set-Content -LiteralPath (Join-Path $tempRoot 'source.txt') -Value 'baseline' -NoNewline
    Set-Content -LiteralPath (Join-Path $tempRoot 'new-source.txt') -Value 'new' -NoNewline
    & $pwsh -NoProfile -File $guard -Mode Verify -Repository $tempRoot -SnapshotFile $snapshot -AllowedWrite '**/bin/**' 2>$null
    if ($LASTEXITCODE -eq 0) { throw 'Non-ignored untracked source was not rejected' }

    New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot 'ignored') | Out-Null
    Set-Content -LiteralPath (Join-Path $tempRoot 'ignored\cache.txt') -Value 'ignored' -NoNewline
    Remove-Item -LiteralPath (Join-Path $tempRoot 'new-source.txt')
    & $pwsh -NoProfile -File $guard -Mode Verify -Repository $tempRoot -SnapshotFile $snapshot -AllowedWrite '**/bin/**'
    if ($LASTEXITCODE -ne 0) { throw 'Ignored file was treated as a boundary change' }
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}

Write-Output 'All source boundary tests passed'
