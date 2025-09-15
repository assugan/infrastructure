// Jenkinsfile — INFRA (single-env), Terraform в Docker
// Ветки: draft-infra => только plan; main => plan -> approve -> apply -> ansible

def TF_IMAGE = 'hashicorp/terraform:1.6.6'  // можно обновить при желании

pipeline {
  agent any

  environment {
    AWS_DEFAULT_REGION = 'eu-central-1'
    TF_IN_AUTOMATION   = 'true'

    TELEGRAM_BOT_TOKEN = credentials('telegram-bot-token')
    TELEGRAM_CHAT_ID   = credentials('telegram-chat-id')

    // Имя существующей AWS KeyPair (String credential в Jenkins с ID: ec2-ssh-key)
    SSH_KEY_NAME       = credentials('ec2-ssh-key')
  }

  options { timestamps() }

  stages {

    stage('Checkout') {
      steps {
        echo "Branch: ${env.BRANCH_NAME}"
        checkout scm
      }
    }

    stage('Terraform Init') {
      steps {
        dir('main') {
          script {
            // Пробрасываем ~/.aws внутрь контейнера (для профилей/credentials)
            docker.image(TF_IMAGE).inside('-v $HOME/.aws:/root/.aws:ro') {
              sh 'terraform version'
              sh 'terraform init -upgrade'
            }
          }
        }
      }
    }

    stage('Validate & Plan (all branches)') {
      steps {
        dir('main') {
          script {
            docker.image(TF_IMAGE).inside('-v $HOME/.aws:/root/.aws:ro') {
              sh 'terraform fmt -check'
              sh 'terraform validate'
              sh """
                terraform plan \
                  -var="ssh_key_name=${SSH_KEY_NAME}" \
                  -out=tfplan
              """
            }
          }
        }
      }
      post {
        success { script { notify("✅ [${env.JOB_NAME}] plan OK on ${env.BRANCH_NAME} (#${env.BUILD_NUMBER})") } }
        failure { script { notify("❌ [${env.JOB_NAME}] plan FAILED on ${env.BRANCH_NAME} (#${env.BUILD_NUMBER})") } }
      }
    }

    stage('Manual Approval (main only)') {
      when { branch 'main' }
      steps {
        input message: 'Apply infrastructure?', ok: 'Apply'
      }
    }

    stage('Apply (main only)') {
      when { branch 'main' }
      steps {
        dir('main') {
          script {
            docker.image(TF_IMAGE).inside('-v $HOME/.aws:/root/.aws:ro') {
              sh 'terraform apply -auto-approve tfplan'
            }
          }
        }
      }
      post {
        success { script { notify("🚀 [${env.JOB_NAME}] apply DONE on main (#${env.BUILD_NUMBER})") } }
        failure { script { notify("🔥 [${env.JOB_NAME}] apply FAILED on main (#${env.BUILD_NUMBER})") } }
      }
    }

    stage('Ansible Configure (main only)') {
      when { branch 'main' }
      steps {
        // Достаём IP из Terraform output (тоже через контейнер)
        dir('main') {
          script {
            def IP = docker.image(TF_IMAGE).inside('-v $HOME/.aws:/root/.aws:ro') {
              sh(script: 'terraform output -raw public_ip', returnStdout: true)
            }.trim()
            writeFile file: 'inventory', text: "${IP}\n"
            echo "Inventory generated with host: ${IP}"
          }
        }

        // Применяем Ansible на хосте (должен быть установлен ansible на агенте Jenkins)
        dir('ansible') {
          sh 'ANSIBLE_HOST_KEY_CHECKING=false ansible -i ../main/inventory all -m ping -u ubuntu || true'
          sh 'ANSIBLE_HOST_KEY_CHECKING=false ansible-playbook -i ../main/inventory site.yml -u ubuntu'
        }
      }
      post {
        success { script { notify("🔧 [${env.JOB_NAME}] ansible DONE on main") } }
        failure { script { notify("🛑 [${env.JOB_NAME}] ansible FAILED on main") } }
      }
    }
  }
}

// безопасная отправка в Telegram (без Groovy-интерполяции)
def notify(String message) {
  withEnv(["MSG=${message}"]) {
    sh '''#!/bin/bash
curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d chat_id="${TELEGRAM_CHAT_ID}" \
  --data-urlencode "text=${MSG}"
'''
  }
}