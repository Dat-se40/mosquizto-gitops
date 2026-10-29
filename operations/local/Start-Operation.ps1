[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('prepare-model', 'sync')]
    [string]$Operation,
    [string]$Context = 'minikube',
    [ValidateSet('meilisearch', 'qdrant', 'all')]
    [string]$Target = 'all',
    [switch]$Write,
    [ValidateSet('none', 'preview', 'delete')]
    [string]$Cleanup = 'none',
    [switch]$MaintenanceConfirmed,
    [string]$Image = 'mosquizto-backend:local-sync-002'
)
$ErrorActionPreference = 'Stop'
$namespace = 'mosquizto-local'
if ($Cleanup -eq 'delete' -and $Write -and -not $MaintenanceConfirmed) {
    throw 'Stop application writes first, then explicitly pass -MaintenanceConfirmed.'
}
$template = Join-Path $PSScriptRoot ($Operation + '-job.yaml')
if ($Operation -eq 'sync') { $template = Join-Path $PSScriptRoot 'sync-job.yaml' }
$raw = & kubectl --context=$Context -n $namespace create --dry-run=client -f $template -o json
if ($LASTEXITCODE -ne 0) { throw 'Cannot load/validate Job template' }
$job = ($raw -join "`n") | ConvertFrom-Json
$job.metadata.name = 'mosquizto-' + $Operation + '-' + [guid]::NewGuid().ToString('N').Substring(0, 12)
$container = $job.spec.template.spec.containers[0]
$container.image = $Image
if ($Operation -eq 'sync') {
    $values = @{
        SYNC_TARGET = $Target
        SYNC_DRY_RUN = (-not $Write).ToString().ToLowerInvariant()
        SYNC_CLEANUP = $Cleanup
        SYNC_MAINTENANCE_CONFIRMED = $MaintenanceConfirmed.IsPresent.ToString().ToLowerInvariant()
    }
    foreach ($entry in $container.env) {
        if ($values.ContainsKey($entry.name)) { $entry.value = $values[$entry.name] }
    }
    if ($Target -eq 'qdrant') {
        $container.env = @($container.env | Where-Object { $_.name -ne 'MEILI_MASTER_KEY' })
    }
    if ($Target -eq 'meilisearch') {
        $container.envFrom = @($container.envFrom | Where-Object {
            $_.configMapRef.name -ne 'mosquizto-model-config'
        })
        $container.PSObject.Properties.Remove('volumeMounts')
        $job.spec.template.spec.PSObject.Properties.Remove('volumes')
    }
}
$job | ConvertTo-Json -Depth 50 | & kubectl --context=$Context -n $namespace create -f -
if ($LASTEXITCODE -ne 0) { throw 'Job creation failed' }
Write-Output "Job: $($job.metadata.name)"
Write-Output "Follow: kubectl --context=$Context -n $namespace logs -f job/$($job.metadata.name)"
Write-Output "Status: kubectl --context=$Context -n $namespace get job $($job.metadata.name)"
