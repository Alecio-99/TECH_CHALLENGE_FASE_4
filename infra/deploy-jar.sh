#!/usr/bin/env bash
# =========================================================
# Deploy usando o JAR gerado em target/ para uma Lambda Java.
# Este fluxo é para o cenário atual, em que o upload é feito
# como arquivo .jar/.zip da Lambda, sem Docker/ECR.
#
# Uso:
#   ./infra/deploy-jar.sh
# =========================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/config.env"

JAR_PATH="${ROOT_DIR}/target/feedback-service-0.0.1-SNAPSHOT-aws.jar"
HANDLER="org.springframework.cloud.function.adapter.aws.FunctionInvoker::handleRequest"
FUNCTION_DEFINITION="processarFeedback"

log() { echo -e "\033[1;34m[deploy-jar]\033[0m $*"; }

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Erro: comando '$1' nao encontrado. Instale/configure antes de rodar o deploy." >&2
    exit 1
  fi
}

require_cmd aws
require_cmd mvn

log "Validando conta AWS..."
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
log "Conta AWS: ${ACCOUNT_ID}"
log "Regiao: ${AWS_REGION}"

log "Gerando JAR da aplicacao..."
(cd "${ROOT_DIR}" && mvn -q clean package -DskipTests)

if [[ ! -f "${JAR_PATH}" ]]; then
  echo "Erro: JAR nao encontrado em ${JAR_PATH}" >&2
  exit 1
fi

log "Garantindo tabela DynamoDB '${DYNAMO_TABLE}'..."
if ! aws dynamodb describe-table --table-name "${DYNAMO_TABLE}" --region "${AWS_REGION}" >/dev/null 2>&1; then
  aws dynamodb create-table \
    --table-name "${DYNAMO_TABLE}" \
    --attribute-definitions AttributeName=id,AttributeType=S \
    --key-schema AttributeName=id,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${AWS_REGION}" >/dev/null
  aws dynamodb wait table-exists --table-name "${DYNAMO_TABLE}" --region "${AWS_REGION}"
  log "Tabela criada."
else
  log "Tabela ja existe."
fi

log "Garantindo topico SNS '${SNS_TOPIC_NAME}'..."
SNS_TOPIC_ARN="$(aws sns create-topic \
  --name "${SNS_TOPIC_NAME}" \
  --region "${AWS_REGION}" \
  --query TopicArn \
  --output text)"
log "SNS_TOPIC_ARN=${SNS_TOPIC_ARN}"

if [[ -n "${ADMIN_EMAIL}" ]]; then
  log "Inscrevendo e-mail '${ADMIN_EMAIL}' no SNS..."
  aws sns subscribe \
    --topic-arn "${SNS_TOPIC_ARN}" \
    --protocol email \
    --notification-endpoint "${ADMIN_EMAIL}" \
    --region "${AWS_REGION}" >/dev/null
  log "Confirme a inscricao no e-mail recebido."
fi

log "Lendo role da Lambda '${LAMBDA_FEEDBACK}'..."
LAMBDA_ROLE_ARN="$(aws lambda get-function-configuration \
  --function-name "${LAMBDA_FEEDBACK}" \
  --region "${AWS_REGION}" \
  --query Role \
  --output text)"
LAMBDA_ROLE_NAME="${LAMBDA_ROLE_ARN##*/}"
log "Role: ${LAMBDA_ROLE_NAME}"

log "Aplicando permissoes DynamoDB/SNS na role..."
INLINE_POLICY=$(cat <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DynamoDbFeedbacksAccess",
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
      "Sid": "SnsPublishAccess",
      "Effect": "Allow",
      "Action": "sns:Publish",
      "Resource": "${SNS_TOPIC_ARN}"
    }
  ]
}
JSON
)

aws iam put-role-policy \
  --role-name "${LAMBDA_ROLE_NAME}" \
  --policy-name "TechChallengeFase4LambdaAccess" \
  --policy-document "${INLINE_POLICY}"

log "Atualizando codigo da Lambda com o JAR..."
aws lambda update-function-code \
  --function-name "${LAMBDA_FEEDBACK}" \
  --zip-file "fileb://${JAR_PATH}" \
  --region "${AWS_REGION}" >/dev/null

aws lambda wait function-updated \
  --function-name "${LAMBDA_FEEDBACK}" \
  --region "${AWS_REGION}"

log "Atualizando handler, runtime e variaveis de ambiente..."
aws lambda update-function-configuration \
  --function-name "${LAMBDA_FEEDBACK}" \
  --runtime java17 \
  --handler "${HANDLER}" \
  --memory-size "${LAMBDA_MEMORY}" \
  --timeout "${LAMBDA_TIMEOUT_FEEDBACK}" \
  --environment "Variables={SPRING_CLOUD_FUNCTION_DEFINITION=${FUNCTION_DEFINITION},DYNAMODB_TABLE_NAME=${DYNAMO_TABLE},SNS_TOPIC_ARN=${SNS_TOPIC_ARN}}" \
  --region "${AWS_REGION}" >/dev/null

aws lambda wait function-updated \
  --function-name "${LAMBDA_FEEDBACK}" \
  --region "${AWS_REGION}"

log "Deploy concluido."
log "Lambda: ${LAMBDA_FEEDBACK}"
log "Handler: ${HANDLER}"
log "Funcao Spring: ${FUNCTION_DEFINITION}"
log "DynamoDB: ${DYNAMO_TABLE}"
log "SNS: ${SNS_TOPIC_ARN}"
