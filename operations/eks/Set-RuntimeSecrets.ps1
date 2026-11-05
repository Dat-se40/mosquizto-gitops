[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Context,
    [string]$EnvFile = (Join-Path $PSScriptRoot '../../overlays/eks/.secret.env')
)
$ErrorActionPreference = 'Stop'
$values = @{}
foreach ($line in Get-Content -LiteralPath $EnvFile -Encoding UTF8) {
    if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) { continue }
    if ($line -notmatch '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') { throw 'Invalid env entry' }
    if ($values.ContainsKey($Matches[1])) { throw "Duplicate env key: $($Matches[1])" }
    $values[$Matches[1]] = $Matches[2]
}
$required = @('DB_PASSWORD','MAIL_ADDRESS','MAIL_USERNAME','MAIL_PASSWORD',
    'JWT_ACCESS_KEY','JWT_REFRESH_KEY','JWT_RESET_KEY','MEILI_MASTER_KEY','GOOGLE_CLIENT_ID',
    'CLOUDINARY_NAME','CLOUDINARY_API_KEY','CLOUDINARY_API_SECRET','WS_MESSAGE_TIME_OUT','WS_CONNECT_ENDPOINT')
foreach ($key in $required) {
    if (-not $values.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($values[$key]) -or
        $values[$key].StartsWith('REPLACE_WITH_')) { throw "Missing usable value for $key" }
}
foreach ($name in @('mosquizto-secret','mosquizto-sync-secret')) {
    $selected = $values
    if ($name -eq 'mosquizto-sync-secret') {
        $selected = @{DB_PASSWORD=$values.DB_PASSWORD; MEILI_MASTER_KEY=$values.MEILI_MASTER_KEY}
    }
    $secret = @{
        apiVersion='v1'; kind='Secret'; type='Opaque'
        metadata=@{name=$name; namespace='mosquizto-eks'}
        stringData=$selected
    }
    # Secrets travel on stdin, never in process arguments or files rendered into Git.
    $secret | ConvertTo-Json -Depth 10 | & kubectl --context=$Context -n mosquizto-eks apply -f -
    if ($LASTEXITCODE -ne 0) { throw "Cannot provision $name" }
}
Write-Output 'Secrets provisioned. Existing backend Pods require an explicit restart after rotation.'
