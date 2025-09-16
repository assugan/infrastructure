// Jenkinsfile — INFRA (single env). Ветки:
//   draft-infra => только plan
//   main        => plan -> manual approve -> apply -> ansible

pipeline {
  agent any

  environment {
    AWS_DEFAULT_REGION = 'eu-central-1'
    TF_IN_AUTOMATION   = 'true'

    // где лежит Terraform и Ansible в репозитории
    TF_DIR      = 'infrastructure/main_infra'
    ANSIBLE_DIR = 'infrastructure/ansible'

    // Jenkins credentials
    TELEGRAM_BOT_TOKEN = credentials('telegram-bot-token')
    TELEGRAM_CHAT_ID   = credentials('telegram-chat-id')
    SSH_KEY_NAME       = credentials('ec2-ssh-key') // ИМЯ KeyPair в AWS

    // кэш плагинов Terraform (ускоряет init)
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
        script {
          def TF = tool name: 'terraform-1.6.6'
          withEnv(["TF_BIN=${TF}/terraform", "TF_PLUGIN_CACHE_DIR=${env.TF_PLUGIN_CACHE_DIR}"]) {
            sh '''
              echo "== PWD =="; pwd
              echo "== TREE (top) =="; ls -la
              mkdir -p "$TF_PLUGIN_CACHE_DIR"
              "$TF_BIN" -chdir=''' + "${env.TF_DIR}" + ''' -version
              "$TF_BIN" -chdir=''' + "${env.TF_DIR}" + ''' init -upgrade
              # macOS: снять quarantine с провайдеров и выдать +x
              if command -v xattr >/dev/null 2>&1; then
                xattr -dr com.apple.quarantine ''' + "${env.TF_DIR}" + '''/.terraform || true
              fi
              chmod -R +x ''' + "${env.TF_DIR}" + '''/.terraform || true
            '''
          }
        }
      }
    }

    stage('Validate & Plan (all branches)') {
      steps {
        script {
          def TF = tool name: 'terraform-1.6.6'
          withEnv([
            "TF_BIN=${TF}/terraform",
            "TF_PLUGIN_CACHE_DIR=${env.TF_PLUGIN_CACHE_DIR}",
            // безопасно пробрасываем имя KeyPair как TF_VAR
            "TF_VAR_ssh_key_name=${SSH_KEY_NAME}"
          ]) {
            sh '''
              echo "--- Planning in: ''' + "${env.TF_DIR}" + ''' ---"
              # мягкий fmt: не валим билд, если формат отличается — автоисправим
              set +e
              "$TF_BIN" -chdir=''' + "${env.TF_DIR}" + ''' fmt -check -recursive
              st=$?
              if [ $st -ne 0 ]; then
                echo "⚠️ terraform fmt нашёл несоответствия. Автоформатирую..."
                "$TF_BIN" -chdir=''' + "${env.TF_DIR}" + ''' fmt -recursive
              fi
              set -e

              "$TF_BIN" -chdir=''' + "${env.TF_DIR}" + ''' validate
              "$TF_BIN" -chdir=''' + "${env.TF_DIR}" + ''' plan -out=tfplan
            '''
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
        script {
          def TF = tool name: 'terraform-1.6.6'
          withEnv(["TF_BIN=${TF}/terraform", "TF_PLUGIN_CACHE_DIR=${env.TF_PLUGIN_CACHE_DIR}"]) {
            sh '"$TF_BIN" -chdir=' + "${env.TF_DIR}" + " apply -auto-approve tfplan"
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
        script {
          // 1) достаём IP из Terraform outputs
          def TF = tool name: 'terraform-1.6.6'
          env.APP_IP = sh(script: "\"${TF}/terraform\" -chdir='${env.TF_DIR}' output -raw public_ip", returnStdout: true).trim()
          echo "EC2 public IP: ${env.APP_IP}"
        }

        // 2) пишем inventory рядом с playbook
        dir("${env.ANSIBLE_DIR}") {
          writeFile file: 'inventory.ini', text: "[web]\n${env.APP_IP}\n"
          echo "Inventory written to ${env.ANSIBLE_DIR}/inventory.ini"
        }

        // 3) запускаем Ansible с приватным ключом из Jenkins credentials
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

// Telegram helper (без Groovy-интерполяции)
def notifyTG(String message) {
  withEnv(["MSG=${message}"]) {
    sh '''#!/bin/bash
curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d chat_id="${TELEGRAM_CHAT_ID}" \
  --data-urlencode "text=${MSG}"
'''
  }
}