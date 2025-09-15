pipeline {
  agent any

  environment {
    AWS_DEFAULT_REGION = 'eu-central-1'
    TF_IN_AUTOMATION   = 'true'

    TELEGRAM_BOT_TOKEN = credentials('telegram-bot-token')
    TELEGRAM_CHAT_ID   = credentials('telegram-chat-id')

    // String credential: ИМЯ AWS KeyPair
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

    stage('Debug Repo Layout') {
      steps {
        sh '''
          echo "=== WORKSPACE ==="
          pwd
          echo "=== TREE ==="
          ls -la
          echo "=== .tf files (first 2 levels) ==="
          find . -maxdepth 2 -name "*.tf" -print || true
        '''
      }
    }

    stage('Detect Terraform directory') {
      steps {
        script {
          // ищем где лежат *.tf: сначала main/, потом infra/, потом корень
          def guess = sh(
            script: '''
              set -e
              for d in main infra .; do
                if [ -d "$d" ] && ls -1 "$d"/*.tf >/dev/null 2>&1; then
                  echo "$d"
                  exit 0
                fi
              done
              # если не нашли — попробуем найти первый каталог с .tf на глубине 2
              dir=$(dirname "$(find . -maxdepth 2 -name "*.tf" -print | head -n1)") || true
              if [ -n "$dir" ]; then
                echo "$dir"
                exit 0
              fi
              exit 1
            ''',
            returnStatus: true
          ) == 0 ? sh(script: 'echo "$?" >/dev/null; ', returnStdout: true) : null

          // Увы, принять stdout из пред. шага нельзя — сделаем отдельно, чтобы получить сам путь:
          def tfDir = sh(
            script: '''
              set -e
              for d in main infra .; do
                if [ -d "$d" ] && ls -1 "$d"/*.tf >/dev/null 2>&1; then
                  echo "$d"
                  exit 0
                fi
              done
              dir=$(dirname "$(find . -maxdepth 2 -name "*.tf" -print | head -n1)") || true
              [ -n "$dir" ] && echo "$dir" || true
            ''',
            returnStdout: true
          ).trim()

          if (!tfDir) {
            error "Не найден каталог с Terraform (.tf). Проверь структуру репозитория."
          }
          echo "Terraform directory detected: ${tfDir}"
          env.TF_DIR = tfDir
        }
      }
    }

    stage('Terraform Init') {
      steps {
        dir("${env.TF_DIR}") {
          script {
            def TF = tool name: 'terraform-1.6.6'
            withEnv(["TF_BIN=${TF}/terraform"]) {
              sh '''
                "$TF_BIN" -version
                pwd
                ls -la
                "$TF_BIN" init -upgrade
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
            // безопасно передаём секрет как TF_VAR_*, чтобы избежать Groovy interpolation warning и утечек
            withEnv([
              "TF_BIN=${TF}/terraform",
              "TF_VAR_ssh_key_name=${SSH_KEY_NAME}"
            ]) {
              sh '''
                echo "--- Planning in: $(pwd) ---"
                "$TF_BIN" fmt -check
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
            withEnv(["TF_BIN=${TF}/terraform"]) {
              sh '''
                "$TF_BIN" apply -auto-approve tfplan
              '''
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
        dir("${env.TF_DIR}") {
          script {
            def TF = tool name: 'terraform-1.6.6'
            def IP = sh(script: "\"${TF}/terraform\" output -raw public_ip", returnStdout: true).trim()
            writeFile file: 'inventory', text: "${IP}\n"
            echo "Inventory generated with host: ${IP}"
          }
        }
        // На агенте должен быть установлен ansible; если нет — скажи, дам контейнерный вариант
        dir('ansible') {
          sh 'ANSIBLE_HOST_KEY_CHECKING=false ansible -i ../${TF_DIR}/inventory all -m ping -u ubuntu || true'
          sh 'ANSIBLE_HOST_KEY_CHECKING=false ansible-playbook -i ../${TF_DIR}/inventory site.yml -u ubuntu'
        }
      }
      post {
        success { script { notifyTG("🔧 [${env.JOB_NAME}] ansible DONE on main") } }
        failure { script { notifyTG("🛑 [${env.JOB_NAME}] ansible FAILED on main") } }
      }
    }
  }
}

def notifyTG(String message) {
  withEnv(["MSG=${message}"]) {
    sh '''#!/bin/bash
curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d chat_id="${TELEGRAM_CHAT_ID}" \
  --data-urlencode "text=${MSG}"
'''
  }
}