// Jenkinsfile — INFRA (single-env), Terraform через `docker run`
// Ветки: draft-infra => только plan; main => plan -> approve -> apply -> ansible

def TF_IMAGE = 'hashicorp/terraform:1.6.6'

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
          // Монтируем текущую папку и ~/.aws внутрь контейнера
          sh """
            docker run --rm \
              -v "\$PWD":/work -w /work \
              -v "\$HOME/.aws":/root/.aws:ro \
              ${TF_IMAGE} version

            docker run --rm \
              -v "\$PWD":/work -w /work \
              -v "\$HOME/.aws":/root/.aws:ro \
              ${TF_IMAGE} init -upgrade
          """
        }
      }
    }

    stage('Validate & Plan (all branches)') {
      steps {
        dir('main') {
          sh """
            docker run --rm \
              -v "\$PWD":/work -w /work \
              -v "\$HOME/.aws":/root/.aws:ro \
              ${TF_IMAGE} fmt -check

            docker run --rm \
              -v "\$PWD":/work -w /work \
              -v "\$HOME/.aws":/root/.aws:ro \
              ${TF_IMAGE} validate

            docker run --rm \
              -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} \
              -v "\$PWD":/work -w /work \
              -v "\$HOME/.aws":/root/.aws:ro \
              ${TF_IMAGE} plan -var="ssh_key_name=${SSH_KEY_NAME}" -out=tfplan
          """
        }
      }
      post {
        success { script { notify("✅ [${env.JOB_NAME}] plan OK on ${env.BRANCH_NAME} (#${env.BUILD_NUMBER})") } }
        failure { script { notify("❌ [${env.JOB_NAME}] plan FAILED on ${env.BRANCH_NAME} (#${env.BUILD_NUMBER})") } }
      }
    }

    stage('Manual Approval (main only)') {
      when { branch 'main' }
      steps { input message: 'Apply infrastructure?', ok: 'Apply' }
    }

    stage('Apply (main only)') {
      when { branch 'main' }
      steps {
        dir('main') {
          sh """
            docker run --rm \
              -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} \
              -v "\$PWD":/work -w /work \
              -v "\$HOME/.aws":/root/.aws:ro \
              ${TF_IMAGE} apply -auto-approve tfplan
          """
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
        // Достаём IP через terraform output (тоже из контейнера)
        dir('main') {
          script {
            def IP = sh(
              script: """
                docker run --rm \
                  -v "\$PWD":/work -w /work \
                  -v "\$HOME/.aws":/root/.aws:ro \
                  ${TF_IMAGE} output -raw public_ip
              """,
              returnStdout: true
            ).trim()
            writeFile file: 'inventory', text: "${IP}\n"
            echo "Inventory generated with host: ${IP}"
          }
        }

        // Ансибл выполняем на агенте (нужен ansible на машине)
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

// Безопасная отправка в Telegram (без Groovy-интерполяции)
def notify(String message) {
  withEnv(["MSG=${message}"]) {
    sh '''#!/bin/bash
curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d chat_id="${TELEGRAM_CHAT_ID}" \
  --data-urlencode "text=${MSG}"
'''
  }
}