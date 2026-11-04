[CmdletBinding()]
param(
    [string]$BaseEnv = (Join-Path $PSScriptRoot '../../base/.secret.env'),
    [string]$LocalEnv = (Join-Path $PSScriptRoot '../../overlays/local/.local.secret.env'),
    [string]$OutputFile = (Join-Path $PSScriptRoot '../../overlays/local/.runtime.secret.env')
)
$ErrorActionPreference = 'Stop'
$values = [ordered]@{}
foreach ($file in @($BaseEnv, $LocalEnv)) {
    foreach ($line in Get-Content -LiteralPath $file -Encoding UTF8) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) { continue }
        if ($line -notmatch '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') { throw "Invalid env entry in $file" }
        $values[$Matches[1]] = $Matches[2]
    }
}
$lines = @($values.GetEnumerator() | ForEach-Object { $_.Key + '=' + $_.Value })
[IO.File]::WriteAllLines([IO.Path]::GetFullPath($OutputFile), $lines, [Text.UTF8Encoding]::new($false))
Write-Output 'Updated ignored local runtime env (base values, then local overrides).'
