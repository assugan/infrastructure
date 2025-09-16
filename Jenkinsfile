// Jenkinsfile — INFRA (single env). Ветки:
//   draft-infra => только plan
//   main        => plan -> manual approve -> apply -> ansible

pipeline {
  agent any

  environment {
    AWS_DEFAULT_REGION = 'eu-central-1'
    TF_IN_AUTOMATION   = 'true'

    // ПУТЬ К ТВОЕЙ ОСНОВНОЙ ИНФРЕ (как на скрине)
    TF_DIR      = 'infrastructure/main_infra'
    ANSIBLE_DIR = 'infrastructure/ansible'

    TELEGRAM_BOT_TOKEN = credentials('telegram-bot-token')
    TELEGRAM_CHAT_ID   = credentials('telegram-chat-id')
    SSH_KEY_NAME       = credentials('ec2-ssh-key')   // имя AWS KeyPair (String)

    TF_PLUGIN_CACHE_DIR = "${WORKSPACE}/.terraform.d/plugin-cache"
  }

  options {
    timestamps()
    // можно так же: skipDefaultCheckout(true) — и сделать checkout в stage вручную
  }

  stages {
    stage('Checkout (clean)') {
      steps {
        // ВАЖНО: очищаем старый мусор из workspace
        deleteDir()
        checkout scm
        sh '''
          echo "== After checkout =="
          pwd
          ls -la
          echo "== TF_DIR listing =="
          ls -la '${TF_DIR}' || true
          echo "== .tf in TF_DIR =="
          find '${TF_DIR}' -maxdepth 1 -name "*.tf" -print || true
        '''
      }
    }

    stage('Terraform Init') {
      steps {
        script {
          def TF = tool name: 'terraform-1.6.6'
          withEnv(["TF_BIN=${TF}/terraform", "TF_PLUGIN_CACHE_DIR=${env.TF_PLUGIN_CACHE_DIR}"]) {
            sh '''
              mkdir -p "$TF_PLUGIN_CACHE_DIR"
              "$TF_BIN" -chdir=''' + "${env.TF_DIR}" + ''' -version
              "$TF_BIN" -chdir=''' + "${env.TF_DIR}" + ''' init -upgrade
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
            "TF_VAR_ssh_key_name=${SSH_KEY_NAME}"
          ]) {
            sh '''
              echo "--- Planning in: ''' + "${env.TF_DIR}" + ''' ---"
              set +e
              "$TF_BIN" -chdir=''' + "${env.TF_DIR}" + ''' fmt -check -recursive
              st=$?
              [ $st -ne 0 ] && echo "⚠️ fmt mismatch → auto-fmt" && "$TF_BIN" -chdir=''' + "${env.TF_DIR}" + ''' fmt -recursive
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
          def TF = tool name: 'terraform-1.6.6'
          env.APP_IP = sh(script: "\"${TF}/terraform\" -chdir='${env.TF_DIR}' output -raw public_ip", returnStdout: true).trim()
          echo "EC2 public IP: ${env.APP_IP}"
        }
        dir("${env.ANSIBLE_DIR}") {
          writeFile file: 'inventory.ini', text: "[web]\n${env.APP_IP}\n"
          withCredentials([sshUserPrivateKey(credentialsId: 'ec2-ssh-private', keyFileVariable: 'SSH_KEY_FILE', usernameVariable: 'SSH_USER')]) {
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

def notifyTG(String message) {
  withEnv(["MSG=${message}"]) {
    sh '''#!/bin/bash
curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d chat_id="${TELEGRAM_CHAT_ID}" \
  --data-urlencode "text=${MSG}"
'''
  }
}