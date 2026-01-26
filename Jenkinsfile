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
            name: 'WAR_FILE_PATH',
            defaultValue: '',
            description: 'Caminho para o arquivo .war (opcional)',
            trim: true
        )
        string(
            name: 'DEPLOY_PATH',
            defaultValue: '/opt/applications',
            description: 'Caminho base para deploy da aplicação',
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
                    echo "   - Nome Banco: ${params.NOME_BANCO}"
                    echo "   - Versão: ${params.VERSAO_DESEJADA}"
                    echo "   - Criar Banco: ${params.CRIAR_BANCO}"
                    echo "   - Deploy App: ${params.DEPLOY_APP}"
                    echo "======================================="
                    
                    // Validações básicas
                    if (!params.NOME_BANCO || params.NOME_BANCO.trim() == '') {
                        error("❌ Nome do banco é obrigatório!")
                    }
                    
                    if (!params.VERSAO_DESEJADA || params.VERSAO_DESEJADA.trim() == '') {
                        error("❌ Versão desejada é obrigatória!")
                    }
                    
                    if (params.DEPLOY_APP && (!params.WAR_FILE_PATH || params.WAR_FILE_PATH.trim() == '')) {
                        error("❌ Caminho do arquivo .war é obrigatório quando deploy está habilitado!")
                    }
                    
                    // Carregar configurações
                    env.DB_HOST = sh(
                        script: "${SCRIPTS_PATH}/get_db_host.sh ${params.SERVIDOR}",
                        returnStdout: true
                    ).trim()
                    
                    echo "✅ Validação concluída. DB Host: ${env.DB_HOST}"
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
echo "================================="

# Executar criação do banco
./scripts/create_database.sh \\
    --tipo-ambiente "${params.TIPO_AMBIENTE}" \\
    --servidor "${params.SERVIDOR}" \\
    --nome-banco "${params.NOME_BANCO}" \\
    --versao-desejada "${params.VERSAO_DESEJADA}" \\
    --db-host "${env.DB_HOST}" \\
    --db-port "${env.DB_PORT}" \\
    --db-user "${DB_USER}" \\
    --db-password "${DB_PASSWORD}" \\
    --workspace "/tmp/pipeline-${BUILD_NUMBER}"

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
                        sshUserPrivateKey(credentialsId: 'SSH_PRIVATE_KEY', keyFileVariable: 'SSH_KEY', passphraseVariable: 'SSH_PASSPHRASE')
                    ]) {
                        def deployResult = sh(
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
                                
                                # Criar diretório no bastion se não existe
                                ssh -o StrictHostKeyChecking=no \${BASTION_USER}@\${BASTION_HOST} "mkdir -p /tmp/pipeline-${BUILD_NUMBER}"
                                
                                # Copiar WAR file se necessário
                                if [ ! -z "${params.WAR_FILE_PATH}" ]; then
                                    scp -o StrictHostKeyChecking=no "${params.WAR_FILE_PATH}" \${BASTION_USER}@\${BASTION_HOST}:/tmp/pipeline-${BUILD_NUMBER}/
                                fi
                                
                                # Executar deploy no bastion
                                ssh -o StrictHostKeyChecking=no \${BASTION_USER}@\${BASTION_HOST} << 'ENDDEPLOY'
cd /tmp/pipeline-${BUILD_NUMBER}

# Executar deploy da aplicação
./scripts/deploy_application.sh \\
    --war-file "/tmp/pipeline-${BUILD_NUMBER}/\$(basename ${params.WAR_FILE_PATH})" \\
    --deploy-path "${params.DEPLOY_PATH}" \\
    --nome-banco "${params.NOME_BANCO}" \\
    --tipo-ambiente "${params.TIPO_AMBIENTE}" \\
    --servidor "${params.SERVIDOR}" \\
    --workspace "/tmp/pipeline-${BUILD_NUMBER}"

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
                        string(credentialsId: 'db-pathfind-user', variable: 'DB_USER'),
                        string(credentialsId: 'db-pathfind-password', variable: 'DB_PASSWORD'),
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
                            
                            # Executar verificações no bastion
                            ssh -o StrictHostKeyChecking=no \${BASTION_USER}@\${BASTION_HOST} << 'ENDVERIFY'
cd /tmp/pipeline-${BUILD_NUMBER}

echo "🔍 Executando verificações..."

# Verificar banco se foi criado
if [ "${params.CRIAR_BANCO}" = "true" ]; then
    ./scripts/verify_database.sh \\
        --nome-banco "${params.NOME_BANCO}" \\
        --db-host "${env.DB_HOST}" \\
        --db-port "${env.DB_PORT}" \\
        --db-user "${DB_USER}" \\
        --db-password "${DB_PASSWORD}"
fi

# Verificar deploy se foi executado
if [ "${params.DEPLOY_APP}" = "true" ]; then
    ./scripts/verify_deployment.sh \\
        --deploy-path "${params.DEPLOY_PATH}" \\
        --nome-banco "${params.NOME_BANCO}"
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
   - Banco: ${params.NOME_BANCO}
   - Versão: ${params.VERSAO_DESEJADA}
   - Criou Banco: ${params.CRIAR_BANCO ? 'Sim' : 'Não'}
   - Deploy App: ${params.DEPLOY_APP ? 'Sim' : 'Não'}
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
   - Banco: ${params.NOME_BANCO}
==============================
            """
        }
    }
}
