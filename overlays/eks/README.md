# Mosquizto on EKS (lab)

Run commands from the GitOps repository root with AWS credentials configured for
the cluster account. Always pass the EKS context explicitly. Five services run
in `mosquizto-eks`; the database is new and initialized by existing Flyway migrations.
Jenkins CI automation and public ingress are outside this milestone.

## Prerequisites

- Two Ready workers, healthy CoreDNS/CNI, working cluster DNS.
- EBS CSI and `mosquizto-gp3`, provisioned from the infra repository's
  `kubernetes/storage` tooling. A PVC write/recreate/read check must pass first.
- Backend built from the recorded Git commit with `INCLUDE_EMBEDDING_MODEL=true`,
  Linux amd64; model/tokenizer SHA-256 verified as UID 10001.
- Immutable image in private ECR. The `images` entry in this overlay must contain
  the verified registry digest. Both the backend and manual sync Job use it.

## Runtime secrets (outside Git and Argo CD)

Copy `base/.secret.env.example` to `overlays/eks/.secret.env`, supply valid
integration settings and generate fresh DB/JWT/Meilisearch credentials for EKS.
Do not replace a password after PostgreSQL has initialized without rotating it
in PostgreSQL too. Do not print or commit this file or a rendered Secret.

```powershell
kubectl --context=mosquizto-eks apply -f bootstrap/eks/namespace.yaml
./operations/eks/Set-RuntimeSecrets.ps1 -Context mosquizto-eks
```

The script checks required keys and provisions `mosquizto-secret` plus the
smaller `mosquizto-sync-secret` through stdin. Argo CD does not manage either
Secret. After an intentional runtime-secret rotation, explicitly restart the
backend to load new environment values.

## Validate and bootstrap

```powershell
kubectl kustomize overlays/eks | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Render failed' }
kubectl --context=mosquizto-eks apply --dry-run=server -k overlays/eks
if ($LASTEXITCODE -ne 0) { throw 'Server validation failed' }
./bootstrap/Install-ArgoCD.ps1 -Context mosquizto-eks
kubectl --context=mosquizto-eks apply -k bootstrap/eks
```

Publish the verified overlay to `main` before syncing. The AppProject permits
only this repository, the application namespace, Deployments, Services,
ConfigMaps and PVCs. Namespaces, Secrets, storage and Argo CD itself are bootstrap
resources. Review the first diff and sync manually in the UI:

```powershell
kubectl --context=mosquizto-eks -n argocd port-forward service/argocd-server 18443:443
```

After acceptance, enable automated sync with self-heal in the tracked Application;
leave prune disabled. PVCs also carry `Prune=false,Delete=false`. The Application
has no cascading-deletion finalizer. Never put manual operation templates in the
Application source path or register them as Argo CD hooks.

## Verify the application and ONNX

```powershell
kubectl --context=mosquizto-eks -n mosquizto-eks get deploy,pods,svc,pvc
kubectl --context=mosquizto-eks -n mosquizto-eks rollout status deployment/mosquizto-backend-deployemnt --timeout=360s
kubectl --context=mosquizto-eks -n mosquizto-eks port-forward service/mosquizto-service 18080:8080
```

Open `/swagger-ui/index.html` and `/v3/api-docs` on `http://localhost:18080`.
Check valid login and invalid-login HTTP 401. Confirm `Embedding ready` in backend
logs; HTTP readiness alone does not prove inference works.

```powershell
./operations/eks/Start-Sync.ps1 -Context mosquizto-eks
# Inspect the completed Job/report before running the write operation:
./operations/eks/Start-Sync.ps1 -Context mosquizto-eks -Write
```

Use the Job name printed by each command for `kubectl logs` and `kubectl wait`.
The script rejects a mismatch between the overlay's digest and the live backend.
Jobs use the bundled model, separate sync Secret and no model PVC. Dry-run is
the default; cleanup is disabled. Verify collection/document/point counts after
the write, and finite, normalized 384-dimensional vectors in Qdrant.

## Data, resources and rollback

PVCs: PostgreSQL 2Gi; Redis, Meilisearch and Qdrant 1Gi each, RWO. Each dependency
has one replica and Recreate strategy. There is no HA or backup guarantee.
Retain means deleting a PVC leaves a billable volume for explicit recovery or
cleanup by its owner. Recreate PostgreSQL's Pod and verify the same database
contents to exercise persistence; never delete its PVC for this check.

Initial app requests total 600m CPU / 1088Mi memory. Measure ONNX startup and
inference and include monitoring, Argo CD and system Pods in capacity checks.
The current startup/readiness probe checks `/v3/api-docs`, not dependency health.
All application Services remain ClusterIP; no public load balancer is created.

Rollback by reverting the GitOps commit to a previously verified image digest
and compatible model/config, then let Argo CD reconcile. Check Flyway backward
compatibility first. Rollback does not undo database migrations or search-store
writes. Keep PVCs and pin dependency images before changing them.
