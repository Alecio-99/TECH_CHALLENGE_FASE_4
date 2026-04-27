#!/usr/bin/env bash
# =========================================================
# Deploy completo da infraestrutura AWS (sem Terraform).
#
# Substitui o que antes era feito por terraform/main.tf por
# chamadas idempotentes do AWS CLI.
#
# Pré-requisitos:
#   - AWS CLI v2 configurado (aws configure)
#   - Docker rodando
#   - jq instalado
#
# Uso:
#   ./infra/deploy-infra.sh
# =========================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/config.env"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}"
IMAGE_TAG="latest"

log() { echo -e "\033[1;34m[infra]\033[0m $*"; }

# ---------------------------------------------------------
# 1. DynamoDB
# ---------------------------------------------------------
log "Criando tabela DynamoDB '${DYNAMO_TABLE}' (se não existir)..."
if ! aws dynamodb describe-table --table-name "${DYNAMO_TABLE}" --region "${AWS_REGION}" >/dev/null 2>&1; then
  aws dynamodb create-table \
    --table-name "${DYNAMO_TABLE}" \
    --attribute-definitions AttributeName=id,AttributeType=S \
    --key-schema AttributeName=id,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --tags Key=Project,Value="${PROJECT_NAME}" \
    --region "${AWS_REGION}" >/dev/null
  aws dynamodb wait table-exists --table-name "${DYNAMO_TABLE}" --region "${AWS_REGION}"
  log "Tabela criada."
else
  log "Tabela já existe, ok."
fi

# ---------------------------------------------------------
# 2. SNS Topic
# ---------------------------------------------------------
log "Criando tópico SNS '${SNS_TOPIC_NAME}'..."
SNS_TOPIC_ARN="$(aws sns create-topic --name "${SNS_TOPIC_NAME}" --region "${AWS_REGION}" --query TopicArn --output text)"
log "Topic ARN: ${SNS_TOPIC_ARN}"

if [[ -n "${ADMIN_EMAIL}" ]]; then
  log "Inscrevendo e-mail '${ADMIN_EMAIL}' no tópico..."
  aws sns subscribe \
    --topic-arn "${SNS_TOPIC_ARN}" \
    --protocol email \
    --notification-endpoint "${ADMIN_EMAIL}" \
    --region "${AWS_REGION}" >/dev/null
  log "Inscrição criada. Confirme no e-mail recebido."
fi

# ---------------------------------------------------------
# 3. IAM Role para as Lambdas
# ---------------------------------------------------------
log "Criando IAM Role '${LAMBDA_ROLE_NAME}'..."
TRUST_POLICY=$(cat <<'JSON'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "lambda.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
JSON
)

if ! aws iam get-role --role-name "${LAMBDA_ROLE_NAME}" >/dev/null 2>&1; then
  aws iam create-role \
    --role-name "${LAMBDA_ROLE_NAME}" \
    --assume-role-policy-document "${TRUST_POLICY}" >/dev/null
  log "Role criada."
else
  log "Role já existia."
fi

LAMBDA_ROLE_ARN="$(aws iam get-role --role-name "${LAMBDA_ROLE_NAME}" --query Role.Arn --output text)"

INLINE_POLICY=$(cat <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:PutItem",
        "dynamodb:GetItem",
        "dynamodb:Scan",
        "dynamodb:Query"
      ],
      "Resource": "arn:aws:dynamodb:${AWS_REGION}:${ACCOUNT_ID}:table/${DYNAMO_TABLE}"
    },
    {
      "Effect": "Allow",
      "Action": "sns:Publish",
      "Resource": "${SNS_TOPIC_ARN}"
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:${AWS_REGION}:${ACCOUNT_ID}:*"
    }
  ]
}
JSON
)

aws iam put-role-policy \
  --role-name "${LAMBDA_ROLE_NAME}" \
  --policy-name "feedback_lambda_policy" \
  --policy-document "${INLINE_POLICY}"
log "Policy atualizada."

log "Aguardando propagação da role (10s)..."
sleep 10

# ---------------------------------------------------------
# 4. ECR + build/push da imagem Docker
# ---------------------------------------------------------
log "Garantindo repositório ECR '${ECR_REPOSITORY}'..."
if ! aws ecr describe-repositories --repository-names "${ECR_REPOSITORY}" --region "${AWS_REGION}" >/dev/null 2>&1; then
  aws ecr create-repository \
    --repository-name "${ECR_REPOSITORY}" \
    --image-scanning-configuration scanOnPush=true \
    --region "${AWS_REGION}" >/dev/null
fi

log "Login no ECR..."
aws ecr get-login-password --region "${AWS_REGION}" \
  | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

log "Build da imagem Docker..."
docker build --platform linux/amd64 -t "${ECR_REPOSITORY}:${IMAGE_TAG}" "${ROOT_DIR}"

log "Tagging e push para ECR..."
docker tag "${ECR_REPOSITORY}:${IMAGE_TAG}" "${ECR_URI}:${IMAGE_TAG}"
docker push "${ECR_URI}:${IMAGE_TAG}"

# ---------------------------------------------------------
# 5. Lambdas (Container Image)
# ---------------------------------------------------------
create_or_update_lambda() {
  local name="$1"
  local function_def="$2"
  local timeout="$3"

  log "Provisionando Lambda '${name}'..."

  if aws lambda get-function --function-name "${name}" --region "${AWS_REGION}" >/dev/null 2>&1; then
    aws lambda update-function-code \
      --function-name "${name}" \
      --image-uri "${ECR_URI}:${IMAGE_TAG}" \
      --region "${AWS_REGION}" >/dev/null
    aws lambda wait function-updated --function-name "${name}" --region "${AWS_REGION}"
    aws lambda update-function-configuration \
      --function-name "${name}" \
      --timeout "${timeout}" \
      --memory-size "${LAMBDA_MEMORY}" \
      --environment "Variables={SPRING_CLOUD_FUNCTION_DEFINITION=${function_def},SNS_TOPIC_ARN=${SNS_TOPIC_ARN},DYNAMODB_TABLE_NAME=${DYNAMO_TABLE}}" \
      --region "${AWS_REGION}" >/dev/null
  else
    aws lambda create-function \
      --function-name "${name}" \
      --package-type Image \
      --code "ImageUri=${ECR_URI}:${IMAGE_TAG}" \
      --role "${LAMBDA_ROLE_ARN}" \
      --timeout "${timeout}" \
      --memory-size "${LAMBDA_MEMORY}" \
      --environment "Variables={SPRING_CLOUD_FUNCTION_DEFINITION=${function_def},SNS_TOPIC_ARN=${SNS_TOPIC_ARN},DYNAMODB_TABLE_NAME=${DYNAMO_TABLE}}" \
      --region "${AWS_REGION}" >/dev/null
    aws lambda wait function-active --function-name "${name}" --region "${AWS_REGION}"
  fi
}

create_or_update_lambda "${LAMBDA_FEEDBACK}" "processarFeedback" "${LAMBDA_TIMEOUT_FEEDBACK}"
create_or_update_lambda "${LAMBDA_REPORT}"   "gerarRelatorioSemanal" "${LAMBDA_TIMEOUT_REPORT}"

# ---------------------------------------------------------
# 6. EventBridge (relatório semanal)
# ---------------------------------------------------------
RULE_NAME="weekly-feedback-report-cron"
log "Criando regra EventBridge '${RULE_NAME}'..."
aws events put-rule \
  --name "${RULE_NAME}" \
  --schedule-expression "${REPORT_SCHEDULE}" \
  --description "Dispara o relatório semanal de feedbacks" \
  --region "${AWS_REGION}" >/dev/null

REPORT_LAMBDA_ARN="$(aws lambda get-function --function-name "${LAMBDA_REPORT}" --region "${AWS_REGION}" --query Configuration.FunctionArn --output text)"

aws events put-targets \
  --rule "${RULE_NAME}" \
  --targets "Id=1,Arn=${REPORT_LAMBDA_ARN}" \
  --region "${AWS_REGION}" >/dev/null

aws lambda add-permission \
  --function-name "${LAMBDA_REPORT}" \
  --statement-id "AllowExecutionFromEventBridge" \
  --action "lambda:InvokeFunction" \
  --principal "events.amazonaws.com" \
  --source-arn "$(aws events describe-rule --name "${RULE_NAME}" --region "${AWS_REGION}" --query Arn --output text)" \
  --region "${AWS_REGION}" >/dev/null 2>&1 || log "Permissão EventBridge já existia."

# ---------------------------------------------------------
# 7. API Gateway HTTP API (POST /avaliacao)
# ---------------------------------------------------------
log "Criando/atualizando API Gateway '${API_NAME}'..."
API_ID="$(aws apigatewayv2 get-apis --region "${AWS_REGION}" --query "Items[?Name=='${API_NAME}'].ApiId | [0]" --output text)"

if [[ "${API_ID}" == "None" || -z "${API_ID}" ]]; then
  API_ID="$(aws apigatewayv2 create-api \
    --name "${API_NAME}" \
    --protocol-type HTTP \
    --region "${AWS_REGION}" \
    --query ApiId --output text)"
  log "API criada (ID: ${API_ID})."
else
  log "API já existia (ID: ${API_ID})."
fi

FEEDBACK_LAMBDA_ARN="$(aws lambda get-function --function-name "${LAMBDA_FEEDBACK}" --region "${AWS_REGION}" --query Configuration.FunctionArn --output text)"

INTEGRATION_ID="$(aws apigatewayv2 get-integrations --api-id "${API_ID}" --region "${AWS_REGION}" \
  --query "Items[?IntegrationUri=='${FEEDBACK_LAMBDA_ARN}'].IntegrationId | [0]" --output text)"

if [[ "${INTEGRATION_ID}" == "None" || -z "${INTEGRATION_ID}" ]]; then
  INTEGRATION_ID="$(aws apigatewayv2 create-integration \
    --api-id "${API_ID}" \
    --integration-type AWS_PROXY \
    --integration-uri "${FEEDBACK_LAMBDA_ARN}" \
    --payload-format-version "2.0" \
    --region "${AWS_REGION}" \
    --query IntegrationId --output text)"
fi

ROUTE_ID="$(aws apigatewayv2 get-routes --api-id "${API_ID}" --region "${AWS_REGION}" \
  --query "Items[?RouteKey=='${API_ROUTE}'].RouteId | [0]" --output text)"

if [[ "${ROUTE_ID}" == "None" || -z "${ROUTE_ID}" ]]; then
  aws apigatewayv2 create-route \
    --api-id "${API_ID}" \
    --route-key "${API_ROUTE}" \
    --target "integrations/${INTEGRATION_ID}" \
    --region "${AWS_REGION}" >/dev/null
fi

if ! aws apigatewayv2 get-stage --api-id "${API_ID}" --stage-name '$default' --region "${AWS_REGION}" >/dev/null 2>&1; then
  aws apigatewayv2 create-stage \
    --api-id "${API_ID}" \
    --stage-name '$default' \
    --auto-deploy \
    --region "${AWS_REGION}" >/dev/null
fi

aws lambda add-permission \
  --function-name "${LAMBDA_FEEDBACK}" \
  --statement-id "AllowExecutionFromAPIGateway" \
  --action "lambda:InvokeFunction" \
  --principal "apigateway.amazonaws.com" \
  --source-arn "arn:aws:execute-api:${AWS_REGION}:${ACCOUNT_ID}:${API_ID}/*/*" \
  --region "${AWS_REGION}" >/dev/null 2>&1 || log "Permissão API Gateway já existia."

API_ENDPOINT="$(aws apigatewayv2 get-api --api-id "${API_ID}" --region "${AWS_REGION}" --query ApiEndpoint --output text)"

# ---------------------------------------------------------
# 8. Estado final
# ---------------------------------------------------------
mkdir -p "${SCRIPT_DIR}/.deploy-state"
cat > "${SCRIPT_DIR}/.deploy-state/state.env" <<EOF
ACCOUNT_ID=${ACCOUNT_ID}
SNS_TOPIC_ARN=${SNS_TOPIC_ARN}
LAMBDA_ROLE_ARN=${LAMBDA_ROLE_ARN}
ECR_URI=${ECR_URI}
API_ID=${API_ID}
API_ENDPOINT=${API_ENDPOINT}
EOF

echo
log "Deploy concluído com sucesso."
log "Endpoint: ${API_ENDPOINT}/avaliacao"
log "Tabela DynamoDB: ${DYNAMO_TABLE}"
log "Tópico SNS: ${SNS_TOPIC_ARN}"
