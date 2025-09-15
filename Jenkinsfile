pipeline {
  agent any
  environment {
    AWS_DEFAULT_REGION = 'eu-central-1'
    TF_IN_AUTOMATION   = 'true'

    TELEGRAM_BOT_TOKEN = credentials('telegram-bot-token')
    TELEGRAM_CHAT_ID   = credentials('telegram-chat-id')

    # ИМЯ KeyPair в AWS (используем в var.ssh_key_name)
    SSH_KEY_NAME       = credentials('ec2-ssh-key')
  }
  options { timestamps() }

  stages {
    stage('Checkout') { steps { checkout scm } }

    stage('Terraform Init') {
      steps {
        dir('main') {
          sh 'terraform init -upgrade'
        }
      }
    }

    stage('Validate & Plan') {
      steps {
        dir('main') {
          sh 'terraform fmt -check'
          sh '''
            terraform validate
            terraform plan \
              -var="ssh_key_name=${SSH_KEY_NAME}" \
              -out=tfplan
          '''
        }
      }
      post {
        success { script { sendTelegram("✅ [${env.JOB_NAME}] plan OK (#${env.BUILD_NUMBER})") } }
        failure { script { sendTelegram("❌ [${env.JOB_NAME}] plan FAILED (#${env.BUILD_NUMBER})") } }
      }
    }

    stage('Manual Approval (only on main)') {
      when { allOf { branch 'main' } }
      steps {
        input message: 'Apply infrastructure?', ok: 'Apply'
      }
    }

    stage('Apply (only on main)') {
      when { allOf { branch 'main' } }
      steps {
        dir('main') {
          sh 'terraform apply -auto-approve tfplan'
        }
      }
      post {
        success { script { sendTelegram("🚀 [${env.JOB_NAME}] apply DONE (#${env.BUILD_NUMBER})") } }
        failure { script { sendTelegram("🔥 [${env.JOB_NAME}] apply FAILED (#${env.BUILD_NUMBER})") } }
      }
    }

    stage('Ansible Configure (only on main)') {
      when { allOf { branch 'main' } }
      steps {
        dir('main') {
          script {
            def IP = sh(script: "terraform output -raw public_ip", returnStdout: true).trim()
            writeFile file: 'inventory', text: "${IP}\n"
          }
        }
        dir('ansible') {
          sh 'ANSIBLE_HOST_KEY_CHECKING=false ansible -i ../main/inventory all -m ping -u ubuntu || true'
          sh 'ANSIBLE_HOST_KEY_CHECKING=false ansible-playbook -i ../main/inventory site.yml -u ubuntu'
        }
      }
      post {
        success { script { sendTelegram("🔧 [${env.JOB_NAME}] ansible DONE") } }
        failure { script { sendTelegram("🛑 [${env.JOB_NAME}] ansible FAILED") } }
      }
    }
  }
}

def sendTelegram(String msg) {
  sh """
    curl -s -X POST https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage \
      -d chat_id=${TELEGRAM_CHAT_ID} -d text="$(echo "${msg}" | sed 's/"/\\\\"/g')"
  """
}