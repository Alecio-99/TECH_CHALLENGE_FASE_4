$ErrorActionPreference = "Stop"

$AwsRegion = "us-east-2"
$ReportLambdaName = "GerarRelatorioSemanal"
$RuleName = "weekly-feedback-report-cron"
$ScheduleExpression = "cron(59 23 ? * SUN *)"

Write-Host "[deploy-report] Subindo Lambda de relatorio semanal..." -ForegroundColor Cyan

& "$PSScriptRoot\infra\deploy-jar.ps1" `
    -AwsRegion $AwsRegion `
    -LambdaName $ReportLambdaName `
    -FunctionDefinition "gerarRelatorioSemanal" `
    -TimeoutSeconds 60

Write-Host "[deploy-report] Configurando EventBridge semanal..." -ForegroundColor Cyan

$ReportLambdaArn = aws lambda get-function-configuration `
    --function-name $ReportLambdaName `
    --region $AwsRegion `
    --query FunctionArn `
    --output text

if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($ReportLambdaArn)) {
    throw "Nao foi possivel obter o ARN da Lambda $ReportLambdaName."
}

aws events put-rule `
    --name $RuleName `
    --schedule-expression $ScheduleExpression `
    --description "Dispara o relatorio semanal de feedbacks" `
    --region $AwsRegion *> $null

if ($LASTEXITCODE -ne 0) {
    throw "Falha ao criar/atualizar regra EventBridge."
}

aws events put-targets `
    --rule $RuleName `
    --targets "Id=1,Arn=$ReportLambdaArn" `
    --region $AwsRegion *> $null

if ($LASTEXITCODE -ne 0) {
    throw "Falha ao associar Lambda na regra EventBridge."
}

$RuleArn = aws events describe-rule `
    --name $RuleName `
    --region $AwsRegion `
    --query Arn `
    --output text

aws lambda add-permission `
    --function-name $ReportLambdaName `
    --statement-id "AllowExecutionFromEventBridge" `
    --action "lambda:InvokeFunction" `
    --principal "events.amazonaws.com" `
    --source-arn $RuleArn `
    --region $AwsRegion *> $null

if ($LASTEXITCODE -ne 0) {
    Write-Host "[deploy-report] Permissao EventBridge ja existia ou nao precisou ser recriada." -ForegroundColor Yellow
}

Write-Host "[deploy-report] Deploy do relatorio concluido." -ForegroundColor Cyan
Write-Host "[deploy-report] Lambda: $ReportLambdaName" -ForegroundColor Cyan
Write-Host "[deploy-report] Funcao Spring: gerarRelatorioSemanal" -ForegroundColor Cyan
Write-Host "[deploy-report] Agendamento: $ScheduleExpression" -ForegroundColor Cyan
