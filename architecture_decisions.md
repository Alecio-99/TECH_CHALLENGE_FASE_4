# Decisões de Arquitetura - Tech Challenge Fase 4

## Tecnologias Escolhidas
- **Linguagem:** Java 17
- **Framework:** Spring Cloud Function (lógica de negócio agnóstica de provedor; mesma base roda como API Spring Boot localmente e como Lambda na AWS).
- **Cloud:** AWS
- **Empacotamento / Deploy:** Docker (Dockerfile multi-stage) + AWS Lambda Container Images + Amazon ECR
- **Orquestração da infraestrutura:** scripts Bash idempotentes usando AWS CLI (`infra/deploy-infra.sh`)
- **Banco de dados:** Amazon DynamoDB (NoSQL, integração nativa com Serverless e cobrança por uso).
- **Mensageria/Notificações:** Amazon SNS (e-mail de urgência + envio do relatório semanal).
- **Agendamento:** Amazon EventBridge (cron semanal).
- **Monitoramento:** Amazon CloudWatch (logs + métricas das Lambdas).
- **Ambiente local:** Docker Compose com **DynamoDB Local** e **LocalStack** (SNS).

## Por que Docker no lugar de Terraform?
A pós-graduação enfatizou **containerização com Docker** como padrão de empacotamento e deploy.
A AWS Lambda suporta nativamente **container images** (até 10 GB), então faz sentido:

1. Empacotar as duas Lambdas usando um único `Dockerfile` baseado em `public.ecr.aws/lambda/java:17`.
2. Publicar a imagem no **Amazon ECR**.
3. Criar/atualizar as Lambdas apontando para essa imagem.

A criação dos demais recursos (DynamoDB, SNS, IAM, API Gateway, EventBridge), que antes era feita por Terraform, agora é feita por **scripts AWS CLI** dentro de `infra/`. Os scripts são idempotentes (podem ser rodados várias vezes sem efeitos colaterais).

## Componentes Serverless (Lambdas)
1. **`processarFeedback` (POST /avaliacao):**
   - Recebe o feedback via API Gateway.
   - Salva no DynamoDB.
   - Se `nota < 5`, marca `urgencia=ALTA` e publica notificação no SNS.
2. **`gerarRelatorioSemanal`:**
   - Disparada pelo EventBridge (cron semanal).
   - Consulta o DynamoDB e calcula:
     - Média das avaliações da semana
     - Total de feedbacks
     - Total de feedbacks por urgência
     - Quantidade de avaliações por dia
   - Publica o relatório consolidado no SNS.

A separação respeita o princípio da **Responsabilidade Única**: uma função recebe e classifica, a outra agrega e relata.

## Segurança e Governança
- **IAM Roles:** uma role única para as Lambdas com policy mínima:
  - `dynamodb:PutItem|GetItem|Scan|Query` apenas na tabela `Feedbacks`.
  - `sns:Publish` apenas no tópico `feedback-notifications`.
  - `logs:*` no grupo de logs do CloudWatch.
- **API Gateway:** HTTP API (mais barato/rápido). Pode ser restrito com **API Key** ou integrado a **Cognito** para produção.
- **Imagens:** ECR com `scanOnPush=true` para vulnerabilidades.
- **Segredos:** sem credenciais hard-coded; tudo via variáveis de ambiente / IAM.
