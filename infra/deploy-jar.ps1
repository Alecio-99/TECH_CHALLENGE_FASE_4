param(
    [string]$AwsRegion = "us-east-2",
    [string]$LambdaName = "TechChallenge",
    [string]$DynamoTable = "Feedbacks",
    [string]$SnsTopicName = "feedback-notifications",
    [string]$AdminEmail = ""
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host "[deploy-jar] $Message" -ForegroundColor Cyan
}

function Assert-Command {
    param([string]$CommandName)
    if (-not (Get-Command $CommandName -ErrorAction SilentlyContinue)) {
        throw "Comando '$CommandName' nao encontrado. Instale/configure antes de rodar o deploy."
    }
}

Assert-Command "aws"
Assert-Command "mvn"

$RootDir = Resolve-Path "$PSScriptRoot\.."
$JarPath = Join-Path $RootDir "target\feedback-service-0.0.1-SNAPSHOT-aws.jar"
$Handler = "org.springframework.cloud.function.adapter.aws.FunctionInvoker::handleRequest"
$FunctionDefinition = "processarFeedback"

Write-Step "Validando credenciais AWS..."
$AccountId = aws sts get-caller-identity --query Account --output text
if ($LASTEXITCODE -ne 0) {
    throw "Nao foi possivel validar as credenciais AWS."
}

Write-Step "Conta AWS: $AccountId"
Write-Step "Regiao: $AwsRegion"

Write-Step "Gerando JAR da aplicacao..."
Push-Location $RootDir
try {
    mvn -q clean package -DskipTests
    if ($LASTEXITCODE -ne 0) {
        throw "Build Maven falhou."
    }
}
finally {
    Pop-Location
}

if (-not (Test-Path $JarPath)) {
    throw "JAR nao encontrado em: $JarPath"
}

Write-Step "Garantindo tabela DynamoDB '$DynamoTable'..."
aws dynamodb describe-table --table-name $DynamoTable --region $AwsRegion *> $null
if ($LASTEXITCODE -ne 0) {
    aws dynamodb create-table `
        --table-name $DynamoTable `
        --attribute-definitions AttributeName=id,AttributeType=S `
        --key-schema AttributeName=id,KeyType=HASH `
        --billing-mode PAY_PER_REQUEST `
        --region $AwsRegion *> $null

    if ($LASTEXITCODE -ne 0) {
        throw "Falha ao criar tabela DynamoDB."
    }

    aws dynamodb wait table-exists --table-name $DynamoTable --region $AwsRegion
    Write-Step "Tabela criada."
}
else {
    Write-Step "Tabela ja existe."
}

Write-Step "Garantindo topico SNS '$SnsTopicName'..."
$SnsTopicArn = aws sns create-topic `
    --name $SnsTopicName `
    --region $AwsRegion `
    --query TopicArn `
    --output text

if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($SnsTopicArn)) {
    throw "Falha ao criar/obter topico SNS."
}

Write-Step "SNS_TOPIC_ARN=$SnsTopicArn"

if (-not [string]::IsNullOrWhiteSpace($AdminEmail)) {
    Write-Step "Inscrevendo e-mail '$AdminEmail' no SNS..."
    aws sns subscribe `
        --topic-arn $SnsTopicArn `
        --protocol email `
        --notification-endpoint $AdminEmail `
        --region $AwsRegion *> $null

    Write-Step "Confirme a inscricao no e-mail recebido."
}

Write-Step "Lendo role da Lambda '$LambdaName'..."
$LambdaRoleArn = aws lambda get-function-configuration `
    --function-name $LambdaName `
    --region $AwsRegion `
    --query Role `
    --output text

if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($LambdaRoleArn)) {
    throw "Nao foi possivel encontrar a Lambda '$LambdaName' em '$AwsRegion'."
}

$LambdaRoleName = ($LambdaRoleArn -split "/")[-1]
Write-Step "Role: $LambdaRoleName"

Write-Step "Aplicando permissoes DynamoDB/SNS na role..."
$Policy = @{
    Version = "2012-10-17"
    Statement = @(
        @{
            Sid = "DynamoDbFeedbacksAccess"
            Effect = "Allow"
            Action = @(
                "dynamodb:PutItem",
                "dynamodb:GetItem",
                "dynamodb:Scan",
                "dynamodb:Query"
            )
            Resource = "arn:aws:dynamodb:${AwsRegion}:${AccountId}:table/${DynamoTable}"
        },
        @{
            Sid = "SnsPublishAccess"
            Effect = "Allow"
            Action = "sns:Publish"
            Resource = $SnsTopicArn
        }
    )
} | ConvertTo-Json -Depth 10

$PolicyPath = Join-Path $env:TEMP "techchallenge-lambda-policy.json"
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($PolicyPath, $Policy, $Utf8NoBom)

aws iam put-role-policy `
    --role-name $LambdaRoleName `
    --policy-name "TechChallengeFase4LambdaAccess" `
    --policy-document "file://$PolicyPath"

if ($LASTEXITCODE -ne 0) {
    throw "Falha ao aplicar policy na role."
}

Write-Step "Atualizando codigo da Lambda com o JAR..."
$JarUri = "fileb://" + ((Resolve-Path $JarPath).Path -replace "\\", "/")

aws lambda update-function-code `
    --function-name $LambdaName `
    --zip-file $JarUri `
    --region $AwsRegion *> $null

if ($LASTEXITCODE -ne 0) {
    throw "Falha ao atualizar o codigo da Lambda."
}

aws lambda wait function-updated --function-name $LambdaName --region $AwsRegion

Write-Step "Atualizando handler, runtime e variaveis de ambiente..."
$Environment = @{
    Variables = @{
        SPRING_CLOUD_FUNCTION_DEFINITION = $FunctionDefinition
        DYNAMODB_TABLE_NAME = $DynamoTable
        SNS_TOPIC_ARN = $SnsTopicArn
    }
} | ConvertTo-Json -Compress

$EnvironmentPath = Join-Path $env:TEMP "techchallenge-lambda-env.json"
[System.IO.File]::WriteAllText($EnvironmentPath, $Environment, $Utf8NoBom)

aws lambda update-function-configuration `
    --function-name $LambdaName `
    --runtime java17 `
    --handler $Handler `
    --memory-size 512 `
    --timeout 30 `
    --environment "file://$EnvironmentPath" `
    --region $AwsRegion *> $null

if ($LASTEXITCODE -ne 0) {
    throw "Falha ao atualizar configuracao da Lambda."
}

aws lambda wait function-updated --function-name $LambdaName --region $AwsRegion

Write-Step "Deploy concluido."
Write-Step "Lambda: $LambdaName"
Write-Step "Handler: $Handler"
Write-Step "Funcao Spring: $FunctionDefinition"
Write-Step "DynamoDB: $DynamoTable"
Write-Step "SNS: $SnsTopicArn"
