# Triển khai Mosquizto trên EKS cho môi trường lab

Các lệnh PowerShell bên dưới chạy từ **thư mục gốc `mosquizto-gitops`**. Cần cấu hình AWS credentials cho đúng tài khoản và luôn truyền rõ context EKS. Năm dịch vụ chạy trong namespace `mosquizto-eks`; database mới được khởi tạo bằng các migration Flyway hiện có. Backend hiện có Service LoadBalancer public; Jenkins CI tự động chưa nghiệm thu. Khi mở lại môi trường đã cài, làm theo [hướng dẫn vận hành EKS lab](../../docs/VAN_HANH_EKS_LAB.md) trước, không cài lại toàn bộ theo các bước bên dưới.

## 1. Điều kiện trước khi triển khai

- Hai worker `Ready`, CoreDNS/CNI hoạt động và DNS trong cluster phân giải được.
- Có EBS CSI và StorageClass `mosquizto-gp3`, được cài bằng bộ công cụ `kubernetes/storage` trong repo infra. Phải kiểm tra được ghi dữ liệu vào PVC, tạo lại Pod và đọc lại dữ liệu trước khi triển khai ứng dụng.
- Backend được build từ commit nguồn đã ghi nhận, nền tảng Linux amd64, với `INCLUDE_EMBEDDING_MODEL=true`; kiểm tra SHA-256 model/tokenizer và chạy bằng UID 10001.
- Image nằm trong ECR private với tag bất biến. Trường `images` của overlay phải chứa digest đã xác minh; backend và Sync Job dùng cùng digest này.

## 2. Cấp Secret riêng ngoài Git và Argo CD

Copy `base/.secret.env.example` thành `overlays/eks/.secret.env`, điền cấu hình tích hợp hợp lệ và tạo mới mật khẩu DB, khóa JWT, khóa Meilisearch cho EKS. Sau khi PostgreSQL đã khởi tạo, đổi mật khẩu trong Secret phải đi kèm đổi mật khẩu trong PostgreSQL. Không in hoặc commit file env thật hay Secret đã render.

```powershell
kubectl --context=mosquizto-eks apply -f bootstrap/eks/namespace.yaml
./operations/eks/Set-RuntimeSecrets.ps1 -Context mosquizto-eks
```

Script kiểm tra các key bắt buộc rồi truyền qua stdin để cấp `mosquizto-secret` và Secret nhỏ hơn `mosquizto-sync-secret`. Argo CD không quản lý hai Secret này. Khi chủ động thay đổi Secret runtime, cần restart backend để nhận biến môi trường mới.

Backend hiện nhận ConfigMap qua biến môi trường. Vì vậy, khi push thay đổi như `SERVER_URL` trong `config.yaml`, Argo CD cập nhật ConfigMap nhưng Pod đang chạy vẫn giữ giá trị cũ. Sau khi Application đã sync đúng commit, rollout backend và kiểm tra lại:

```powershell
kubectl --context=mosquizto-eks -n mosquizto-eks rollout restart deployment/mosquizto-backend-deployemnt
kubectl --context=mosquizto-eks -n mosquizto-eks rollout status deployment/mosquizto-backend-deployemnt --timeout=360s
kubectl --context=mosquizto-eks -n mosquizto-eks exec deployment/mosquizto-backend-deployemnt -- printenv SERVER_URL
```

`SERVER_URL` cần là URL public có dấu `/` cuối nếu muốn link xác nhận email dùng địa chỉ public. Email đã gửi trước khi rollout vẫn giữ link được tạo lúc đó; restart ứng dụng không sửa nội dung email cũ.

## 3. Kiểm tra YAML và cài Argo CD

```powershell
cd D:\uselessTool\DevOps\NT548\mosquizto-gitops
kubectl kustomize overlays/eks | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Không render được overlay' }
kubectl --context=mosquizto-eks apply --dry-run=server -k overlays/eks
if ($LASTEXITCODE -ne 0) { throw 'Kiểm tra phía server thất bại' }
./bootstrap/Install-ArgoCD.ps1 -Context mosquizto-eks
```

Dry-run chỉ kiểm tra YAML, chưa tạo workload. Các file có trên máy local cũng chưa chắc đã có trên nhánh Git mà Argo CD đang đọc. Cần chọn đúng nguồn Git ở bước tiếp theo rồi sync qua Argo CD.

## 4. Triển khai thử từ nhánh review hiện tại

Khi PR chưa được merge, dùng bootstrap sau để Application đọc nhánh `eks-argocd`; `main` được giữ nguyên:

```powershell
kubectl --context=mosquizto-eks apply -k bootstrap/eks-review
kubectl --context=mosquizto-eks -n argocd get application mosquizto-eks
```

Đợi Application hết lỗi sinh manifest và chuyển sang `OutOfSync`. Bootstrap này dùng chế độ sync thủ công, nên chỉ tạo Application chưa làm xuất hiện Deployment/Service của ứng dụng. Yêu cầu Argo CD sync bằng:

```powershell
kubectl --context=mosquizto-eks -n argocd patch application mosquizto-eks --type=merge --patch-file operations/eks/sync-application.yaml
```

Kiểm tra `status.operationState` của Application để biết thành công hoặc lỗi rồi kiểm tra rollout. AppProject chỉ cho phép repo này, namespace ứng dụng và các loại Deployment, Service, ConfigMap, PVC. Namespace, Secret, storage và bản thân Argo CD được chuẩn bị riêng.

Muốn mở giao diện Argo CD, giữ lệnh sau chạy trong một terminal riêng rồi truy cập `https://localhost:18443`:

```powershell
kubectl --context=mosquizto-eks -n argocd port-forward service/argocd-server 18443:443
```

Sau lần sync thủ công và kiểm thử thành công, bật tự động đồng bộ và tự sửa drift cho nhánh review:

```powershell
kubectl --context=mosquizto-eks apply -k bootstrap/eks-review-selfheal
```

Nguồn Git vẫn là `eks-argocd`, `selfHeal=true`, `prune=false`. Áp dụng lại `bootstrap/eks-review` sẽ quay về sync thủ công. Các PVC có thêm `Prune=false,Delete=false`; Application không có finalizer xóa tài nguyên theo dây chuyền. Không đưa các Job thao tác thủ công vào đường dẫn Application hoặc đăng ký chúng làm Argo CD hook.

**Chỉ sau khi overlay đã được merge vào `main`**, mới dùng:

```powershell
kubectl --context=mosquizto-eks apply -k bootstrap/eks
```

Lệnh này chọn lại `main` và chế độ sync thủ công. Nếu nhánh đó chưa có `overlays/eks`, Argo CD sẽ báo `app path does not exist`.

## 5. Kiểm tra ứng dụng và ONNX

```powershell
kubectl --context=mosquizto-eks -n mosquizto-eks get deploy,pods,svc,pvc
kubectl --context=mosquizto-eks -n mosquizto-eks rollout status deployment/mosquizto-backend-deployemnt --timeout=360s
kubectl --context=mosquizto-eks -n mosquizto-eks port-forward service/mosquizto-service 18080:8080
```

Giữ terminal port-forward mở. Truy cập `/swagger-ui/index.html` và `/v3/api-docs` tại `http://localhost:18080`. Kiểm tra đăng nhập hợp lệ thành công và thông tin sai trả HTTP 401. Log backend cần có `Embedding ready`; HTTP readiness chưa chứng minh được ONNX suy luận thành công.

```powershell
./operations/eks/Start-Sync.ps1 -Context mosquizto-eks
# Chỉ chạy ghi thật sau khi đã xem kết quả Job dry-run:
./operations/eks/Start-Sync.ps1 -Context mosquizto-eks -Write
```

Dùng tên Job mà script in ra để xem `kubectl logs` và `kubectl wait`. Script từ chối khi digest của overlay khác image backend đang chạy. Job dùng model trong image, Secret riêng và không dùng PVC model. Mặc định là dry-run, không dọn/xóa dữ liệu mồ côi. Sau lượt ghi thật, đối chiếu số collection/document/point và kiểm tra vector Qdrant có 384 phần tử hữu hạn, đã chuẩn hóa.

## 6. Dữ liệu, tài nguyên và quay lui

PVC PostgreSQL 2Gi; Redis, Meilisearch và Qdrant mỗi dịch vụ 1Gi, kiểu RWO. Mỗi dependency có một replica và chiến lược `Recreate`. Đây chưa phải cấu hình HA hoặc cơ chế backup. Chính sách `Retain` giữ lại volume có tính phí sau khi PVC bị xóa, cần người quản lý chủ động khôi phục hoặc dọn. Khi kiểm tra persistence, chỉ tạo lại Pod PostgreSQL rồi so sánh dữ liệu; giữ nguyên PVC.

Tổng requests khởi đầu của năm dịch vụ là 600m CPU và 1088Mi RAM. Cần đo lúc ONNX khởi tạo/suy luận và tính thêm monitoring, Argo CD, Pod hệ thống khi đánh giá tài nguyên. Probe startup/readiness hiện kiểm tra `/v3/api-docs`, chưa đánh giá đầy đủ dependency. Service backend được patch thành LoadBalancer public bởi `public-service.yaml`; các dependency giữ ClusterIP. Lấy lại hostname sau khi mở Lab và kiểm tra `SERVER_URL` theo hướng dẫn vận hành.

Quay lui bằng cách revert commit GitOps về image digest và cấu hình/model tương thích đã được kiểm chứng, rồi để Argo CD reconcile. Kiểm tra khả năng tương thích ngược của Flyway trước. Quay lui workload không hoàn tác migration database hoặc dữ liệu đã ghi vào search store. Giữ PVC và pin phiên bản image dependency trước khi nâng cấp.
