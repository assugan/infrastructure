pipeline {
  agent any

  environment {
    AWS_DEFAULT_REGION = 'eu-central-1'
    TF_IN_AUTOMATION   = 'true'

    // Jenkins credentials:
    TELEGRAM_BOT_TOKEN = credentials('telegram-bot-token')
    TELEGRAM_CHAT_ID   = credentials('telegram-chat-id')

    // Строковый credential: имя существующей AWS KeyPair
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
          withTerraform(installation: 'terraform-1.6.6') {
            sh 'terraform -version'
            sh 'terraform init -upgrade'
          }
        }
      }
    }

    stage('Validate & Plan (all branches)') {
      steps {
        dir('main') {
          withTerraform(installation: 'terraform-1.6.6') {
            sh 'terraform fmt -check'
            sh 'terraform validate'
            // подставляем имя KeyPair из Jenkins credentials
            sh "terraform plan -var='ssh_key_name=${SSH_KEY_NAME}' -out=tfplan"
          }
        }
      }
      post {
        success { script { notifyTG("✅ [${env.JOB_NAME}] plan OK on ${env.BRANCH_NAME} (#${env.BUILD_NUMBER})") } }
        failure { script { notifyTG("❌ [${env.JOB_NAME}] plan FAILED on ${env.BRANCH_NAME} (#${env.BUILD_NUMBER})") } }
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
          withTerraform(installation: 'terraform-1.6.6') {
            sh 'terraform apply -auto-approve tfplan'
          }
        }
      }
      post {
        success { script { notifyTG("🚀 [${env.JOB_NAME}] apply DONE on main (#${env.BUILD_NUMBER})") } }
        failure { script { notifyTG("🔥 [${env.JOB_NAME}] apply FAILED on main (#${env.BUILD_NUMBER})") } }
      }
    }

    stage('Ansible Configure (main only)') {
      when { branch 'main' }
      steps {
        // достаём IP из outputs
        dir('main') {
          withTerraform(installation: 'terraform-1.6.6') {
            script {
              def IP = sh(script: "terraform output -raw public_ip", returnStdout: true).trim()
              writeFile file: 'inventory', text: "${IP}\n"
              echo "Inventory generated with host: ${IP}"
            }
          }
        }
        dir('ansible') {
          sh 'ANSIBLE_HOST_KEY_CHECKING=false ansible -i ../main/inventory all -m ping -u ubuntu || true'
          sh 'ANSIBLE_HOST_KEY_CHECKING=false ansible-playbook -i ../main/inventory site.yml -u ubuntu'
        }
      }
      post {
        success { script { notifyTG("🔧 [${env.JOB_NAME}] ansible DONE on main") } }
        failure { script { notifyTG("🛑 [${env.JOB_NAME}] ansible FAILED on main") } }
      }
    }
  }
}

// Безопасная отправка в Telegram (без Groovy-интерполяции $)
def notifyTG(String message) {
  withEnv(["MSG=${message}"]) {
    sh '''#!/bin/bash
curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d chat_id="${TELEGRAM_CHAT_ID}" \
  --data-urlencode "text=${MSG}"
'''
  }
}