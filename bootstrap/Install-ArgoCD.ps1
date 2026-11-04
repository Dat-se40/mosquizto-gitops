[CmdletBinding()]
param([Parameter(Mandatory)][string]$Context)
$ErrorActionPreference = 'Stop'
$version = 'v3.6.0'
$sha256 = 'c1d7ec243fa63ce675d71e564775ae42bf11608d35436d5c5951365b6c86fa6a'
$manifest = Join-Path ([IO.Path]::GetTempPath()) ('argocd-' + [guid]::NewGuid().ToString('N') + '.yaml')
try {
    Invoke-WebRequest "https://raw.githubusercontent.com/argoproj/argo-cd/$version/manifests/install.yaml" -UseBasicParsing -OutFile $manifest
    if ((Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash.ToLowerInvariant() -ne $sha256) {
        throw 'Pinned Argo CD manifest checksum mismatch'
    }
    & kubectl --context=$Context create namespace argocd --dry-run=client -o yaml | & kubectl --context=$Context apply -f -
    if ($LASTEXITCODE -ne 0) { throw 'Cannot create Argo CD namespace' }
    & kubectl --context=$Context -n argocd apply --server-side -f $manifest
    if ($LASTEXITCODE -ne 0) { throw 'Cannot install Argo CD' }
    & kubectl --context=$Context -n argocd rollout status deployment/argocd-server --timeout=300s
    if ($LASTEXITCODE -ne 0) { throw 'Argo CD server is not ready' }
} finally {
    if (Test-Path -LiteralPath $manifest) { Remove-Item -LiteralPath $manifest }
}
