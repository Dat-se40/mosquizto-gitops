# Mosquizto GitOps

Kubernetes manifests và Kustomize cho backend Mosquizto của đồ án NT548.

- [Cấu trúc base, mạng và cách cấp cấu hình](base/README.md).
- [Chạy trên Minikube, kiểm tra API và xử lý lỗi](overlays/local/README.md).
- [Triển khai EKS qua Argo CD, ECR và ONNX trong image](overlays/eks/README.md).
- [Hướng dẫn vận hành EKS lab và kết quả nghiệm thu](docs/VAN_HANH_EKS_LAB.md).
- [Tài liệu và tiến độ](docs/README.md).
- [Khởi động, dừng và gỡ môi trường local](overlays/local/README.md#9-khởi-động-dừng-và-gỡ-môi-trường-local).
- [Source backend và Dockerfile](https://github.com/Dat-se40/mosquizto-backend).

```text
base/
  kustomization.yaml
  mosquizto-deployment.yaml
  mosquizto-service.yaml
  mosquizto-config.yaml
  postgres.yaml
  .secret.env.example
  README.md
dependencies/
  kustomization.yaml
  redis.yaml
  meilisearch.yaml
  qdrant.yaml
overlays/local/
  kustomization.yaml
  namespace.yaml
  image.yaml
  mosquizto-config.yaml
  .local.secret.env.example
  README.md
overlays/eks/
  kustomization.yaml
  backend.yaml
  config.yaml
  model-config.yaml
bootstrap/eks/
  namespace.yaml
  project.yaml
  application.yaml
```

## Phạm vi hiện tại

Overlay `local` chạy backend, PostgreSQL, Redis, Meilisearch và Qdrant trong namespace `mosquizto-local`. PostgreSQL ở base; Redis và hai search services được thêm bởi overlay local.

Kiểm tra thủ công trên Minikube ngày 28–29/10/2026 đã xác nhận cả năm Deployment Ready, Swagger/OpenAPI trả HTTP 200, đăng nhập bằng tài khoản seed thành công qua Postman và username không tồn tại trả HTTP 401. Chưa kiểm thử toàn bộ CRUD, search, embedding hoặc các dịch vụ mail/media bên ngoài.

Overlay `eks` dùng namespace `mosquizto-eks`, bốn dependency trong cluster với PVC gp3, backend một replica và model ONNX trong image ECR pin bằng digest. Secret EKS được cấp riêng ngoài Git. Bootstrap review chọn nhánh `eks-argocd`; bootstrap mặc định chọn `main` và chỉ dùng khi nhánh đó đã có overlay được duyệt. Đã nghiệm thu sync/self-heal, API, ONNX, giữ dữ liệu và truy cập backend qua Load Balancer trong phiên 04/11/2026; xem [hướng dẫn vận hành](docs/VAN_HANH_EKS_LAB.md) để kiểm tra lại khi mở Lab. Jenkins tự động cập nhật GitOps và demo pipeline end-to-end chưa nghiệm thu.

## Bắt đầu

Đọc [hướng dẫn local](overlays/local/README.md), tạo hai file env riêng từ các file `.example`, điền giá trị hợp lệ, chạy `operations/local/Update-RuntimeEnv.ps1` rồi render overlay. Các file ví dụ chỉ chứa placeholder; các giá trị riêng thật không được commit. Base không đọc env file hay tạo Secret.

Luôn chọn overlay khi triển khai. Base là phần cấu hình tái sử dụng, chưa phải môi trường triển khai độc lập.
