#!/usr/bin/env bash
# =========================================================
# Destroi a infraestrutura criada por deploy-infra.sh.
# Use com cuidado: apaga Lambdas, API, regra do EventBridge,
# tópico SNS, role IAM, repositório ECR e tabela DynamoDB.
# =========================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/config.env"

log() { echo -e "\033[1;31m[teardown]\033[0m $*"; }

read -r -p "Tem certeza que deseja DESTRUIR todos os recursos do projeto? [yes/N] " confirm
if [[ "${confirm}" != "yes" ]]; then
  log "Operação cancelada."
  exit 0
fi

log "Removendo regra EventBridge..."
aws events remove-targets --rule "weekly-feedback-report-cron" --ids "1" --region "${AWS_REGION}" >/dev/null 2>&1 || true
aws events delete-rule --name "weekly-feedback-report-cron" --region "${AWS_REGION}" >/dev/null 2>&1 || true

log "Removendo API Gateway..."
API_ID="$(aws apigatewayv2 get-apis --region "${AWS_REGION}" --query "Items[?Name=='${API_NAME}'].ApiId | [0]" --output text)"
if [[ "${API_ID}" != "None" && -n "${API_ID}" ]]; then
  aws apigatewayv2 delete-api --api-id "${API_ID}" --region "${AWS_REGION}" >/dev/null
fi

log "Removendo Lambdas..."
aws lambda delete-function --function-name "${LAMBDA_FEEDBACK}" --region "${AWS_REGION}" >/dev/null 2>&1 || true
aws lambda delete-function --function-name "${LAMBDA_REPORT}"   --region "${AWS_REGION}" >/dev/null 2>&1 || true

log "Removendo IAM role..."
aws iam delete-role-policy --role-name "${LAMBDA_ROLE_NAME}" --policy-name "feedback_lambda_policy" >/dev/null 2>&1 || true
aws iam delete-role --role-name "${LAMBDA_ROLE_NAME}" >/dev/null 2>&1 || true

log "Removendo tópico SNS..."
TOPIC_ARN="$(aws sns list-topics --region "${AWS_REGION}" --query "Topics[?ends_with(TopicArn, ':${SNS_TOPIC_NAME}')].TopicArn | [0]" --output text)"
if [[ "${TOPIC_ARN}" != "None" && -n "${TOPIC_ARN}" ]]; then
  aws sns delete-topic --topic-arn "${TOPIC_ARN}" --region "${AWS_REGION}" >/dev/null
fi

log "Removendo tabela DynamoDB..."
aws dynamodb delete-table --table-name "${DYNAMO_TABLE}" --region "${AWS_REGION}" >/dev/null 2>&1 || true

log "Removendo imagens e repositório ECR..."
aws ecr delete-repository --repository-name "${ECR_REPOSITORY}" --force --region "${AWS_REGION}" >/dev/null 2>&1 || true

rm -rf "${SCRIPT_DIR}/.deploy-state"
log "Tudo destruído."
