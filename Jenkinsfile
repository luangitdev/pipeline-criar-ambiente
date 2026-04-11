pipeline {
    agent any
    
    parameters {
        choice(
            name: 'TIPO_AMBIENTE',
            choices: ['PTF', 'PLN'],
            description: 'Tipo do ambiente (PTF ou PLN)'
        )
        choice(
            name: 'SERVIDOR',
            choices: ['GCP01', 'GCP02', 'GCP03', 'GCP-PLN'],
            description: 'Servidor de destino'
        )
        choice(
            name: 'DEPLOY_TARGET',
            choices: [
                'IMP-01:34.95.251.169',
                'PROD-01:35.247.243.102',
                'PROD-02:35.199.97.30',
                'PROD-03:34.95.176.6',
                'PROD-04:34.151.235.67',
                'PROD-05:35.247.231.213',
                'PROD-06:34.151.245.19',
                'PROD-07:35.199.65.37',
                'PROD-08:35.199.103.167',
                'PROD-09:35.199.120.245',
                'PROD-10:34.95.167.115',
                'PROD-11:34.39.155.140'
            ],
            description: 'Servidor de deploy no formato NOME:IP'
        )
        string(
            name: 'NOME_BANCO',
            defaultValue: '',
            description: 'Nome do banco de dados a ser criado',
            trim: true
        )
        string(
            name: 'VERSAO_DESEJADA',
            defaultValue: '15.13.1.0-1',
            description: 'Versão desejada do banco (ex: 15.13.1.0-1)',
            trim: true
        )
        string(
            name: 'TOMCAT_VOLUME',
            defaultValue: '',
            description: 'Nome do volume Docker do Tomcat (ex: ptf-routing_tomcat-v15_8081)',
            trim: true
        )
        string(
            name: 'APP_NAME',
            defaultValue: 'pathfind_',
            description: 'Nome final da aplicação no Tomcat',
            trim: true
        )
        string(
            name: 'APP_REPO_URL_OVERRIDE',
            defaultValue: '',
            description: 'Override técnico opcional da URL do repositório da aplicação',
            trim: true
        )
        string(
            name: 'APP_REPO_BRANCH_OVERRIDE',
            defaultValue: '',
            description: 'Override técnico opcional da branch da aplicação',
            trim: true
        )
        booleanParam(
            name: 'CRIAR_BANCO',
            defaultValue: true,
            description: 'Executar criação do banco de dados'
        )
        booleanParam(
            name: 'DEPLOY_APP',
            defaultValue: false,
            description: 'Executar deploy da aplicação'
        )
        booleanParam(
            name: 'SINCRONIZAR_UPDATES_INFRA',
            defaultValue: true,
            description: 'Buscar updates SQL no repositório de infraestrutura (Azure DevOps)'
        )
        string(
            name: 'INFRA_REPO_URL',
            defaultValue: 'https://MobiisLogistica@dev.azure.com/MobiisLogistica/Roteirizador/_git/infraestrutura',
            description: 'URL do repositório de infraestrutura que contém as migrations',
            trim: true
        )
        string(
            name: 'INFRA_REPO_BRANCH',
            defaultValue: 'master',
            description: 'Branch do repositório de infraestrutura',
            trim: true
        )
        string(
            name: 'INFRA_REPO_CREDENTIALS_ID',
            defaultValue: 'azure-credentials-luan',
            description: 'Credentials ID (username/password ou PAT) para acessar o repositório de infraestrutura',
            trim: true
        )
        text(
            name: 'DADOS_AMBIENTE',
            defaultValue: '''Endereço: Rua Capitão Luis Ramos, 200
Bairro: Vila Guilherme
Cidade: São Paulo
Estado: SP
CEP: 02066-010
Lat: -23.507212290544405
Long: -46.607500704611475
CNPJ: 09645368000181
Razao Social: AGEBRANDS''',
            description: '''Dados do ambiente no formato:
Endereço: <endereço>
Bairro: <bairro>
Cidade: <cidade>
Estado: <sigla do estado>
CEP: <cep>
Lat: <latitude>
Long: <longitude>
CNPJ: <cnpj>
Razao Social: <razão social>'''
        )
    }
    
    environment {
        PIPELINE_HOME = "${WORKSPACE}"
        SCRIPTS_PATH = "${WORKSPACE}/scripts"
        CONFIG_PATH = "${WORKSPACE}/config"
        SQL_PATH = "${WORKSPACE}/sql"
        DADOS_PATH = "${WORKSPACE}/dados"
        TEMPLATES_PATH = "${WORKSPACE}/templates"
        
        // Configurações por ambiente
        DB_PORT = '5432'
        
        // Log level
        LOG_LEVEL = 'INFO'
    }
    
    stages {
        stage('🔍 Validação de Parâmetros') {
            steps {
                script {
                    echo "🚀 ===== PIPELINE CRIAR AMBIENTE ====="
                    echo "📋 Parâmetros recebidos:"
                    echo "   - Tipo Ambiente: ${params.TIPO_AMBIENTE}"
                    echo "   - Servidor: ${params.SERVIDOR}"
                    echo "   - Deploy Target: ${params.DEPLOY_TARGET}"
                    echo "   - Nome Banco: ${params.NOME_BANCO}"
                    echo "   - Versão: ${params.VERSAO_DESEJADA}"
                    echo "   - Criar Banco: ${params.CRIAR_BANCO}"
                    echo "   - Deploy App: ${params.DEPLOY_APP}"
                    echo "   - Tomcat Volume: ${params.TOMCAT_VOLUME}"
                    echo "   - App Name: ${params.APP_NAME}"
                    echo "   - Sincronizar Updates Infra: ${params.SINCRONIZAR_UPDATES_INFRA}"
                    echo "======================================="
                    
                    // Validações básicas
                    if (!params.NOME_BANCO || params.NOME_BANCO.trim() == '') {
                        error("❌ Nome do banco é obrigatório!")
                    }
                    
                    if (!params.VERSAO_DESEJADA || params.VERSAO_DESEJADA.trim() == '') {
                        error("❌ Versão desejada é obrigatória!")
                    }
                    
                    // Definir nome customizado para o build
                    currentBuild.displayName = "#${BUILD_NUMBER} - ${params.NOME_BANCO}"
                    currentBuild.description = "Ambiente: ${params.TIPO_AMBIENTE} | DB: ${params.SERVIDOR} | Deploy: ${params.DEPLOY_TARGET}"
                    
                    if (params.DEPLOY_APP) {
                        if (!params.DEPLOY_TARGET || params.DEPLOY_TARGET.trim() == '') {
                            error("❌ DEPLOY_TARGET é obrigatório quando deploy está habilitado!")
                        }
                        if (!params.TOMCAT_VOLUME || params.TOMCAT_VOLUME.trim() == '') {
                            error("❌ TOMCAT_VOLUME é obrigatório quando deploy está habilitado!")
                        }
                        if (!params.APP_NAME || params.APP_NAME.trim() == '') {
                            error("❌ APP_NAME é obrigatório quando deploy está habilitado!")
                        }

                        def parts = params.DEPLOY_TARGET.split(':')
                        if (parts.size() != 2 || !parts[0].trim() || !parts[1].trim()) {
                            error("❌ DEPLOY_TARGET inválido. Use o formato NOME:IP.")
                        }

                        def ip = parts[1].trim()
                        if (!(ip ==~ /^\d{1,3}(\.\d{1,3}){3}$/)) {
                            error("❌ DEPLOY_TARGET inválido. IP fora do padrão esperado.")
                        }

                        env.DEPLOY_SERVER_NAME = parts[0].trim()
                        env.DEPLOY_SERVER_IP = ip
                    } else {
                        env.DEPLOY_SERVER_NAME = ''
                        env.DEPLOY_SERVER_IP = ''
                    }

                    if (params.CRIAR_BANCO && params.SINCRONIZAR_UPDATES_INFRA && (!params.INFRA_REPO_CREDENTIALS_ID || params.INFRA_REPO_CREDENTIALS_ID.trim() == '')) {
                        error("❌ INFRA_REPO_CREDENTIALS_ID é obrigatório quando a sincronização de updates está habilitada!")
                    }

                    if (params.DEPLOY_APP && params.CRIAR_BANCO) {
                        def minByAmbiente = [
                            'PTF': '15.12.0.3-43',
                            'PLN': '9.0.0.0-0'
                        ]

                        def normalizeVersion = { String versionValue ->
                            def matcher = (versionValue =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)-(\d+)$/)
                            if (!matcher.matches()) {
                                error("❌ VERSAO_DESEJADA inválida: '${versionValue}'. Use N.N.N.N-N.")
                            }
                            return [
                                matcher[0][1].toInteger(),
                                matcher[0][2].toInteger(),
                                matcher[0][3].toInteger(),
                                matcher[0][4].toInteger(),
                                matcher[0][5].toInteger()
                            ]
                        }

                        def isLowerThan = { left, right ->
                            for (int i = 0; i < left.size(); i++) {
                                if (left[i] < right[i]) {
                                    return true
                                }
                                if (left[i] > right[i]) {
                                    return false
                                }
                            }
                            return false
                        }

                        def minVersion = minByAmbiente[params.TIPO_AMBIENTE]
                        def desiredTokens = normalizeVersion(params.VERSAO_DESEJADA.trim())
                        def minTokens = normalizeVersion(minVersion)

                        if (isLowerThan(desiredTokens, minTokens)) {
                            error("❌ VERSAO_DESEJADA (${params.VERSAO_DESEJADA}) é menor que o piso permitido para ${params.TIPO_AMBIENTE}: ${minVersion}.")
                        }
                    }
                    
                    // Carregar configurações
                    env.DB_HOST = sh(
                        script: "${SCRIPTS_PATH}/get_db_host.sh ${params.SERVIDOR.toLowerCase()}",
                        returnStdout: true
                    ).trim()

                    def appRepoDefaults = [
                        'PTF': [url: 'https://MobiisLogistica@dev.azure.com/MobiisLogistica/Roteirizador/_git/pathfind', branch: 'mvp'],
                        'PLN': [url: 'https://MobiisLogistica@dev.azure.com/MobiisLogistica/Planner%20e%20Torre/_git/planner', branch: 'v8']
                    ]
                    def selectedRepo = appRepoDefaults[params.TIPO_AMBIENTE]
                    env.APP_REPO_URL = (params.APP_REPO_URL_OVERRIDE?.trim()) ? params.APP_REPO_URL_OVERRIDE.trim() : selectedRepo.url
                    env.APP_REPO_BRANCH = (params.APP_REPO_BRANCH_OVERRIDE?.trim()) ? params.APP_REPO_BRANCH_OVERRIDE.trim() : selectedRepo.branch
                    
                    echo "✅ Validação concluída. DB Host: ${env.DB_HOST}"
                    if (params.DEPLOY_APP) {
                        echo "✅ Deploy Target resolvido: ${env.DEPLOY_SERVER_NAME} (${env.DEPLOY_SERVER_IP})"
                        echo "✅ Repositório da aplicação: ${env.APP_REPO_URL} [branch: ${env.APP_REPO_BRANCH}]"
                    }
                }
            }
        }
        
        stage('📁 Preparação do Ambiente') {
            steps {
                script {
                    echo "🔧 Preparando ambiente de trabalho..."
                    
                    // Criar diretórios temporários
                    sh """
                        mkdir -p ${WORKSPACE}/temp
                        mkdir -p ${WORKSPACE}/logs
                        chmod +x ${SCRIPTS_PATH}/*.sh
                    """
                    
                    // Criar arquivo dados.txt a partir do parâmetro ou usar arquivo padrão
                    if (params.DADOS_AMBIENTE && params.DADOS_AMBIENTE.trim() != '') {
                        // Usar dados fornecidos como parâmetro
                        writeFile file: "${WORKSPACE}/temp/dados.txt", text: params.DADOS_AMBIENTE
                        echo "✅ Dados do ambiente criados a partir do parâmetro"
                        echo "📄 Conteúdo:"
                        sh "cat ${WORKSPACE}/temp/dados.txt"
                    } else {
                        // Usar arquivo padrão se nenhum dado foi fornecido
                        sh """
                            if [ -f "${DADOS_PATH}/${params.TIPO_AMBIENTE}/dados.txt" ]; then
                                cp "${DADOS_PATH}/${params.TIPO_AMBIENTE}/dados.txt" ${WORKSPACE}/temp/
                                echo "✅ Dados do ambiente ${params.TIPO_AMBIENTE} copiados do arquivo padrão"
                            else
                                echo "❌ Nenhum dado fornecido e arquivo padrão não encontrado!"
                                exit 1
                            fi
                        """
                    }
                }
            }
        }

        stage('🔄 Sincronização de Migrations') {
            when {
                expression { params.CRIAR_BANCO }
            }
            steps {
                script {
                    def tipoAmbiente = params.TIPO_AMBIENTE.toLowerCase()
                    def outputDir = "${WORKSPACE}/temp/sql_updates/${tipoAmbiente}/updates"

                    sh """
                        mkdir -p "${outputDir}"
                        rm -f "${outputDir}"/*.sql
                    """

                    if (params.SINCRONIZAR_UPDATES_INFRA) {
                        echo "🔄 Sincronizando updates do repositório de infraestrutura..."

                        withCredentials([
                            usernamePassword(
                                credentialsId: params.INFRA_REPO_CREDENTIALS_ID,
                                usernameVariable: 'INFRA_GIT_USER',
                                passwordVariable: 'INFRA_GIT_TOKEN'
                            )
                        ]) {
                            sh """
                                ${SCRIPTS_PATH}/fetch_updates.sh \\
                                    --tipo-ambiente "${tipoAmbiente}" \\
                                    --repo-url "${params.INFRA_REPO_URL}" \\
                                    --repo-branch "${params.INFRA_REPO_BRANCH}" \\
                                    --work-dir "${WORKSPACE}/temp/infra_repo_cache" \\
                                    --output-dir "${outputDir}" \\
                                    --git-username "${INFRA_GIT_USER}" \\
                                    --git-token "${INFRA_GIT_TOKEN}"
                            """
                        }
                    } else {
                        echo "ℹ️ Sincronização desabilitada. Usando updates locais do repositório atual."
                        sh """
                            cp ${SQL_PATH}/${tipoAmbiente}/updates/*.sql "${outputDir}/" 2>/dev/null || true
                        """
                    }

                    sh """
                        echo "📋 Updates preparados para execução:"
                        ls -1 "${outputDir}"/*.sql 2>/dev/null || echo "Nenhum update disponível"
                    """
                }
            }
        }
        
        stage('🗄️ Criação do Banco de Dados') {
            when {
                expression { params.CRIAR_BANCO }
            }
            steps {
                script {
                    echo "🗄️ Iniciando criação do banco de dados..."
                    
                    withCredentials([
                        string(credentialsId: 'BASTION_HOST', variable: 'BASTION_HOST'),
                        string(credentialsId: 'BASTION_USER', variable: 'BASTION_USER'),
                        string(credentialsId: 'db-pathfind-user', variable: 'DB_USER'),
                        string(credentialsId: 'db-pathfind-password', variable: 'DB_PASSWORD'),
                        sshUserPrivateKey(credentialsId: 'SSH_PRIVATE_KEY', keyFileVariable: 'SSH_KEY', passphraseVariable: 'SSH_PASSPHRASE')
                    ]) {
                        def createResult = sh(
                            script: """
                                # Criar script temporário para ssh-add
                                cat > /tmp/ssh-add-script-\$\$.sh << 'EOF'
#!/bin/bash
echo "\$SSH_PASSPHRASE"
EOF
                                chmod +x /tmp/ssh-add-script-\$\$.sh
                                
                                # Configurar ssh-agent temporário
                                eval \$(ssh-agent -s)
                                
                                # Adicionar chave com passphrase
                                DISPLAY=:0 SSH_ASKPASS=/tmp/ssh-add-script-\$\$.sh ssh-add \${SSH_KEY} < /dev/null
                                
                                # Criar diretório no bastion
                                ssh -o StrictHostKeyChecking=no \${BASTION_USER}@\${BASTION_HOST} "mkdir -p /tmp/pipeline-${BUILD_NUMBER}"
                                
                                # Copiar arquivos necessários
                                scp -o StrictHostKeyChecking=no -r ${WORKSPACE}/scripts/ \${BASTION_USER}@\${BASTION_HOST}:/tmp/pipeline-${BUILD_NUMBER}/
                                scp -o StrictHostKeyChecking=no -r ${WORKSPACE}/sql/ \${BASTION_USER}@\${BASTION_HOST}:/tmp/pipeline-${BUILD_NUMBER}/
                                scp -o StrictHostKeyChecking=no -r ${WORKSPACE}/dados/ \${BASTION_USER}@\${BASTION_HOST}:/tmp/pipeline-${BUILD_NUMBER}/
                                scp -o StrictHostKeyChecking=no -r ${WORKSPACE}/temp/ \${BASTION_USER}@\${BASTION_HOST}:/tmp/pipeline-${BUILD_NUMBER}/
                                
                                # Executar scripts no bastion
                                ssh -o StrictHostKeyChecking=no \${BASTION_USER}@\${BASTION_HOST} << 'ENDCREATE'
cd /tmp/pipeline-${BUILD_NUMBER}
chmod +x scripts/*.sh

# Debug - mostrar variáveis
echo "=== DEBUG - Variáveis do Pipeline ==="
echo "TIPO_AMBIENTE: ${params.TIPO_AMBIENTE}"
echo "SERVIDOR: ${params.SERVIDOR}"
echo "NOME_BANCO: ${params.NOME_BANCO}"
echo "VERSAO_DESEJADA: ${params.VERSAO_DESEJADA}"
echo "DB_HOST: ${env.DB_HOST}"
echo "DB_PORT: ${env.DB_PORT}"
echo "DB_USER: ${DB_USER}"
echo "DB_PASSWORD: [MASKED]"
echo "WORKSPACE: /tmp/pipeline-${BUILD_NUMBER}"
echo "UPDATES_DIR: /tmp/pipeline-${BUILD_NUMBER}/temp/sql_updates/${params.TIPO_AMBIENTE.toLowerCase()}/updates"
echo "================================="

# Executar criação do banco
./scripts/create_database.sh \\
    --tipo-ambiente "${params.TIPO_AMBIENTE.toLowerCase()}" \\
    --servidor "${params.SERVIDOR}" \\
    --nome-banco "${params.NOME_BANCO}" \\
    --versao-desejada "${params.VERSAO_DESEJADA}" \\
    --db-host "${env.DB_HOST}" \\
    --db-port "${env.DB_PORT}" \\
    --db-user "${DB_USER}" \\
    --db-password "${DB_PASSWORD}" \\
    --workspace "/tmp/pipeline-${BUILD_NUMBER}" \\
    --updates-dir "/tmp/pipeline-${BUILD_NUMBER}/temp/sql_updates/${params.TIPO_AMBIENTE.toLowerCase()}/updates"

# Verificar se houve erro na criação
if [ \$? -ne 0 ]; then
    echo "❌ ERRO: Falha na criação do banco de dados!"
    exit 1
fi

echo "✅ Criação do banco concluída com sucesso!"
ENDCREATE
                                
                                # Capturar exit code do SSH
                                SSH_EXIT_CODE=\$?
                                
                                # Limpar
                                ssh-agent -k
                                rm -f /tmp/ssh-add-script-\$\$.sh
                                
                                # Verificar se houve erro
                                if [ \$SSH_EXIT_CODE -ne 0 ]; then
                                    echo "❌ ERRO: Script remoto falhou com código: \$SSH_EXIT_CODE"
                                    exit \$SSH_EXIT_CODE
                                fi
                            """,
                            returnStatus: true
                        )
                        
                        if (createResult != 0) {
                            error("❌ Falha na criação do banco de dados! Exit code: ${createResult}")
                        }
                        
                        echo "✅ Banco de dados ${params.NOME_BANCO} criado com sucesso!"
                    }
                }
            }
        }
        
        stage('🚀 Deploy da Aplicação') {
            when {
                expression { params.DEPLOY_APP }
            }
            steps {
                script {
                    echo "🚀 Iniciando deploy da aplicação..."
                    
                    withCredentials([
                        string(credentialsId: 'BASTION_HOST', variable: 'BASTION_HOST'),
                        string(credentialsId: 'BASTION_USER', variable: 'BASTION_USER'),
                        string(credentialsId: 'infra-sudo-pswd', variable: 'INFRA_SUDO_PASSWORD'),
                        usernamePassword(credentialsId: 'azure-credentials-luan', usernameVariable: 'APP_GIT_USER', passwordVariable: 'APP_GIT_TOKEN'),
                        sshUserPrivateKey(credentialsId: 'SSH_PRIVATE_KEY', keyFileVariable: 'SSH_KEY', passphraseVariable: 'SSH_PASSPHRASE'),
                        sshUserPrivateKey(credentialsId: 'ssh-credentials', keyFileVariable: 'DEPLOY_SSH_KEY', passphraseVariable: 'DEPLOY_SSH_PASSPHRASE')
                    ]) {
                        def deployResult = sh(
                            script: """
                                ARTIFACT_DIR="${WORKSPACE}/temp/app_artifact"
                                ARTIFACT_WAR="\${ARTIFACT_DIR}/app.war"
                                mkdir -p "\${ARTIFACT_DIR}"

                                echo "📦 Construindo WAR da aplicação a partir do repositório ${env.APP_REPO_URL}"
                                echo "🔖 Aplicando versão da app igual a VERSAO_DESEJADA: ${params.VERSAO_DESEJADA}"
                                ${SCRIPTS_PATH}/build_app_artifact.sh \\
                                    --tipo-ambiente "${params.TIPO_AMBIENTE.toLowerCase()}" \\
                                    --repo-url "${env.APP_REPO_URL}" \\
                                    --repo-branch "${env.APP_REPO_BRANCH}" \\
                                    --app-version "${params.VERSAO_DESEJADA}" \\
                                    --output-war "\${ARTIFACT_WAR}" \\
                                    --workspace "${WORKSPACE}" \\
                                    --git-username "\${APP_GIT_USER}" \\
                                    --git-token "\${APP_GIT_TOKEN}"

                                if [ ! -f "\${ARTIFACT_WAR}" ]; then
                                    echo "❌ ERRO: WAR final não encontrado em \${ARTIFACT_WAR}"
                                    exit 1
                                fi

                                # Criar script temporário para ssh-add
                                cat > /tmp/ssh-add-script-\$\$.sh << 'EOF'
#!/bin/bash
echo "\$SSH_PASSPHRASE"
EOF
                                chmod +x /tmp/ssh-add-script-\$\$.sh
                                
                                # Configurar ssh-agent temporário
                                eval \$(ssh-agent -s)
                                
                                # Adicionar chave com passphrase
                                DISPLAY=:0 SSH_ASKPASS=/tmp/ssh-add-script-\$\$.sh ssh-add \${SSH_KEY} < /dev/null
                                
                                # Criar diretório no bastion e copiar arquivos necessários
                                ssh -o StrictHostKeyChecking=no \${BASTION_USER}@\${BASTION_HOST} "mkdir -p /tmp/pipeline-${BUILD_NUMBER}"
                                scp -o StrictHostKeyChecking=no -r ${WORKSPACE}/scripts/ \${BASTION_USER}@\${BASTION_HOST}:/tmp/pipeline-${BUILD_NUMBER}/
                                scp -o StrictHostKeyChecking=no "\${ARTIFACT_WAR}" \${BASTION_USER}@\${BASTION_HOST}:/tmp/pipeline-${BUILD_NUMBER}/app.war
                                scp -o StrictHostKeyChecking=no "\${DEPLOY_SSH_KEY}" \${BASTION_USER}@\${BASTION_HOST}:/tmp/pipeline-${BUILD_NUMBER}/.deploy_ssh_key
                                ssh -o StrictHostKeyChecking=no \${BASTION_USER}@\${BASTION_HOST} "chmod 600 /tmp/pipeline-${BUILD_NUMBER}/.deploy_ssh_key"
                                printf '%s' "\${INFRA_SUDO_PASSWORD}" > "${WORKSPACE}/temp/.infra_sudo_password"
                                scp -o StrictHostKeyChecking=no "${WORKSPACE}/temp/.infra_sudo_password" \${BASTION_USER}@\${BASTION_HOST}:/tmp/pipeline-${BUILD_NUMBER}/.infra_sudo_password
                                rm -f "${WORKSPACE}/temp/.infra_sudo_password"
                                
                                # Executar deploy no bastion
                                ssh -A -o StrictHostKeyChecking=no \${BASTION_USER}@\${BASTION_HOST} << 'ENDDEPLOY'
cd /tmp/pipeline-${BUILD_NUMBER}
chmod +x scripts/*.sh
trap 'rm -f /tmp/pipeline-${BUILD_NUMBER}/.infra_sudo_password /tmp/pipeline-${BUILD_NUMBER}/.deploy_ssh_key' EXIT
SUDO_PASSWORD_REMOTE="\$(cat /tmp/pipeline-${BUILD_NUMBER}/.infra_sudo_password)"

# Executar deploy da aplicação
./scripts/deploy_application.sh \\
    --war-file "/tmp/pipeline-${BUILD_NUMBER}/app.war" \\
    --nome-banco "${params.NOME_BANCO}" \\
    --db-host "${env.DB_HOST}" \\
    --tipo-ambiente "${params.TIPO_AMBIENTE.toLowerCase()}" \\
    --deploy-server-name "${env.DEPLOY_SERVER_NAME}" \\
    --deploy-server-ip "${env.DEPLOY_SERVER_IP}" \\
    --tomcat-volume "${params.TOMCAT_VOLUME}" \\
    --app-name "${params.APP_NAME}" \\
    --ssh-key-file "/tmp/pipeline-${BUILD_NUMBER}/.deploy_ssh_key" \\
    --workspace "/tmp/pipeline-${BUILD_NUMBER}" \\
    --sudo-password "\${SUDO_PASSWORD_REMOTE}"

# Verificar se houve erro no deploy
if [ \$? -ne 0 ]; then
    echo "❌ ERRO: Falha no deploy da aplicação!"
    exit 1
fi

echo "✅ Deploy da aplicação concluído com sucesso!"
ENDDEPLOY
                                
                                # Capturar exit code do SSH
                                DEPLOY_EXIT_CODE=\$?
                                
                                # Limpar
                                ssh-agent -k
                                rm -f /tmp/ssh-add-script-\$\$.sh
                                
                                # Verificar se houve erro
                                if [ \$DEPLOY_EXIT_CODE -ne 0 ]; then
                                    echo "❌ ERRO: Deploy falhou com código: \$DEPLOY_EXIT_CODE"
                                    exit \$DEPLOY_EXIT_CODE
                                fi
                            """,
                            returnStatus: true
                        )
                        
                        if (deployResult != 0) {
                            error("❌ Falha no deploy da aplicação! Exit code: ${deployResult}")
                        }
                        
                        echo "✅ Deploy da aplicação concluído com sucesso!"
                    }
                }
            }
        }
        
        stage('✅ Verificação Final') {
            steps {
                script {
                    echo "🔍 Executando verificações finais..."
                    
                    withCredentials([
                        string(credentialsId: 'BASTION_HOST', variable: 'BASTION_HOST'),
                        string(credentialsId: 'BASTION_USER', variable: 'BASTION_USER'),
                        string(credentialsId: 'infra-sudo-pswd', variable: 'INFRA_SUDO_PASSWORD'),
                        string(credentialsId: 'db-pathfind-user', variable: 'DB_USER'),
                        string(credentialsId: 'db-pathfind-password', variable: 'DB_PASSWORD'),
                        sshUserPrivateKey(credentialsId: 'SSH_PRIVATE_KEY', keyFileVariable: 'SSH_KEY', passphraseVariable: 'SSH_PASSPHRASE'),
                        sshUserPrivateKey(credentialsId: 'ssh-credentials', keyFileVariable: 'DEPLOY_SSH_KEY', passphraseVariable: 'DEPLOY_SSH_PASSPHRASE')
                    ]) {
                        sh """
                            # Criar script temporário para ssh-add
                            cat > /tmp/ssh-add-script-\$\$.sh << 'EOF'
#!/bin/bash
echo "\$SSH_PASSPHRASE"
EOF
                            chmod +x /tmp/ssh-add-script-\$\$.sh
                            
                            # Configurar ssh-agent temporário
                            eval \$(ssh-agent -s)
                            
                            # Adicionar chave com passphrase
                            DISPLAY=:0 SSH_ASKPASS=/tmp/ssh-add-script-\$\$.sh ssh-add \${SSH_KEY} < /dev/null

                            # Garantir diretório e scripts no bastion
                            ssh -o StrictHostKeyChecking=no \${BASTION_USER}@\${BASTION_HOST} "mkdir -p /tmp/pipeline-${BUILD_NUMBER}"
                            scp -o StrictHostKeyChecking=no -r ${WORKSPACE}/scripts/ \${BASTION_USER}@\${BASTION_HOST}:/tmp/pipeline-${BUILD_NUMBER}/
                            scp -o StrictHostKeyChecking=no "\${DEPLOY_SSH_KEY}" \${BASTION_USER}@\${BASTION_HOST}:/tmp/pipeline-${BUILD_NUMBER}/.deploy_ssh_key
                            ssh -o StrictHostKeyChecking=no \${BASTION_USER}@\${BASTION_HOST} "chmod 600 /tmp/pipeline-${BUILD_NUMBER}/.deploy_ssh_key"
                            printf '%s' "\${DB_USER}" > "${WORKSPACE}/temp/.db_user"
                            printf '%s' "\${DB_PASSWORD}" > "${WORKSPACE}/temp/.db_password"
                            printf '%s' "\${INFRA_SUDO_PASSWORD}" > "${WORKSPACE}/temp/.infra_sudo_password"
                            scp -o StrictHostKeyChecking=no "${WORKSPACE}/temp/.db_user" \${BASTION_USER}@\${BASTION_HOST}:/tmp/pipeline-${BUILD_NUMBER}/.db_user
                            scp -o StrictHostKeyChecking=no "${WORKSPACE}/temp/.db_password" \${BASTION_USER}@\${BASTION_HOST}:/tmp/pipeline-${BUILD_NUMBER}/.db_password
                            scp -o StrictHostKeyChecking=no "${WORKSPACE}/temp/.infra_sudo_password" \${BASTION_USER}@\${BASTION_HOST}:/tmp/pipeline-${BUILD_NUMBER}/.infra_sudo_password
                            rm -f "${WORKSPACE}/temp/.db_user" "${WORKSPACE}/temp/.db_password" "${WORKSPACE}/temp/.infra_sudo_password"
                            
                            # Executar verificações no bastion
                            ssh -A -o StrictHostKeyChecking=no \${BASTION_USER}@\${BASTION_HOST} << 'ENDVERIFY'
cd /tmp/pipeline-${BUILD_NUMBER}
chmod +x scripts/*.sh
trap 'rm -f /tmp/pipeline-${BUILD_NUMBER}/.db_user /tmp/pipeline-${BUILD_NUMBER}/.db_password /tmp/pipeline-${BUILD_NUMBER}/.infra_sudo_password /tmp/pipeline-${BUILD_NUMBER}/.deploy_ssh_key' EXIT
DB_USER_REMOTE="\$(cat /tmp/pipeline-${BUILD_NUMBER}/.db_user)"
DB_PASSWORD_REMOTE="\$(cat /tmp/pipeline-${BUILD_NUMBER}/.db_password)"
SUDO_PASSWORD_REMOTE="\$(cat /tmp/pipeline-${BUILD_NUMBER}/.infra_sudo_password)"

echo "🔍 Executando verificações..."

# Verificar banco se foi criado
if [ "${params.CRIAR_BANCO}" = "true" ]; then
    ./scripts/verify_database.sh \\
        --nome-banco "${params.NOME_BANCO}" \\
        --db-host "${env.DB_HOST}" \\
        --db-port "${env.DB_PORT}" \\
        --db-user "\${DB_USER_REMOTE}" \\
        --db-password "\${DB_PASSWORD_REMOTE}"
fi

# Verificar deploy se foi executado
if [ "${params.DEPLOY_APP}" = "true" ]; then
    ./scripts/verify_deployment.sh \\
        --deploy-server-name "${env.DEPLOY_SERVER_NAME}" \\
        --deploy-server-ip "${env.DEPLOY_SERVER_IP}" \\
        --tomcat-volume "${params.TOMCAT_VOLUME}" \\
        --app-name "${params.APP_NAME}" \\
        --ssh-key-file "/tmp/pipeline-${BUILD_NUMBER}/.deploy_ssh_key" \\
        --sudo-password "\${SUDO_PASSWORD_REMOTE}"
fi

# Verificar se todas as verificações passaram
if [ \$? -ne 0 ]; then
    echo "❌ ERRO: Verificações falharam!"
    exit 1
fi

echo "✅ Todas as verificações concluídas com sucesso!"
ENDVERIFY
                            
                            # Capturar exit code do SSH
                            VERIFY_EXIT_CODE=\$?
                            
                            # Limpar
                            ssh-agent -k
                            rm -f /tmp/ssh-add-script-\$\$.sh
                            
                            # Verificar se houve erro na verificação
                            if [ \$VERIFY_EXIT_CODE -ne 0 ]; then
                                echo "❌ ERRO: Verificações falharam com código: \$VERIFY_EXIT_CODE"
                                exit \$VERIFY_EXIT_CODE
                            fi
                        """
                    }
                    
                    echo "✅ Todas as verificações foram concluídas com sucesso!"
                }
            }
        }
    }
    
    post {
        always {
            script {
                echo "🧹 Executando limpeza..."
                
                // Arquivar logs
                if (fileExists("${WORKSPACE}/logs")) {
                    archiveArtifacts artifacts: 'logs/**/*', allowEmptyArchive: true
                }
                
                // Limpar arquivos temporários sensíveis
                sh """
                    echo "🧹 Removendo SQL updates copiados localmente..."
                    rm -rf "${WORKSPACE}/temp/sql_updates" || true
                    rm -rf ${WORKSPACE}/temp
                    find ${WORKSPACE} -name "*.tmp" -delete 2>/dev/null || true
                """
                
                // Limpar diretório temporário no bastion
                try {
                    withCredentials([
                        string(credentialsId: 'BASTION_HOST', variable: 'BASTION_HOST'),
                        string(credentialsId: 'BASTION_USER', variable: 'BASTION_USER'),
                        sshUserPrivateKey(credentialsId: 'SSH_PRIVATE_KEY', keyFileVariable: 'SSH_KEY', passphraseVariable: 'SSH_PASSPHRASE')
                    ]) {
                        sh """
                            # Criar script temporário para ssh-add
                            cat > /tmp/ssh-add-script-\$\$.sh << 'EOF'
#!/bin/bash
echo "\$SSH_PASSPHRASE"
EOF
                            chmod +x /tmp/ssh-add-script-\$\$.sh
                            
                            # Configurar ssh-agent temporário
                            eval \$(ssh-agent -s)
                            
                            # Adicionar chave com passphrase
                            DISPLAY=:0 SSH_ASKPASS=/tmp/ssh-add-script-\$\$.sh ssh-add \${SSH_KEY} < /dev/null
                            
                            # Limpar diretório no bastion
                            ssh -o StrictHostKeyChecking=no \${BASTION_USER}@\${BASTION_HOST} "rm -rf /tmp/pipeline-${BUILD_NUMBER}"
                            
                            # Limpar
                            ssh-agent -k
                            rm -f /tmp/ssh-add-script-\$\$.sh
                        """
                    }
                } catch (Exception e) {
                    echo "⚠️ Erro na limpeza do bastion: ${e.getMessage()}"
                }
            }
        }
        
        success {
            echo """
🎉 ===== PIPELINE CONCLUÍDO COM SUCESSO! =====
📋 Resumo:
   - Ambiente: ${params.TIPO_AMBIENTE}
   - Servidor: ${params.SERVIDOR}
   - Deploy Target: ${params.DEPLOY_TARGET}
   - Banco: ${params.NOME_BANCO}
   - Versão: ${params.VERSAO_DESEJADA}
   - Criou Banco: ${params.CRIAR_BANCO ? 'Sim' : 'Não'}
   - Deploy App: ${params.DEPLOY_APP ? 'Sim' : 'Não'}
   - Tomcat Volume: ${params.TOMCAT_VOLUME}
   - App Name: ${params.APP_NAME}
=============================================
            """
        }
        
        failure {
            echo """
❌ ===== PIPELINE FALHOU! =====
📋 Verifique os logs para mais detalhes.
Parâmetros utilizados:
   - Ambiente: ${params.TIPO_AMBIENTE}
   - Servidor: ${params.SERVIDOR}
   - Deploy Target: ${params.DEPLOY_TARGET}
   - Banco: ${params.NOME_BANCO}
==============================
            """
        }
    }
}
