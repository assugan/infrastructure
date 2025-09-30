# Infrastructure

Репозиторий с кодом инфраструктуры и автоматизацией деплоя приложения и мониторинга.

##  Назначение
- Создание и настройка инфраструктуры AWS.
- Автоматический деплой приложения и стека мониторинга.

##  Технологии
- **Terraform** — создание ресурсов AWS:
  - EC2 (Ubuntu 24.04)
  - S3 (для terraform.tfstate)
  - Route53 (домен assugan.click)
- **Ansible** — конфигурация EC2 и деплой:
  - Docker + Docker Compose
  - Запуск контейнера приложения `simple_web_page`
  - Мониторинг-стек (**Prometheus, Grafana, Alertmanager, Loki, Promtail, cAdvisor, Node Exporter, Blackbox Exporter**)
- **Jenkins** — CI/CD, вызывает Ansible-playbook из этого репо.

##  Terraform
`git clone https://github.com/assugan/infrastructure.git`
- **Хранилище s3 bucket**
```
   cd infrastructure/storage
   terraform init
   terraform plan
   terraform apply
```
- **Основная инфраструктура**
```
   cd infrastructure/main_infra
   terraform init
   terraform plan
   terraform apply
```
- **Как итог, в AWS создается:**
  - Хранилище для стейта Terraform
  - Базовая VPC
  - Security group
  - EC2 instance
    - необходимо создать в AWS в разделе EC2 - Key pairs, для ssh-доступа к инстансу
  - DNS-записи в Route 53
    - также необходимо приобрести домен (здесь же в AWS или другом сервисе)

## Ansible 
- Вызывается Jenkinsfile из репозитория [simple_web_page](https://github.com/assugan/simple_web_page).
   - Устанавливает Docker и Docker Compose.
   - Деплоит контейнер приложения `web-app`.
   - Поднимает мониторинг-стек:
     - Prometheus
     - Grafana
     - Node Exporter
     - cAdvisor
     - Blackbox Exporter
     - Loki + Promtail
     - Alertmanager (с уведомлениями в Telegram).

### Деплой вручную
Уже сделан `git clone https://github.com/assugan/infrastructure.git`
```
    cd infrastructure/ansible
    # Запуск Ansible
    ansible-playbook -i inventory.ini site.yml \
    -u ubuntu --private-key ~/path/to/ec2-key.pem
```
## После успешного пайплана и деплоя всех компонентов веб страничка, в моем случае, будет доступна по адресу:
`assugan.click` 

### Доступ к EC2 инстансу (Виртуальная машина на Ubuntu 24.04)
```
    ssh -i ~/path/to/ec2-key.pem ubuntu@<your-domain>
```
### Доступ в UI мониторинга
```
    ssh -i ~/.ssh/ssh-diploma-key.pem \
      -L 3000:127.0.0.1:3000 \
      -L 9090:127.0.0.1:9090 \
      -L 9093:127.0.0.1:9093 \
       ubuntu@<your-public-ip-address>
```
   **После чего Prometheus и Grafana будут доступны в браузере по адресам:**
    `http://127.0.0.1:9090`
    `http://127.0.0.1:3000`
