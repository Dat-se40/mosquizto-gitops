# Mosquizto GitOps

Kubernetes manifests và Kustomize cho backend Mosquizto của đồ án NT548.

- [Cấu trúc base, mạng và cách cấp cấu hình](base/README.md).
- [Chạy trên Minikube, kiểm tra API và xử lý lỗi](overlays/local/README.md).
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
overlays/local/
  kustomization.yaml
  namespace.yaml
  image.yaml
  mosquizto-config.yaml
  redis.yaml
  meilisearch.yaml
  qdrant.yaml
  .local.secret.env.example
  README.md
```

## Phạm vi hiện tại

Overlay `local` chạy backend, PostgreSQL, Redis, Meilisearch và Qdrant trong namespace `mosquizto-local`. PostgreSQL ở base; Redis và hai search services được thêm bởi overlay local.

Các phiên kiểm tra ngày 28–29/10/2026 đã xác nhận cả năm Deployment Ready, Swagger/OpenAPI trả HTTP 200 và đăng nhập bằng username kiểm thử không tồn tại trả HTTP 401. Người dùng cũng đã xác nhận đăng nhập thành công bằng tài khoản seed qua Postman. Đây không phải kết quả kiểm thử toàn bộ CRUD, search, embedding hoặc các dịch vụ mail/media bên ngoài.

Repo hiện chưa có overlay EKS hay Argo CD Application. Registry/image tag, nơi chạy database trên EKS, secrets management và ownership add-on vẫn cần chốt với nhóm. Flow tích hợp dự kiến là Jenkins cập nhật image reference trong repo này, Argo CD reconcile lên cluster.

## Bắt đầu

Đọc [hướng dẫn local](overlays/local/README.md), tạo hai file env riêng từ các file `.example`, điền giá trị hợp lệ rồi render overlay. Các file ví dụ chỉ chứa placeholder; các giá trị riêng thật không được commit.

Luôn chọn overlay khi triển khai. Base là phần cấu hình tái sử dụng, chưa phải môi trường triển khai độc lập.
