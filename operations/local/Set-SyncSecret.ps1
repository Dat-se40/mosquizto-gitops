[CmdletBinding()]
param(
    [string]$Context = 'minikube',
    [string]$EnvFile = (Join-Path $PSScriptRoot '../../base/.secret.env')
)
$ErrorActionPreference = 'Stop'
$selected = @{}
foreach ($line in Get-Content -LiteralPath $EnvFile -Encoding UTF8) {
    if ($line.TrimStart().StartsWith('#') -or $line.IndexOf('=') -lt 1) { continue }
    $parts = $line.Split('=', 2)
    $key = $parts[0].Trim()
    if ($key -in @('DB_PASSWORD', 'MEILI_MASTER_KEY')) { $selected[$key] = $parts[1] }
}
foreach ($key in @('DB_PASSWORD', 'MEILI_MASTER_KEY')) {
    if (-not $selected.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($selected[$key]) -or
            $selected[$key].StartsWith('REPLACE_WITH_')) {
        throw "Missing usable value for $key"
    }
}
# Only required credentials are copied. Never print the JSON or pass values in argv.
$secret = @{
    apiVersion = 'v1'
    kind = 'Secret'
    type = 'Opaque'
    metadata = @{ name = 'mosquizto-sync-secret'; namespace = 'mosquizto-local' }
    stringData = $selected
}
$secret | ConvertTo-Json -Depth 10 | & kubectl --context=$Context -n mosquizto-local apply -f -
if ($LASTEXITCODE -ne 0) { throw 'Cannot provision local sync Secret' }
