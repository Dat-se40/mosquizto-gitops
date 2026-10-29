# ONNX trên PVC và Job đồng bộ thủ công ở local

[Về trang chính](../../README.md) · [Hướng dẫn Minikube](../local/README.md) · [ONNX và CLI trong backend](../../../mosquizto-backend/ONNX_SYNC.md)

Overlay tùy chọn này kế thừa `../local`, bổ sung PVC 1Gi lưu model, ConfigMap pin revision/checksum và mount chỉ đọc cho backend. Overlay local hiện có được giữ nguyên. Cần dùng image backend mới hỗ trợ hai chế độ `--prepare-model` và `--sync`.

## 1. Chuẩn bị image và manifests

Chạy từ thư mục gốc `mosquizto-gitops`, sau khi đã cấu hình các file env riêng theo [README local](../local/README.md):

```powershell
docker build -t mosquizto-backend:local-sync-002 ../mosquizto-backend
minikube -p minikube image load mosquizto-backend:local-sync-002
kubectl kustomize ./overlays/local-onnx | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Render failed' }
kubectl --context=minikube apply --dry-run=server -k ./overlays/local-onnx
if ($LASTEXITCODE -ne 0) { throw 'Server validation failed' }
kubectl --context=minikube apply -k ./overlays/local-onnx
```

Tag trên là tên image cần build ở local, chưa phải xác nhận image đã được publish lên registry. Backend giữ một replica. Chiến lược Recreate tránh các Pod backend cũ/mới chạy chồng trong lúc rollout với volume RWO của môi trường thử nghiệm này; đổi lại, rollout có thời gian gián đoạn. API có thể khởi động khi embedding chưa sẵn sàng; bước tiếp theo sẽ nạp model vào PVC.

## 2. Nạp model vào PVC

```powershell
./operations/local/Start-Operation.ps1 -Operation prepare-model
```

Script in tên Job riêng cho lần chạy cùng các lệnh xem log/trạng thái. Chờ Job hoàn thành và kiểm tra log trước khi tiếp tục. Nếu revision đã có và checksum hợp lệ, command dùng lại các file đó, không tải lại. Bước này không cần credentials của database, JWT hay SMTP.

Revision và SHA-256 trong ConfigMap là thông tin công khai để xác định phiên bản và kiểm tra nội dung model/tokenizer; chúng không phải mật khẩu hay token. Khi đổi model, cần cập nhật revision và checksum kỳ vọng cùng nhau, lấy từ nguồn tin cậy.

Sau khi nạp xong, restart backend vì lần khởi tạo model trước đó có thể đã diễn ra khi PVC còn trống:

```powershell
kubectl --context=minikube -n mosquizto-local rollout restart deployment/mosquizto-backend-deployemnt
kubectl --context=minikube -n mosquizto-local rollout status deployment/mosquizto-backend-deployemnt --timeout=360s
```

Kiểm tra log `Embedding ready`; HTTP readiness chưa chứng minh ONNX đã được nạp. Đo mức sử dụng bộ nhớ cao nhất lúc startup và khi chạy inference/sync nhiều lần trước khi điều chỉnh limits.

## 3. Cấp credentials cần thiết cho CLI

Trong môi trường local, tạo hoặc cập nhật Secret riêng cho sync từ file env của base đã có:

```powershell
./operations/local/Set-SyncSecret.ps1
```

Script chỉ đọc `DB_PASSWORD` và `MEILI_MASTER_KEY`, truyền cho kubectl qua stdin; không in giá trị và không đưa chúng vào arguments của tiến trình. Namespace phải tồn tại trước khi chạy. Không commit file env thật hoặc Secret đã render.

Script này phục vụ việc cấp Secret ở local. Khi triển khai EKS, Secret mà Job tham chiếu phải được cung cấp qua cơ chế quản lý runtime secrets đã được nhóm thống nhất.

## 4. Chạy dry-run trước khi ghi dữ liệu

Chọn một trong các lệnh sau theo phạm vi cần kiểm tra:

```powershell
./operations/local/Start-Operation.ps1 -Operation sync -Target all
./operations/local/Start-Operation.ps1 -Operation sync -Target meilisearch
./operations/local/Start-Operation.ps1 -Operation sync -Target qdrant
```

Chờ và kiểm tra từng lần chạy; không chạy đồng thời các ví dụ trên. Mặc định là dry-run. Với Qdrant, dry-run kiểm tra embedding thật nhưng chưa chứng minh credentials có quyền ghi lên service.

Sau khi xem kết quả dry-run, thêm `-Write` để thực sự ghi dữ liệu:

```powershell
./operations/local/Start-Operation.ps1 -Operation sync -Target all -Write
```

Dùng `-Cleanup preview` để kiểm tra các document/point mồ côi, tức những bản ghi trong derived stores không còn bản ghi PostgreSQL hợp lệ tương ứng. Muốn xóa thật, cần đủ `-Write -Cleanup delete -MaintenanceConfirmed` **sau khi đã dừng các tác vụ ghi dữ liệu của ứng dụng**. Cờ xác nhận không tự dừng các tác vụ đó. Các lệnh trong hướng dẫn này không xóa PVC hoặc Namespace.

Mỗi lần kích hoạt có tên Job riêng. PostgreSQL advisory lock từ chối các lượt sync chạy chồng nhau. Nếu Job thất bại, đọc báo cáo JSON rồi chủ động tạo lượt chạy mới. Các template đặt `backoffLimit: 0`, có giới hạn thời gian chạy và TTL 24 giờ; lưu log cần thiết trước khi Job được dọn theo TTL. Job dry-run hoàn thành không có nghĩa dữ liệu đã được ghi: kiểm tra trường `dryRun` trong báo cáo.

Thư mục `operations` không nằm trong Kustomization của workload. Không có Argo CD hook, CronJob hoặc cơ chế tự chạy lại Job theo mỗi lần sync thông thường. Không cấu hình Argo CD theo dõi trực tiếp các template thao tác này.

## 5. Rollback và những điểm cần chốt trước EKS

Khôi phục image **tương thích** cùng revision/checksum model tương ứng, giữ các thư mục model cũ và restart các tiến trình sử dụng model. Nếu quay về image cũ dùng classpath loader, cần khôi phục cả manifests tương ứng. Rollback YAML workload không khôi phục dữ liệu đã ghi vào Meilisearch/Qdrant.

PVC này dùng StorageClass mặc định của Minikube và RWO trên một node. Không mặc định backend và Sync Job nằm trên hai node EKS khác nhau có thể dùng chung volume đó. CSI/StorageClass, RWX nếu cần, backup/restore, quyền truy cập, người phụ trách và chi phí vẫn cần nhóm thống nhất trước production. Các file này không tạo tài nguyên AWS.

Volume chỉ chia sẻ file model; mỗi tiến trình vẫn có ONNX session và bộ nhớ inference riêng. Giới hạn bộ nhớ 1Gi của backend/Sync Job là giá trị thử nghiệm local, cần đo lại trước production. Cách truy cập URL qua port-forward hiện có được giữ nguyên; các Service của dependency tiếp tục phục vụ nội bộ cluster.

## 6. Kết quả kiểm chứng local ngày 29/10/2026

Đã chạy trên Minikube Docker driver, Kubernetes v1.37.0, một node và image `mosquizto-backend:local-sync-002`:

- Build/load image, server dry-run và apply overlay thành công. Cả năm Deployment `1/1 Ready`; năm PVC `Bound`, gồm bốn PVC dữ liệu cũ và PVC model mới.
- Job nạp model hoàn thành; backend và CLI trong Linux container đều ghi log `Embedding ready`, đúng revision và 384 chiều.
- Swagger/OpenAPI trả HTTP 200; OpenAPI dùng `http://localhost:18080/`. Login bằng tài khoản không tồn tại và gọi sync không có token đều trả HTTP 401.
- CLI dry-run đọc 38 collections và tính embedding thành công. Hai lượt sync ghi thật liên tiếp đều báo 38 thành công, 0 lỗi cho từng store; không bật cleanup.
- Kiểm tra trực tiếp sau hai lượt: Meilisearch có 38 documents, không còn indexing; Qdrant có 38 points, trạng thái `green`, schema 384 chiều/Cosine. Vector mẫu có các phần tử hữu hạn, norm bằng 1 và khác vector 0.
- Request search trực tiếp tới Meilisearch trả ba ID mẫu, tổng số hits ước tính là 38. Chưa kiểm thử search/recommendation qua API bằng tài khoản đăng nhập hợp lệ trong lượt này.

Lượt dry-run đầu tiên đã phát hiện lỗi Hibernate deserialize kết quả `MAX(id)` trên ID generic. Backend đã đổi truy vấn này sang native scalar SQL và thêm regression assertion; image `local-sync-002` chứa bản sửa. Job thất bại cũ được giữ lại để đối chiếu log, không phải trạng thái của các lượt chạy sau bản sửa.

Các kết quả trên chưa chứng minh cleanup/xóa hoặc soft-delete, khả năng chịu lỗi khi store mất kết nối trên cluster, load test, nhiều replicas hay sizing production. Các trường hợp đó vẫn cần bài kiểm thử riêng.
