[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Context,
    [ValidateSet('meilisearch','qdrant','all')][string]$Target = 'all',
    [switch]$Write
)
$ErrorActionPreference = 'Stop'
$namespace = 'mosquizto-eks'
# Resolve the image from the tracked overlay: Jobs always use its exact digest.
$rendered = & kubectl --context=$Context apply --dry-run=client -k (Join-Path $PSScriptRoot '../../overlays/eks') -o json
if ($LASTEXITCODE -ne 0) { throw 'Cannot render EKS overlay' }
$items = (($rendered -join "`n") | ConvertFrom-Json).items
$backend = $items | Where-Object { $_.kind -eq 'Deployment' -and $_.metadata.name -eq 'mosquizto-backend-deployemnt' }
$image = $backend.spec.template.spec.containers[0].image
if ($image -notmatch '@sha256:[a-f0-9]{64}$') { throw 'EKS image must be pinned by digest' }
$liveImage = & kubectl --context=$Context -n $namespace get deployment mosquizto-backend-deployemnt -o 'jsonpath={.spec.template.spec.containers[0].image}'
if ($LASTEXITCODE -ne 0 -or $liveImage -ne $image) { throw 'Live backend and tracked overlay must use the same image digest' }
$raw = & kubectl --context=$Context create --dry-run=client -f (Join-Path $PSScriptRoot 'sync-job.yaml') -o json
if ($LASTEXITCODE -ne 0) { throw 'Cannot validate sync Job template' }
$job = ($raw -join "`n") | ConvertFrom-Json
$job.metadata.name = 'mosquizto-sync-' + [guid]::NewGuid().ToString('N').Substring(0,12)
$container = $job.spec.template.spec.containers[0]
$container.image = $image
foreach ($entry in $container.env) {
    if ($entry.name -eq 'SYNC_TARGET') { $entry.value = $Target }
    if ($entry.name -eq 'SYNC_DRY_RUN') { $entry.value = (-not $Write).ToString().ToLowerInvariant() }
}
$job | ConvertTo-Json -Depth 40 | & kubectl --context=$Context -n $namespace create -f -
if ($LASTEXITCODE -ne 0) { throw 'Job creation failed' }
Write-Output "Job: $($job.metadata.name)"
Write-Output "kubectl --context=$Context -n $namespace logs -f job/$($job.metadata.name)"
