# Hướng dẫn vận hành Mosquizto trên EKS lab

**Cập nhật:** 05/11/2026. Tài liệu hợp nhất hướng dẫn mở lại AWS Lab và bàn giao nghiệm thu ngày 04/11/2026.

Dùng để mở lại môi trường đã triển khai, kiểm tra và xử lý lỗi đến khi truy cập được ứng dụng. Kết quả nghiệm thu cũ nằm ở phần 12, không thay cho kiểm tra trạng thái mỗi phiên. Tài liệu này chỉ chứa hướng dẫn; các lệnh AWS/Kubernetes thay đổi tài nguyên chỉ có hiệu lực khi người vận hành chủ động chạy.

Các ví dụ dùng Windows tại `D:\uselessTool\DevOps\NT548`, ba repo backend/gitops/infra đặt cạnh nhau và Ubuntu WSL. Nếu dùng máy khác, thay đường dẫn gốc, đường dẫn công cụ và SSH key bằng cấu hình thực tế. Công cụ trong `.tools` và cache Minikube không nằm trong repo GitOps; cần cài sẵn trước khi dùng các lệnh bên dưới.

- **Windows/WSL:** máy điều khiển để chạy AWS CLI, kubectl, Terraform và Ansible. Mở WSL chưa phải SSH vào EC2.
- **EC2:** chạy Jenkins/Docker; Ansible từ WSL tự SSH tới EC2 khi chạy playbook Jenkins.
- **EKS:** chạy Argo CD, Mosquizto và monitoring. Playbook monitoring gọi Helm/kubectl trên máy điều khiển, không cài stack lên EC2 Jenkins.
- **GitOps:** Argo CD đọc `mosquizto-gitops`, nhánh review `eks-argocd`, đường dẫn `overlays/eks`, rồi đồng bộ vào namespace `mosquizto-eks` trong cùng cluster. Giữ nguyên `main` tới khi được duyệt; không dùng Jenkins apply workload trực tiếp.

Các khối `powershell` chạy trên Windows, các khối `bash` chạy trong WSL trừ khi ghi rõ trên worker. Lệnh `port-forward` mở cổng tại máy đang chạy nó; nếu chạy trong phiên SSH trên EC2 thì cần thêm SSH tunnel để mở UI từ máy cá nhân.

**Cách dùng:** mở lại bình thường làm phần 1–9; lỗi không có Node xem phần 2.1–2.3; chỉ dùng phần 10 khi thành phần thực sự mất. Phần Terraform/Ansible/add-on giữ theo trách nhiệm Tuấn/Phong, Jenkins CI phối hợp Huy.

## Mục lục

- [0. Hiểu trạng thái sau End Lab](#buoc-0)
- [1. Credentials và PowerShell](#buoc-1)
- [2. EKS và khôi phục worker](#buoc-2)
- [3. IP Internet và Security Group](#buoc-3)
- [4. IP Jenkins và inventory](#buoc-4)
- [5. WSL, Ansible và Jenkins](#buoc-5)
- [6. DNS, storage, Argo CD và ứng dụng](#buoc-6)
- [7. URL public và SERVER_URL/email](#buoc-7)
- [8. Mở Argo CD, Prometheus, Grafana](#buoc-8)
- [9. Kiểm tra cuối phiên khởi động](#buoc-9)
- [10. Khôi phục thành phần bị mất](#buoc-10)
- [11. Kết thúc phiên](#buoc-11)
- [12. Kết quả nghiệm thu đã ghi nhận](#buoc-12)
- [Nguồn đối chiếu](#nguon-doi-chieu)

<a id="buoc-0"></a>

## 0. Hiểu trạng thái sau End Lab

Ví dụ đã ghi nhận sau End Lab (không phải kết quả kiểm tra trực tiếp ở lần đọc tài liệu này):

```text
aws sts get-caller-identity       → thành công
kubectl get nodes                → No resources found
kubectl get pods -A              → Pod còn nhưng đều Pending, READY 0
```

Trong ví dụ trên, credentials vẫn được AWS chấp nhận và API Kubernetes vẫn trả lời. Cluster đang không có đối tượng Node; Pod là yêu cầu chạy còn lưu trong cluster, chưa có worker để thực thi. Chưa thể kết luận worker đang tắt, bị thay thế hay bootstrap lỗi nếu chưa kiểm tra AWS. STS thành công không chứng minh Lab đang chạy hoặc EC2 đã bật.

Sau mỗi phiên, phân biệt các địa chỉ:

- **IP Internet của bạn:** dùng cho rule Security Group `/32`; lấy từ đúng Windows/WSL đang kết nối.
- **Public IP của EC2 Jenkins:** có thể đổi sau stop/start; cập nhật `hosts.ini` và URL Jenkins.
- **IP Node/Pod:** có thể đổi; không điền chúng vào URL backend hay inventory Jenkins.
- **DNS Load Balancer:** lấy lại bằng `kubectl get svc`. IP phía sau DNS có thể đổi; dùng hostname. Nếu vẫn cùng Load Balancer, không cần sửa `SERVER_URL` chỉ vì worker đổi IP. Nếu Load Balancer bị tạo lại, DNS cũng có thể khác.

Luồng mỗi phiên: **Start Lab → credentials → kiểm tra EKS/worker → cập nhật IP Jenkins và quyền truy cập nếu cần → chờ workload phục hồi → kiểm tra URL backend/email → mở Jenkins, Argo CD, Prometheus, Grafana**.

<a id="buoc-1"></a>

## 1. Start Lab, cập nhật credentials và mở PowerShell

Trong AWS Academy, bấm **Start Lab**, chờ trạng thái sẵn sàng rồi lấy bộ credentials hiện tại trong **AWS Details → AWS CLI**. End Lab và Start Lab có thể tác động tài nguyên theo chính sách Lab; luôn kiểm tra trạng thái thực tế.

Mở file credentials riêng:

```powershell
notepad 'D:\uselessTool\DevOps\NT548\mosquizto-infra\.aws\credentials'
```

Thay đủ ba giá trị trong profile `[default]`: `aws_access_key_id`, `aws_secret_access_key`, `aws_session_token`. Không đưa nội dung file vào Git hoặc chat.

Trong **mỗi PowerShell mới** dùng để chạy lệnh, nạp khối này:

```powershell
$labRoot = 'D:\uselessTool\DevOps\NT548'
$env:Path = "$labRoot\.tools\terraform;D:\AWS;C:\Users\hp\.minikube\cache\windows\amd64\v1.37.0;" + $env:Path
$env:AWS_SHARED_CREDENTIALS_FILE = "$labRoot\mosquizto-infra\.aws\credentials"
$env:AWS_PROFILE = 'default'
$env:AWS_DEFAULT_REGION = 'us-east-1'
$env:AWS_EC2_METADATA_DISABLED = 'true'
$env:AWS_PAGER = ''
$env:KUBECONFIG = "$labRoot\mosquizto-infra\.aws\eks-kubeconfig"
$OutputEncoding = [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
# Tránh lỗi HTTP/2 từng gặp với kubectl trên máy này.
$env:GODEBUG = 'http2client=0'

# Bỏ bộ key cũ trong môi trường để CLI dùng đúng file vừa cập nhật.
Remove-Item Env:\AWS_ACCESS_KEY_ID, Env:\AWS_SECRET_ACCESS_KEY, Env:\AWS_SESSION_TOKEN, Env:\AWS_SECURITY_TOKEN -ErrorAction SilentlyContinue

Set-Location "$labRoot\mosquizto-infra\terraform"
Get-Command aws, terraform, kubectl | Select-Object Name, Source
aws sts get-caller-identity
if ($LASTEXITCODE -ne 0) { throw 'Sửa credentials trước khi tiếp tục' }
```

Account đã dùng cho môi trường này là `821278618825`, region `us-east-1`. Nếu đang dùng account khác, dừng để xác định đúng môi trường; không apply state cũ sang account khác. Các đường dẫn công cụ trên là của máy hiện tại, cần điều chỉnh nếu chuyển máy.

<a id="buoc-2"></a>

## 2. Kết nối đúng EKS và kiểm tra worker trước

```powershell
$clusterName = 'project11-eks-cluster'
$nodegroupName = 'project11-eks-cluster-node-group'

aws eks describe-cluster --name $clusterName --query 'cluster.{Name:name,Status:status,Version:version}' --output json
if ($LASTEXITCODE -ne 0) { throw 'Chưa đọc được cluster; kiểm tra account, region, quyền và Lab' }

aws eks update-kubeconfig --name $clusterName --region us-east-1 --alias mosquizto-eks --kubeconfig $env:KUBECONFIG
if ($LASTEXITCODE -ne 0) { throw 'Không cập nhật được kubeconfig' }
kubectl --context=mosquizto-eks get nodes -o wide --request-timeout=20s
kubectl --context=mosquizto-eks get pods -A --request-timeout=20s
```

Nếu đã có **hai Node Ready**, sang phần 3. Nếu `No resources found`, làm phần 2.1–2.3. Nếu `Unauthorized`/`Forbidden`, kiểm tra credentials và quyền EKS/RBAC; đó là nhánh lỗi khác với không có Node. Nếu cluster không tồn tại, xem phần 10; không tự xóa state rồi dựng lại.

### 2.1. Lấy đúng nodegroup, Auto Scaling Group và instance hiện tại

```powershell
aws eks list-nodegroups --cluster-name $clusterName --output table
$nodegroupRaw = aws eks describe-nodegroup --cluster-name $clusterName --nodegroup-name $nodegroupName --output json
if ($LASTEXITCODE -ne 0) { throw 'Không đọc được nodegroup; kiểm tra tên/trạng thái trước' }
$nodegroup = ($nodegroupRaw -join "`n" | ConvertFrom-Json).nodegroup
$nodegroup | Select-Object nodegroupName, status, scalingConfig, health | ConvertTo-Json -Depth 8

$asgNames = @($nodegroup.resources.autoScalingGroups | ForEach-Object { $_.name })
if ($asgNames.Count -eq 0) { throw 'Nodegroup chưa có Auto Scaling Group; cần kiểm tra với Tuấn' }
$asgRaw = aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $asgNames --output json
if ($LASTEXITCODE -ne 0) { throw 'Không đọc được Auto Scaling Group' }
$asgGroups = @(($asgRaw -join "`n" | ConvertFrom-Json).AutoScalingGroups)
$asgGroups | Select-Object AutoScalingGroupName, MinSize, MaxSize, DesiredCapacity
$asgGroups.Instances | Select-Object InstanceId, LifecycleState, HealthStatus

$workerIds = @($asgGroups.Instances | ForEach-Object { $_.InstanceId })
if ($workerIds.Count -gt 0) {
    aws ec2 describe-instances --instance-ids $workerIds --query 'Reservations[].Instances[].{ID:InstanceId,State:State.Name,PrivateIP:PrivateIpAddress,PublicIP:PublicIpAddress}' --output table
    aws ec2 describe-instance-status --include-all-instances --instance-ids $workerIds --query 'InstanceStatuses[].{ID:InstanceId,State:InstanceState.Name,System:SystemStatus.Status,Instance:InstanceStatus.Status}' --output table
}
```

Mã Terraform hiện khai báo `desired_size=2`, `min_size=1`, `max_size=3`. Tuy nhiên `ACTIVE`, `InService`, EC2 `running` hoặc status check đạt **chưa chứng minh Node đã join Kubernetes**.

### 2.2. Chọn cách phục hồi theo kết quả

**Worker đang pending/initializing:** theo dõi EC2 và `kubectl get nodes -w`, dùng `Ctrl+C` để thoát. Nếu khoảng 10–15 phút vẫn không có Node, lấy log theo phần 2.3 thay vì chờ vô hạn.

**Worker đang stopped:** xác nhận Start Lab đã hoàn tất. Nếu Lab chưa tự bật lại, phối hợp Tuấn kiểm tra các instance còn thuộc ASG hiện tại và ASG có đang thay máy không. Chỉ khi đã xác nhận giữ lại những worker đó mới bật lại; không dùng ID của phiên cũ. Có thể dùng EC2 Console → đúng các instance đã đối chiếu → Start instance. Không lấy việc Stop/Start từng worker làm quy trình quản lý nodegroup hằng ngày.

**ASG không có máy hoặc desired capacity bị giảm:** đưa kết quả cho Tuấn khôi phục số lượng theo cấu hình nodegroup. Nếu hai người thống nhất sửa qua Terraform và state còn đúng, có thể xem trước phạm vi nodegroup:

```powershell
terraform plan '-target=module.eks.aws_eks_node_group.nodes' '-out=restore-nodegroup.tfplan'
if ($LASTEXITCODE -ne 0) { throw 'Lập plan nodegroup thất bại' }
terraform show -no-color restore-nodegroup.tfplan
```

Chỉ khi bản plan đúng thay đổi đã thống nhất, không thay VPC/cluster/Jenkins hoặc xóa/thay nodegroup ngoài dự kiến, mới chạy:

```powershell
terraform apply restore-nodegroup.tfplan
```

Lệnh trên thay đổi AWS và có thể cấp EC2 tính phí. Đây là sửa chữa có phạm vi, không phải bước bắt buộc mỗi lần mở Lab. Nếu desired đã bằng 2 nhưng worker vẫn không join, apply lại cùng cấu hình không sửa được bootstrap.

**Worker running, status check đạt, vẫn không có Node:** sang phần 2.3. Không restart các Deployment hoặc cài lại Argo CD để chữa lỗi worker.

### 2.3. Kiểm tra lỗi bootstrap, đặc biệt lỗi SCP đã từng gặp

Lấy console log của **từng worker hiện tại**, lưu riêng ngoài Git:

```powershell
$logDir = Join-Path $labRoot ('.tools\lab-diagnostics\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
foreach ($workerId in $workerIds) {
    $consoleRaw = aws ec2 get-console-output --instance-id $workerId --latest --output json
    if ($LASTEXITCODE -ne 0) { Write-Warning "Không lấy được console log: $workerId"; continue }
    $console = $consoleRaw -join "`n" | ConvertFrom-Json
    $logFile = Join-Path $logDir "$workerId.txt"
    $console.Output | Set-Content -LiteralPath $logFile -Encoding UTF8
    Write-Output "Instance: $workerId; Console timestamp: $($console.Timestamp); File: $logFile"
    Select-String -LiteralPath $logFile -Pattern 'nodeadm|DescribeInstances|AccessDenied|UnauthorizedOperation|explicit deny|service control policy' | Select-Object -Last 20
}
```

Console log có thể chưa đầy đủ hoặc chưa mới. Đối chiếu timestamp trong log với lần khởi động hiện tại; không kết luận lỗi còn xảy ra chỉ từ một dòng deny cũ. Nếu có quyền vào worker qua SSM/SSH, Tuấn có thể xem thêm các lệnh chỉ đọc sau trên **worker**, không phải EC2 Jenkins:

```bash
sudo systemctl status nodeadm-config nodeadm-run kubelet --no-pager
sudo journalctl -b -u nodeadm-config -u nodeadm-run -u kubelet --no-pager -n 200
```

Môi trường đã từng gặp `nodeadm` bị deny `ec2:DescribeInstances` bởi SCP:

```text
arn:aws:organizations::616729071712:policy/o-8xngl69ixz/service_control_policy/p-fshgnpgi
```

Đây là **tiền sử lỗi**, không phải kết luận cho mọi lần mở Lab. Nếu log mới có cùng lỗi, gửi Tuấn/phía quản lý Lab: instance ID, cluster/nodegroup, timestamp, action bị deny, role và ARN SCP. Không thêm `AdministratorAccess` để thử vượt SCP. Chỉ sau khi phía Lab xác nhận đã xử lý quyền, phối hợp Tuấn retry bootstrap hoặc thay worker bằng cơ chế nodegroup. Nếu chọn reboot worker để chạy lại các dịch vụ bootstrap lúc boot, đối chiếu lại ID và xem trước phạm vi; không reboot Jenkins hoặc lặp reboot khi deny còn nguyên.

Nếu không phải SCP, tiếp tục kiểm tra theo log: quyền role node, ánh xạ `aws-auth`/access entry phù hợp chế độ cluster, endpoint EKS, route/DNS/Security Group. Không tự sửa quyền/auth bằng cấu hình mẫu chưa đối chiếu.

**Điều kiện qua bước:** thấy đúng hai Node Ready:

```powershell
kubectl --context=mosquizto-eks get nodes
# Chỉ chạy wait sau khi đã thấy các Node xuất hiện.
kubectl --context=mosquizto-eks wait nodes --all --for=condition=Ready --timeout=300s
```

<a id="buoc-3"></a>

## 3. Cập nhật IP Internet và Security Group cho Jenkins nếu cần

Đây là **IP của mạng bạn**, không phải IP EC2. Với PowerShell:

```powershell
$clientIp = (Invoke-RestMethod 'https://checkip.amazonaws.com').Trim()
$clientCidr = "$clientIp/32"
$clientCidr
```

Nếu SSH/Ansible chạy trong WSL, kiểm tra từ WSL nữa:

```bash
curl -4 --noproxy checkip.amazonaws.com https://checkip.amazonaws.com
```

Nếu Windows và WSL ra hai IP khác nhau do VPN/proxy, rule SSH cần IP thực tế của đường kết nối WSL; Jenkins UI cần IP của đường truy cập trình duyệt. Chỉ thêm những IP nhóm thực sự dùng, giữ các CIDR của thành viên khác khi vẫn cần.

```powershell
Set-Location "$labRoot\mosquizto-infra\terraform"
notepad .\terraform.tfvars
```

Sửa hai biến sau bằng IP thật, không dán nguyên mẫu:

```hcl
ALLOWED-SSH-CIDRS     = ["IP_PUBLIC_DUNG_CHO_SSH/32"]
ALLOWED-JENKINS-CIDRS = ["IP_PUBLIC_DUNG_CHO_TRINH_DUYET/32"]
```

Biến thứ hai còn dùng cho rule 3000/9090/9100 của SG Jenkins trong Terraform hiện tại; các rule này không thay thế việc truy cập monitoring đang chạy trên EKS.

Nếu CIDR không đổi và rule đã đúng, bỏ qua apply. Nếu cần sửa, lập plan hẹp cho SG để tránh kéo theo đổi AMI Jenkins:

```powershell
terraform plan '-target=module.security-group.aws_security_group.jenkins_sg' '-out=lab-access.tfplan'
if ($LASTEXITCODE -ne 0) { throw 'Lập plan Security Group thất bại' }
terraform show -no-color lab-access.tfplan
```

Mong đợi chỉ thay rule đã định: thường `0 to add, 1 to change, 0 to destroy`; nếu đã đúng có thể không có thay đổi. Kiểm tra cả các rule khác trước khi áp dụng vì SG là một resource chung. Nếu thấy tạo lại EC2/VPC/EKS, dừng để kiểm tra scope.

Sau khi xem đúng plan:

```powershell
terraform apply lab-access.tfplan
```

Plan đã lưu được áp dụng ngay, không hỏi `yes` lần nữa. Không dùng lại plan từ phiên cũ. `-target` ở đây dành cho sửa quyền truy cập cụ thể; việc thay đổi hạ tầng thường lệ vẫn cần plan tổng và review với Tuấn.

**Không chạy `terraform apply` toàn bộ chỉ để lấy IP mới.** Module EC2 đang dùng `most_recent=true` cho AMI Ubuntu; đã từng có plan đề xuất thay máy Jenkins chỉ vì AMI mới xuất hiện.

<a id="buoc-4"></a>

## 4. Lấy IP Jenkins trực tiếp từ AWS, cập nhật inventory

Vẫn trong PowerShell ở `mosquizto-infra/terraform`:

```powershell
$jenkinsId = (terraform output -raw jenkins_instance_id).Trim()
if ($LASTEXITCODE -ne 0 -or -not $jenkinsId.StartsWith('i-')) { throw 'Chưa lấy được Jenkins ID từ đúng state' }
aws ec2 describe-instances --instance-ids $jenkinsId --query 'Reservations[].Instances[].{ID:InstanceId,State:State.Name,IP:PublicIpAddress,Key:KeyName,SG:SecurityGroups[].GroupId}' --output json
```

Nếu ID đã terminated/không còn tồn tại, dừng để đối chiếu state và máy Jenkins hiện tại với Tuấn; không SSH theo IP cũ. Nếu đúng máy đang stopped và cần dùng Jenkins, bật riêng máy đó:

```powershell
aws ec2 start-instances --instance-ids $jenkinsId
if ($LASTEXITCODE -ne 0) { throw 'Không bật được Jenkins' }
aws ec2 wait instance-status-ok --instance-ids $jenkinsId
if ($LASTEXITCODE -ne 0) { throw 'Jenkins chưa qua status check' }
```

Lấy IP mới sau khi instance running:

```powershell
$jenkinsIp = (aws ec2 describe-instances --instance-ids $jenkinsId --query 'Reservations[0].Instances[0].PublicIpAddress' --output text).Trim()
if ($LASTEXITCODE -ne 0 -or $jenkinsIp -eq 'None' -or [string]::IsNullOrWhiteSpace($jenkinsIp)) { throw 'Jenkins chưa có Public IP' }
$jenkinsIp
Test-NetConnection -ComputerName $jenkinsIp -Port 22
notepad "$labRoot\mosquizto-infra\ansible\inventory\hosts.ini"
```

Chỉ sửa `ansible_host` của dòng `jenkins-server`, giữ các group khác và đường dẫn key Linux đang đúng:

```ini
[jenkins]
jenkins-server ansible_host=IP_JENKINS_VUA_LAY ansible_user=ubuntu ansible_ssh_private_key_file=/home/hp/.ssh/devops-teams-key
```

`terraform output jenkins_public_ip` có thể vẫn là giá trị trong state trước stop/start; truy vấn EC2 ở trên mới là bước lấy IP hiện tại. Không cần apply để làm mới IP phục vụ kết nối.

<a id="buoc-5"></a>

## 5. Vào WSL, kiểm tra Ansible và Jenkins

Từ PowerShell:

```powershell
wsl -d Ubuntu
```

Trong **Bash WSL**:

```bash
cd /mnt/d/uselessTool/DevOps/NT548/mosquizto-infra/ansible
export ANSIBLE_CONFIG="$PWD/ansible.cfg"
export AWS_SHARED_CREDENTIALS_FILE=/mnt/d/uselessTool/DevOps/NT548/mosquizto-infra/.aws/credentials
export AWS_PROFILE=default
export AWS_DEFAULT_REGION=us-east-1
export AWS_EC2_METADATA_DISABLED=true
export AWS_PAGER=''
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_SECURITY_TOKEN

# Kubeconfig Linux riêng: tránh trộn đường dẫn/tool Windows vào WSL.
mkdir -p "$HOME/.kube"
export KUBECONFIG="$HOME/.kube/mosquizto-eks"
export GODEBUG=http2client=0
aws sts get-caller-identity
aws eks update-kubeconfig --region us-east-1 --name project11-eks-cluster --alias mosquizto-eks --kubeconfig "$KUBECONFIG"
kubectl --context=mosquizto-eks get nodes

test -f /home/hp/.ssh/devops-teams-key && chmod 400 /home/hp/.ssh/devops-teams-key
ansible jenkins -i inventory/hosts.ini -m ping
ansible jenkins -i inventory/hosts.ini -b -m command -a 'systemctl is-active jenkins'
ansible jenkins -i inventory/hosts.ini -b -m command -a 'systemctl is-active docker'
```

AWS CLI, kubectl, Ansible và Helm phải được cài trong WSL nếu dùng tại đó; xem [README Ansible của repo infra](https://github.com/Dat-se40/mosquizto-infra/blob/eks-delivery-prerequisites/ansible/README.md) cho phần cài công cụ. Windows và WSL dùng chung **file credentials**, nhưng các biến môi trường phải được nạp riêng trong mỗi shell. Không cần copy credentials vào EC2 Jenkins cho việc mở giao diện.

Kết quả mong đợi: Ansible `pong`, Jenkins/Docker `active`. Nếu dịch vụ đã cài nhưng inactive, xem lỗi trước:

```bash
ansible jenkins -i inventory/hosts.ini -b -m command -a 'systemctl status jenkins --no-pager -l'
ansible jenkins -i inventory/hosts.ini -b -m command -a 'journalctl -u jenkins -n 80 --no-pager'
```

Nếu không có lỗi cấu hình cần sửa và chỉ cần bật dịch vụ đã cài:

```bash
ansible jenkins -i inventory/hosts.ini -b -m systemd_service -a 'name=docker state=started'
ansible jenkins -i inventory/hosts.ini -b -m systemd_service -a 'name=jenkins state=started'
```

Chỉ khi máy Jenkins thực sự mới/chưa cài, phối hợp Phong/Huy chạy lại playbook cài đặt; không chạy lại chỉ vì IP đổi:

```bash
ansible-playbook -i inventory/hosts.ini playbooks/install-jenkin.yml
```

Mở `http://IP_JENKINS_VUA_LAY:8080` trên trình duyệt. Backend Mosquizto chạy trên EKS, có thể phục hồi độc lập với Jenkins nếu image và cấu hình GitOps vẫn còn.

Nếu SSH vẫn timeout: kiểm tra IP EC2 đang dùng, state/status check, đúng SG gắn vào máy, rule TCP 22 khớp IP WSL và rule đã lưu. Sau đó mới kiểm tra route/NACL/firewall/VPN. `Permission denied (publickey)` là lỗi user/key sau khi đã kết nối được cổng 22; không xử lý giống timeout.

<a id="buoc-6"></a>

## 6. Chờ EKS khôi phục hệ thống, storage và ứng dụng

Quay lại **PowerShell đã nạp phần 1**, giữ nguyên context rõ ràng:

```powershell
kubectl --context=mosquizto-eks get nodes -o wide
kubectl --context=mosquizto-eks -n kube-system get deploy,ds,pods
kubectl --context=mosquizto-eks -n kube-system rollout status deployment/coredns --timeout=300s
kubectl --context=mosquizto-eks -n kube-system rollout status daemonset/aws-node --timeout=300s
kubectl --context=mosquizto-eks -n kube-system rollout status daemonset/kube-proxy --timeout=300s
kubectl --context=mosquizto-eks get storageclass mosquizto-gp3
kubectl --context=mosquizto-eks -n kube-system rollout status deployment/ebs-csi-controller --timeout=300s
kubectl --context=mosquizto-eks -n kube-system rollout status daemonset/ebs-csi-node --timeout=300s
```

Nếu CSI/StorageClass vẫn có, không cài chồng driver. Nếu thiếu, dùng nhánh khôi phục phần 10. Nếu CSI báo lỗi AWS/volume attach, xử lý quyền/AZ/theo Events; không xóa PVC để thử.

Kiểm tra DNS bằng Pod tạm, lệnh này tạo một Pod kiểm tra rồi xóa khi kết thúc:

```powershell
kubectl --context=mosquizto-eks -n default run mosquizto-dns-check --image=busybox:1.37.0 --restart=Never --rm -i --pod-running-timeout=120s -- nslookup kubernetes.default.svc.cluster.local
```

Nếu kiểm tra thất bại và Pod tạm còn lại, xem `describe pod mosquizto-dns-check -n default` rồi chỉ xóa Pod kiểm tra đó sau khi xem lỗi. Không xóa workload ứng dụng.

```powershell
kubectl --context=mosquizto-eks -n argocd get pods
kubectl --context=mosquizto-eks -n argocd get application mosquizto-eks
kubectl --context=mosquizto-eks -n argocd get application mosquizto-eks -o 'jsonpath={.spec.source.targetRevision}'
kubectl --context=mosquizto-eks -n mosquizto-eks get deploy,pods,svc,pvc
kubectl --context=mosquizto-eks -n mosquizto-eks get secret mosquizto-secret mosquizto-sync-secret
kubectl --context=mosquizto-eks -n mosquizto-eks rollout status deployment/postgres --timeout=360s
kubectl --context=mosquizto-eks -n mosquizto-eks rollout status deployment/redis --timeout=360s
kubectl --context=mosquizto-eks -n mosquizto-eks rollout status deployment/meilisearch --timeout=360s
kubectl --context=mosquizto-eks -n mosquizto-eks rollout status deployment/qdrant --timeout=360s
kubectl --context=mosquizto-eks -n mosquizto-eks rollout status deployment/mosquizto-backend-deployemnt --timeout=360s
```

Tên `deployemnt` bị viết sai trong manifest hiện tại; dùng đúng tên này khi chạy lệnh. Sau khi Node Ready, controller sẽ tự tạo/chạy Pod theo Deployment. Không bắt buộc restart tất cả Pod mỗi phiên.

Mong đợi năm Deployment đủ replica, bốn PVC `Bound`, Argo CD `Synced/Healthy`, nhánh `eks-argocd` khi PR chưa merge. Không đổi Application về `main` trong quy trình mở Lab này. Đọc metadata Secret bằng `get secret` như trên không in giá trị; tránh `-o yaml/json` hoặc giải mã Secret để chụp log.

Nếu Application còn nhưng chưa đồng bộ commit mong muốn, yêu cầu refresh rồi xem lỗi:

```powershell
kubectl --context=mosquizto-eks -n argocd annotate application mosquizto-eks argocd.argoproj.io/refresh=hard --overwrite
kubectl --context=mosquizto-eks -n argocd get application mosquizto-eks
```

Nếu đang ở chế độ manual và cần đồng bộ thay đổi đã review, chạy từ repo GitOps:

```powershell
Set-Location "$labRoot\mosquizto-gitops"
kubectl --context=mosquizto-eks -n argocd patch application mosquizto-eks --type=merge --patch-file operations/eks/sync-application.yaml
```

Nếu Pod còn lỗi, xem theo đúng namespace/tên đang hiện:

```powershell
kubectl --context=mosquizto-eks -n mosquizto-eks get events --sort-by=.metadata.creationTimestamp
kubectl --context=mosquizto-eks -n mosquizto-eks logs deployment/mosquizto-backend-deployemnt --tail=100
```

`FailedScheduling` → xem thiếu Node/tài nguyên/AZ; `FailedAttachVolume`/`FailedMount` → storage; `ImagePullBackOff` → image/ECR/quyền pull; `CreateContainerConfigError` → Secret/ConfigMap; `CrashLoopBackOff` → log ứng dụng và dependency. Dùng `kubectl describe pod TEN_POD -n mosquizto-eks` với tên thật, không chỉ nhìn mỗi cột STATUS.

<a id="buoc-7"></a>

## 7. Lấy URL backend hiện tại và kiểm tra SERVER_URL/email

Trong PowerShell:

```powershell
kubectl --context=mosquizto-eks -n mosquizto-eks get service mosquizto-service
$serviceRaw = kubectl --context=mosquizto-eks -n mosquizto-eks get service mosquizto-service -o json
if ($LASTEXITCODE -ne 0) { throw 'Chưa lấy được Service backend' }
$service = $serviceRaw -join "`n" | ConvertFrom-Json
$publicHost = $service.status.loadBalancer.ingress[0].hostname
if ([string]::IsNullOrWhiteSpace($publicHost)) { throw 'Load Balancer chưa có hostname; xem Events của Service' }
$backendUrl = "http://${publicHost}:8080/"
$backendUrl
(Invoke-WebRequest -UseBasicParsing -Uri ($backendUrl + 'v3/api-docs')).StatusCode
```

Mong đợi HTTP 200. Dùng `$backendUrl` làm base URL Postman/Android/máy khác. Nếu LB có hostname nhưng HTTP chưa được, xem Pod Ready, EndpointSlice của `mosquizto-service`, Events Service và target health của LB; DNS có sẵn không chứng minh backend khỏe.

So sánh cấu hình cluster với môi trường **bên trong backend**:

```powershell
kubectl --context=mosquizto-eks -n mosquizto-eks get configmap mosquizto-config -o 'jsonpath={.data.SERVER_URL}'
kubectl --context=mosquizto-eks -n mosquizto-eks exec deployment/mosquizto-backend-deployemnt -- printenv SERVER_URL
```

Nếu hostname vẫn như trước và hai giá trị đúng, không cần sửa Git. Nếu hostname đổi:

1. Trong repo GitOps, kiểm tra `git status` và nhánh đang làm việc là `eks-argocd`.
2. Sửa `overlays/eks/config.yaml`: `SERVER_URL` bằng `$backendUrl`, có dấu `/` cuối. Không sửa trực tiếp ConfigMap rồi để self-heal ghi đè.
3. Xem diff, commit riêng file cấu hình, push nhánh review. Giữ nguyên `main`.

```powershell
Set-Location "$labRoot\mosquizto-gitops"
git status --short --branch
notepad overlays/eks/config.yaml
kubectl kustomize overlays/eks | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Overlay chưa render được' }
git diff -- overlays/eks/config.yaml
# Kiểm tra git diff --cached trước; không gộp file đã stage từ việc khác.
git diff --cached --name-only
# Chỉ chạy ba lệnh sau khi diff đúng, không có thay đổi khác đang stage.
git add -- overlays/eks/config.yaml
git commit -m "Cập nhật URL public của backend trong lab"
git push origin eks-argocd
```

Chờ Argo CD sync đúng commit, kiểm tra ConfigMap đã có URL mới, rồi restart **riêng backend**:

```powershell
kubectl --context=mosquizto-eks -n argocd get application mosquizto-eks -o 'jsonpath={.status.sync.revision}'
kubectl --context=mosquizto-eks -n mosquizto-eks get configmap mosquizto-config -o 'jsonpath={.data.SERVER_URL}'
kubectl --context=mosquizto-eks -n mosquizto-eks rollout restart deployment/mosquizto-backend-deployemnt
kubectl --context=mosquizto-eks -n mosquizto-eks rollout status deployment/mosquizto-backend-deployemnt --timeout=360s
kubectl --context=mosquizto-eks -n mosquizto-eks exec deployment/mosquizto-backend-deployemnt -- printenv SERVER_URL
(Invoke-RestMethod -Uri ($backendUrl + 'v3/api-docs')).servers
```

Backend đọc ConfigMap qua biến môi trường, nên cập nhật ConfigMap không tự đổi môi trường của container đang chạy. Email xác nhận gửi **sau** khi backend nhận URL mới mới dùng cấu hình mới; email đã gửi không được viết lại. Với link cũ còn hiệu lực, có thể thay phần host/port sang URL mới, giữ nguyên đường dẫn và mã xác nhận. Không đăng lại cùng tài khoản một cách máy móc vì user có thể đã tồn tại/chưa xác nhận.

<a id="buoc-8"></a>

## 8. Mở Argo CD, Prometheus, Grafana và backend local

Mỗi lệnh `port-forward` chạy trong **một PowerShell riêng đã nạp biến ở phần 1**; giữ cửa sổ mở, dùng `Ctrl+C` để đóng. Các địa chỉ localhost chỉ truy cập được trên máy đang chạy tunnel.

**Argo CD:**

```powershell
kubectl --context=mosquizto-eks -n argocd port-forward service/argocd-server 18443:443
```

Mở `https://localhost:18443`. Dùng tài khoản hiện có; trình duyệt có thể cảnh báo chứng chỉ tự ký của lab. Không reset tài khoản mỗi phiên.

**Prometheus:**

```powershell
kubectl --context=mosquizto-eks -n monitoring get pods,svc
kubectl --context=mosquizto-eks -n monitoring port-forward service/prometheus-kube-prometheus-prometheus 19090:9090
```

Mở `http://localhost:19090`, kiểm tra **Status → Targets**. Chờ thêm vài chu kỳ scrape sau khi Pod Ready; lịch sử metric có thể mất nếu cấu hình không lưu bền.

**Grafana:**

```powershell
kubectl --context=mosquizto-eks -n monitoring port-forward service/prometheus-grafana 13000:80
```

Mở `http://localhost:13000`, dùng tài khoản/mật khẩu đã cài. Template monitoring hiện tắt persistence Grafana, nên không coi dashboard do sửa tay trong UI là dữ liệu được backup. Không chạy lại Helm/Ansible chỉ để mở UI.

**Backend local để chẩn đoán khi đường public có lỗi:**

```powershell
kubectl --context=mosquizto-eks -n mosquizto-eks port-forward service/mosquizto-service 18080:8080
```

Mở `http://localhost:18080/swagger-ui/index.html`. Port-forward backend không tự thay `SERVER_URL`; link email vẫn theo cấu hình runtime.

Nếu muốn dùng địa chỉ public monitoring đã có, lấy lại `EXTERNAL-IP` và port từ:

```powershell
kubectl --context=mosquizto-eks -n monitoring get service prometheus-grafana prometheus-kube-prometheus-prometheus
```

Dùng đúng hostname/port hiện ra; không tái sử dụng IP của Jenkins cho monitoring EKS. Các tên Service trong phần này theo release `prometheus` đã chạy trước đó; nếu không thấy, liệt kê `get svc -n monitoring` để đối chiếu release, đừng tạo thêm release mới chỉ vì khác tên.

<a id="buoc-9"></a>

## 9. Kiểm tra cuối phiên khởi động

```powershell
kubectl --context=mosquizto-eks get nodes
kubectl --context=mosquizto-eks -n mosquizto-eks get deploy,pvc
kubectl --context=mosquizto-eks -n argocd get application mosquizto-eks
kubectl --context=mosquizto-eks -n monitoring get pods
kubectl --context=mosquizto-eks -n mosquizto-eks logs deployment/mosquizto-backend-deployemnt --tail=200 | Select-String 'Embedding ready'
```

Hoàn thành khi hai Node Ready; CoreDNS/CNI/kube-proxy/CSI khỏe; năm Deployment ứng dụng đủ replica; bốn PVC Bound; Argo CD Synced/Healthy; OpenAPI 200; đăng nhập hợp lệ chạy được và monitoring truy cập được. `Embedding ready` có thể đã ra khỏi 200 dòng log cuối; xem log từ lúc khởi động nếu không tìm thấy, chưa vội kết luận ONNX lỗi.

Không cần sync lại toàn bộ dữ liệu search mỗi lần mở Lab nếu PostgreSQL/Meili/Qdrant vẫn giữ dữ liệu. Khi thực sự cần, từ gốc repo GitOps dùng [Start-Sync.ps1](../operations/eks/Start-Sync.ps1) với `-Context mosquizto-eks` để dry-run trước, xem log Job và chờ Completed rồi mới cân nhắc chạy lại với `-Write`. Xem [hướng dẫn EKS](../overlays/eks/README.md); không bật cleanup để chữa lỗi mở Lab.

<a id="buoc-10"></a>

## 10. Chỉ dùng khi thành phần thực sự bị mất

Đây là nhánh khôi phục, không phải các bước chạy hằng ngày. Phân biệt **Pod Pending vì không có Node** với **Deployment/Secret/PVC/cluster không còn**. Nếu workload còn tồn tại như ví dụ ở phần 0, ưu tiên phục hồi worker trước.

- **Cluster/nodegroup mất:** đối chiếu AWS, Terraform state và plan với Tuấn; xem [Terraform trong repo infra](https://github.com/Dat-se40/mosquizto-infra/tree/eks-delivery-prerequisites/terraform). Không xóa state, chạy destroy hoặc tạo cluster mới để sửa lỗi đăng nhập/Node.
- **EBS CSI/StorageClass mất nhưng cluster còn:** phối hợp Tuấn/Phong, làm theo [README storage của repo infra](https://github.com/Dat-se40/mosquizto-infra/blob/eks-delivery-prerequisites/kubernetes/storage/README.md). Installer hiện render chart rồi apply, không phải Helm release hay managed add-on; không cài thêm bản khác chồng lên.
- **Secret ứng dụng mất:** giữ đúng file EKS riêng và các mật khẩu đã khởi tạo DB. Từ repo GitOps, chạy lệnh bên dưới. Không tạo password DB ngẫu nhiên mới khi còn PostgreSQL volume cũ.

```powershell
Set-Location "$labRoot\mosquizto-gitops"
kubectl --context=mosquizto-eks apply -f bootstrap/eks/namespace.yaml
./operations/eks/Set-RuntimeSecrets.ps1 -Context mosquizto-eks
```

- **Argo CD/Application mất:** chỉ sau khi Node và storage khỏe, Secret có sẵn, kiểm tra overlay và cài lại theo bản pin trong repo. Chọn lại đúng nhánh review, self-heal bật, prune tắt:

```powershell
Set-Location "$labRoot\mosquizto-gitops"
kubectl kustomize overlays/eks | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Overlay lỗi' }
kubectl --context=mosquizto-eks apply --dry-run=server -k overlays/eks
if ($LASTEXITCODE -ne 0) { throw 'Kiểm tra phía server thất bại' }
./bootstrap/Install-ArgoCD.ps1 -Context mosquizto-eks
if ($LASTEXITCODE -ne 0) { throw 'Kiểm tra kết quả cài Argo CD trước khi tiếp tục' }
kubectl --context=mosquizto-eks apply -k bootstrap/eks-review-selfheal
```

Nếu chỉ Application mất còn Argo CD khỏe, bỏ qua installer. Không dùng `kubectl apply -k overlays/eks` để thay đường triển khai Argo CD thông thường. Theo dõi Application; nếu lỗi `app path does not exist`, kiểm tra nhánh remote có overlay và `targetRevision` là `eks-argocd`.

- **Monitoring thực sự chưa cài/mất:** phối hợp Phong. Trong WSL đã cấu hình credentials/kubeconfig ở phần 5, kiểm tra `helm list -n monitoring` và tài nguyên trước. Chỉ khi cần cài/khôi phục mới chạy playbook:

```bash
cd /mnt/d/uselessTool/DevOps/NT548/mosquizto-infra/ansible
ansible-playbook -i inventory/hosts.ini playbooks/install-prometheus.yml --syntax-check
ansible-playbook -i inventory/hosts.ini playbooks/install-prometheus.yml -e aws_region=us-east-1 -e eks_cluster_name=project11-eks-cluster -e prometheus_release_name=prometheus
```

Truyền rõ các biến trên vì `inventory/group_vars/monitoring.yml` hiện ghi region/cluster khác với role defaults; không dựa vào cấu hình ngầm. Playbook hiện dùng group `control` trên WSL và hỏi mật khẩu Grafana, không cài monitoring trên EC2 Jenkins. Việc cài lại có thể tạo Load Balancer tính phí và thay phiên bản chart nếu chưa pin; thống nhất phiên bản/values với Phong trước khi chạy.

- **PVC/PV/EBS volume mất:** dừng việc ghi dữ liệu, xác định còn volume/backup hay không. `Retain` không phải backup. Không tạo PVC mới rồi coi dữ liệu đã được khôi phục. Không xóa PVC, namespace ứng dụng hay chạy sync cleanup trong lúc chẩn đoán.

<a id="buoc-11"></a>

## 11. Kết thúc phiên

Đóng các tunnel bằng `Ctrl+C`, thoát WSL bằng `exit` khi xong. Lưu thay đổi mã/cấu hình cần thiết vào đúng nhánh, giữ credentials/key/env/plan/log riêng ngoài Git. Ghi lại lỗi còn tồn tại trước khi End Lab để phân biệt log cũ và mới lần sau.

Không dùng `terraform destroy` để kết thúc buổi học thông thường hoặc sửa timeout. End Lab không phải bằng chứng tất cả tài nguyên/dữ liệu đã bị xóa; việc lưu giữ, dọn tài nguyên và chi phí phải theo quy định Lab/nhóm. Lần sau bắt đầu lại từ phần 1, không nhảy thẳng vào apply toàn bộ.

<a id="buoc-12"></a>

## 12. Kết quả nghiệm thu đã ghi nhận — 04/11/2026

Các kết quả này thuộc phiên kiểm chứng cũ; khi mở lại Lab phải kiểm tra theo phần 1–9. Lần báo cáo sau End Lab gần nhất chỉ có output không có Node và Pod Pending; chưa có kết quả xác nhận phục hồi sau lần đó.

### 12.1. Cấu hình và phiên bản đã dùng

- EKS `project11-eks-cluster`, region `us-east-1`: hai worker từng Ready, DNS/CNI hoạt động. Namespace ứng dụng `mosquizto-eks` có hai runtime Secret cấp ngoài Git, năm Deployment Ready và bốn PVC Bound.
- Argo CD v3.6.0 non-HA: bảy Pod Ready, Application Synced/Healthy. Lỗi cài CRD bị ngắt kết nối đã được xử lý; lỗi `app path does not exist` do chọn main được xử lý bằng bootstrap review.
- EBS CSI chart 2.67.1, driver 1.67.1; controller 5/5 và CSI node 3/3 trên từng worker. Cài bằng render chart rồi kubectl apply, không phải Helm release hay managed add-on. Dùng LabRole qua IMDSv2/host network; controller health port 9811 tránh trùng node plugin 9808.
- StorageClass gp3 mã hóa, WaitForFirstConsumer, cho mở rộng, Retain; PostgreSQL 2Gi, Redis/Meilisearch/Qdrant mỗi dịch vụ 1Gi. Bài ghi/tạo lại Pod/đọc lại PVC đã qua. PVC/PV/namespace thử và EBS `vol-078564037cbf9571e` đã dọn, truy vấn volume sau đó trả danh sách rỗng.
- Image backend từ commit `032120f4eca0f36220d9514aa1395e3346189576`, Linux amd64, ONNX nằm trong image; checksum model/tokenizer và UID 10001 đã kiểm tra. Build/push thủ công trong thư mục tạm riêng trên EC2 đang có lúc đó; đây chưa phải kết quả Jenkins CI.
- ECR private `mosquizto-backend`: immutable tags, AES256. Tag `git-032120f4eca0f36220d9514aa1395e3346189576-onnx`; digest `sha256:7aef4eb70349b0759019d5f69fb46a9b2798d84b7cef3b679a6be6335d9c5908`. Khi vận hành, dùng digest đang được GitOps theo dõi; không tự hạ về digest lịch sử này.

### 12.2. Các kiểm tra đã qua

- Render base/local/local-onnx/EKS; local/local-onnx khớp từng byte với bản trước khi refactor khi dùng cùng env riêng. EKS render từ checkout sạch không cần file Secret, selector/port/PVC hợp lệ.
- Server dry-run qua cho 16 tài nguyên overlay EKS, bootstrap và mẫu Sync Job; tám script PowerShell và script Bash push image qua kiểm tra cú pháp. Dockerfile dùng `-DskipTests`, chưa chạy thêm Maven unit test trong lần triển khai này.
- Manual sync triển khai đủ workload; đổi annotation trong Git được áp dụng. Sửa lệch trên cluster tạo OutOfSync; bật self-heal đưa giá trị về `eks-lab`. Chính sách review cuối phiên: selfHeal=true, prune=false, nguồn `eks-argocd`.
- Flyway chạy 24 migration; dữ liệu ban đầu 38 collection/27 user. OpenAPI/Swagger 200, đăng nhập đúng thành công/sai trả 401; danh sách công khai, search và recommendation có xác thực trả 200.
- Backend và CLI có `Embedding ready`, đúng revision, 384 chiều. Dry-run `mosquizto-sync-d4be7ccff502` quét 38 bản ghi mỗi store, không ghi/không lỗi; Job ghi `mosquizto-sync-bae825c02f86` hoàn thành 38 bản ghi mỗi store, cleanup tắt.
- Meilisearch có 38 document, hết indexing; Qdrant có 38 point green, 384/Cosine. Vector mẫu hữu hạn, norm `0.9999999966`.
- Tạo lại riêng Pod PostgreSQL giữ nguyên PVC/PV và checksum collection `38:153261f381b39b65dcd910628a6b016d`. Đỉnh RAM backend quan sát khoảng 553Mi, dưới limit 1Gi; chưa phải load test hoặc sizing production.
- Sau mốc nghiệm thu ban đầu, backend đã có Load Balancer public; người dùng đăng nhập bằng Postman nhận 200. Sync ConfigMap rồi rollout backend đã xác nhận `SERVER_URL` trong container và OpenAPI đúng URL public. Không coi kết quả này là đã nghiệm thu toàn bộ flow xác nhận email.

### 12.3. Tiền sử lỗi và phần chưa nghiệm thu

- Bootstrap từng lỗi trên worker `i-0117b68bf93956adf` lúc 2026-11-03 21:55:11 UTC và `i-0dc603b66435364d8` lúc 21:54:21 UTC; nodeadm bị SCP chặn `ec2:DescribeInstances` như phần 2.3. Lỗi từng tái diễn trên worker thay thế. Khi nghiệm thu đã có Node Ready, nhưng chưa có bằng chứng xác định cách phía Lab xử lý quyền hoặc bảo đảm lỗi không tái diễn.
- Chưa nghiệm thu Jenkins tự build/test/scan/push/cập nhật GitOps, OWASP/Trivy, chuỗi đổi image/rollback, email xác nhận hoàn chỉnh, dashboard/Targets monitoring, backup/restore, TLS/HA hoặc load test. Xem [báo cáo tiến độ 05/11](5_11_2026.md) để đối chiếu phạm vi đã có bằng chứng.

### 12.4. Nhánh và bàn giao

- [GitOps PR #2](https://github.com/Dat-se40/mosquizto-gitops/pull/2), nhánh `eks-argocd`; commit nghiệm thu trước đổi tên nhánh `14c9e61cec96f83fe7044990e6110368d4b17485`. Tại mốc bàn giao, main ở `fcfb5906e07bd01d01d339558eae030797dfcff7` và chưa merge.
- [Infra PR #2](https://github.com/Dat-se40/mosquizto-infra/pull/2), nhánh `eks-delivery-prerequisites`; commit trước đổi tên nhánh `be1b0d94604b5355ddf9b2eb90481152e6087f29`. Hai PR #2 thay PR #1 để bỏ tiền tố nhánh.
- Các thay đổi/xóa file không thuộc tác vụ được giữ ngoài commit. Không đưa env thật, private key, token hay Secret render vào Git. EC2 Jenkins từng thay instance/IP; luôn hỏi AWS lấy trạng thái/IP hiện tại thay vì dùng ID/IP lịch sử.

<a id="nguon-doi-chieu"></a>

## Nguồn đối chiếu

- [AWS: xử lý Node không join EKS](https://docs.aws.amazon.com/eks/latest/userguide/troubleshooting.html).
- [AWS: managed node groups và Auto Scaling Group](https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html).
- [AWS: stop/start EC2 và thay đổi public IPv4](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/Stop_Start.html).
- [AWS: lấy console log EC2](https://docs.aws.amazon.com/cli/latest/reference/ec2/get-console-output.html).
- [AWS: nodeadm trên EKS AMI](https://awslabs.github.io/amazon-eks-ami/nodeadm/).
- [AWS: giới hạn quyền bằng SCP](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps.html).
- [AWS: Load Balancer, DNS và target health](https://docs.aws.amazon.com/elasticloadbalancing/latest/userguide/how-elastic-load-balancing-works.html).
- [Kubernetes: cập nhật ConfigMap và biến môi trường](https://kubernetes.io/docs/tutorials/configuration/updating-configuration-via-a-configmap/).
- [HashiCorp: plan, saved plan và resource targeting](https://developer.hashicorp.com/terraform/cli/commands/plan).
