// Jenkinsfile — INFRA (single env). Ветки:
//   draft-infra => только plan
//   main        => plan -> manual approve -> apply -> ansible

pipeline {
  agent any

  environment {
    AWS_DEFAULT_REGION = 'eu-central-1'
    TF_IN_AUTOMATION   = 'true'

    // где лежит Terraform и Ansible:
    TF_DIR      = 'infrastructure/main_infra'
    ANSIBLE_DIR = 'infrastructure/ansible'

    // Telegram creds (Secret text)
    TELEGRAM_BOT_TOKEN = credentials('telegram-bot-token')
    TELEGRAM_CHAT_ID   = credentials('telegram-chat-id')

    // Имя AWS KeyPair (String credential) — нужно Terraform’у
    SSH_KEY_NAME = credentials('ec2-ssh-key')

    // Кэш провайдеров — быстрее init на macOS
    TF_PLUGIN_CACHE_DIR = "${WORKSPACE}/.terraform.d/plugin-cache"
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
        dir("${env.TF_DIR}") {
          script {
            def TF = tool name: 'terraform-1.6.6'
            withEnv(["TF_BIN=${TF}/terraform", "TF_PLUGIN_CACHE_DIR=${env.TF_PLUGIN_CACHE_DIR}"]) {
              sh '''
                mkdir -p "$TF_PLUGIN_CACHE_DIR"
                "$TF_BIN" -version
                "$TF_BIN" init -upgrade
                # macOS: иногда провайдеры в quarantine — снимем на всякий
                if command -v xattr >/dev/null 2>&1; then
                  xattr -dr com.apple.quarantine .terraform || true
                fi
                chmod -R +x .terraform || true
              '''
            }
          }
        }
      }
    }

    stage('Validate & Plan (all branches)') {
      steps {
        dir("${env.TF_DIR}") {
          script {
            def TF = tool name: 'terraform-1.6.6'
            withEnv([
              "TF_BIN=${TF}/terraform",
              "TF_PLUGIN_CACHE_DIR=${env.TF_PLUGIN_CACHE_DIR}",
              // безопасно прокидываем имя KeyPair
              "TF_VAR_ssh_key_name=${SSH_KEY_NAME}"
            ]) {
              sh '''
                # fmt: если есть несоответствия — автоисправим, но не валим сборку
                set +e
                "$TF_BIN" fmt -check -recursive
                st=$?
                if [ $st -ne 0 ]; then
                  echo "⚠️ terraform fmt нашёл несоответствия. Автоформатирую..."
                  "$TF_BIN" fmt -recursive
                fi
                set -e

                "$TF_BIN" validate
                "$TF_BIN" plan -out=tfplan
              '''
            }
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
      steps { input message: 'Apply infrastructure?', ok: 'Apply' }
    }

    stage('Apply (main only)') {
      when { branch 'main' }
      steps {
        dir("${env.TF_DIR}") {
          script {
            def TF = tool name: 'terraform-1.6.6'
            withEnv(["TF_BIN=${TF}/terraform", "TF_PLUGIN_CACHE_DIR=${env.TF_PLUGIN_CACHE_DIR}"]) {
              sh '"$TF_BIN" apply -auto-approve tfplan'
            }
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
        // 1) достаём IP из Terraform outputs
        dir("${env.TF_DIR}") {
          script {
            def TF = tool name: 'terraform-1.6.6'
            env.APP_IP = sh(script: "\"${TF}/terraform\" output -raw public_ip", returnStdout: true).trim()
            echo "EC2 public IP: ${env.APP_IP}"
          }
        }

        // 2) формируем inventory для Ansible рядом с playbook
        dir("${env.ANSIBLE_DIR}") {
          script {
            def inv = "[web]\n${env.APP_IP}\n"
            writeFile file: 'inventory.ini', text: inv
            echo "Inventory written to ${env.ANSIBLE_DIR}/inventory.ini"
          }
        }

        // 3) запускаем Ansible c SSH-ключом из Jenkins credentials
        // Создай credential типа "SSH Username with private key" с ID: ec2-ssh-private, username: ubuntu
        withCredentials([sshUserPrivateKey(credentialsId: 'ec2-ssh-private', keyFileVariable: 'SSH_KEY_FILE', usernameVariable: 'SSH_USER')]) {
          dir("${env.ANSIBLE_DIR}") {
            sh '''
              ANSIBLE_HOST_KEY_CHECKING=false ansible -i inventory.ini web -m ping -u "$SSH_USER" --private-key "$SSH_KEY_FILE" || true
              ANSIBLE_HOST_KEY_CHECKING=false ansible-playbook -i inventory.ini site.yml -u "$SSH_USER" --private-key "$SSH_KEY_FILE"
            '''
          }
        }
      }
      post {
        success { script { notifyTG("🔧 [${env.JOB_NAME}] ansible DONE on main") } }
        failure { script { notifyTG("🛑 [${env.JOB_NAME}] ansible FAILED on main") } }
      }
    }
  }
}

// Телеграм без Groovy-интерполяции
def notifyTG(String message) {
  withEnv(["MSG=${message}"]) {
    sh '''#!/bin/bash
curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d chat_id="${TELEGRAM_CHAT_ID}" \
  --data-urlencode "text=${MSG}"
'''
  }
}