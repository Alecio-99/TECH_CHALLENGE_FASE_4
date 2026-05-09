# Tech Challenge Fase 4 - Plataforma de Feedback Serverless

Projeto desenvolvido para o Tech Challenge da Fase 4, com foco em Cloud Computing, Serverless e deploy em ambiente de nuvem. A aplicação permite registrar feedbacks de aulas, notificar administradores quando houver avaliações críticas e gerar um relatório semanal consolidado.

## Modelo de Cloud

O modelo escolhido foi **Serverless na AWS**, usando serviços gerenciados para reduzir manutenção de infraestrutura, escalar sob demanda e pagar conforme o uso.

Componentes principais:

- **AWS Lambda:** execução das funções serverless em Java 17.
- **Amazon DynamoDB:** armazenamento dos feedbacks na tabela `Feedbacks`.
- **Amazon SNS:** envio de e-mails para administradores.
- **Amazon EventBridge:** agendamento semanal da geração de relatório.
- **Amazon CloudWatch:** logs e métricas das Lambdas.
- **IAM:** governança de acesso e permissões mínimas para as funções.

## Arquitetura

![Arquitetura da Solução](architecture.png)

Fluxo principal:

```text
Usuário/Admin
  -> Lambda processarFeedback
  -> DynamoDB Feedbacks
  -> SNS feedback-notifications, se nota < 5
  -> E-mail do administrador
```

Fluxo do relatório:

```text
EventBridge semanal
  -> Lambda gerarRelatorioSemanal
  -> DynamoDB Feedbacks
  -> SNS feedback-notifications
  -> E-mail do administrador
```

## Funções Serverless

### 1. `processarFeedback`

Responsabilidade: receber, classificar e persistir feedbacks.

Entrada esperada:

```json
{
  "descricao": "A aula foi muito confusa e o audio estava ruim.",
  "nota": 3
}
```

Comportamento:

- Gera `id` automaticamente.
- Registra `dataEnvio`.
- Define `urgencia` como `ALTA` quando `nota < 5`; caso contrário, `NORMAL`.
- Salva o feedback no DynamoDB.
- Publica uma notificação no SNS quando a urgência é `ALTA`.

### 2. `gerarRelatorioSemanal`

Responsabilidade: consolidar os feedbacks da última semana e enviar relatório.

Comportamento:

- Busca feedbacks dos últimos 7 dias no DynamoDB.
- Calcula a média das avaliações.
- Calcula quantidade de avaliações por dia.
- Calcula quantidade de avaliações por urgência.
- Publica o relatório consolidado no SNS.

Agendamento:

```text
EventBridge: weekly-feedback-report-cron
Cron: cron(59 23 ? * SUN *)
```

## Estrutura do Projeto

```text
.
├── Dockerfile
├── docker-compose.yml
├── deploy.ps1
├── deploy-report.ps1
├── deploy.sh
├── infra/
│   ├── config.env
│   ├── deploy-jar.ps1
│   ├── deploy-jar.sh
│   ├── deploy-infra.sh
│   └── teardown-infra.sh
├── pom.xml
├── src/main/java/com/techchallenge/feedback/
│   ├── FeedbackApplication.java
│   ├── client/FeedbackFunctionUrlClient.java
│   ├── functions/FeedbackFunctions.java
│   ├── model/Feedback.java
│   └── service/FeedbackService.java
├── src/main/resources/application.properties
├── src/test/java/com/techchallenge/feedback/FeedbackFunctionUrlManualTest.java
├── architecture.d2
├── architecture_decisions.md
└── architecture.png
```

## Pré-Requisitos

- Java 17
- Maven
- AWS CLI v2 configurado com `aws configure`
- Conta AWS com permissão para Lambda, DynamoDB, SNS, EventBridge, CloudWatch e IAM
- PowerShell, para executar os scripts de deploy no Windows

Região usada no projeto:

```text
us-east-2
```

## Deploy

O deploy atual usa o JAR gerado pelo Maven em `target/feedback-service-0.0.1-SNAPSHOT-aws.jar`.

### Lambda de Feedback

Execute:

```powershell
.\deploy.ps1
```

Esse script:

- Executa `mvn clean package -DskipTests`.
- Cria/valida a tabela DynamoDB `Feedbacks`.
- Cria/valida o tópico SNS `feedback-notifications`.
- Atualiza o JAR da Lambda principal.
- Configura o handler:

```text
org.springframework.cloud.function.adapter.aws.FunctionInvoker::handleRequest
```

- Configura as variáveis:

```text
SPRING_CLOUD_FUNCTION_DEFINITION=processarFeedback
DYNAMODB_TABLE_NAME=Feedbacks
SNS_TOPIC_ARN=<arn do topico SNS>
```

### Lambda de Relatório Semanal

Execute:

```powershell
.\deploy-report.ps1
```

Esse script:

- Atualiza o JAR da Lambda `GerarRelatorioSemanal`.
- Configura:

```text
SPRING_CLOUD_FUNCTION_DEFINITION=gerarRelatorioSemanal
DYNAMODB_TABLE_NAME=Feedbacks
SNS_TOPIC_ARN=<arn do topico SNS>
```

- Cria/atualiza a regra EventBridge `weekly-feedback-report-cron`.
- Associa a regra EventBridge à Lambda de relatório.

Se o PowerShell bloquear a execução, use:

```powershell
powershell -ExecutionPolicy Bypass -File .\deploy.ps1
powershell -ExecutionPolicy Bypass -File .\deploy-report.ps1
```

## Testes

### Testar feedback normal

Na aba **Testar** da Lambda principal:

```json
{
  "descricao": "Aula boa e bem explicada",
  "nota": 8
}
```

Resultado esperado:

- Feedback salvo no DynamoDB.
- Sem envio de e-mail, pois a urgência é `NORMAL`.

### Testar feedback crítico

Na aba **Testar** da Lambda principal:

```json
{
  "descricao": "A aula foi muito confusa e o audio estava ruim",
  "nota": 3
}
```

Resultado esperado:

- Feedback salvo no DynamoDB.
- Urgência definida como `ALTA`.
- Publicação no SNS.
- E-mail enviado ao administrador inscrito no tópico.

### Testar relatório semanal

Na aba **Testar** da Lambda `GerarRelatorioSemanal`, use:

```json
{}
```

Resultado esperado:

- Consulta dos feedbacks no DynamoDB.
- Cálculo da média das avaliações.
- Contagem por dia.
- Contagem por urgência.
- Envio do relatório via SNS.

## Configuração do E-Mail no SNS

Para receber os e-mails:

1. Acesse **Amazon SNS**.
2. Abra o tópico `feedback-notifications`.
3. Clique em **Criar assinatura**.
4. Escolha protocolo **Email**.
5. Informe o e-mail do administrador.
6. Confirme a assinatura no e-mail recebido.

O envio só acontece se a assinatura estiver com status **Confirmed**.

## Monitoramento

O monitoramento é feito pelo **Amazon CloudWatch**.

Log groups esperados:

```text
/aws/lambda/<nome-da-lambda-principal>
/aws/lambda/GerarRelatorioSemanal
```

Métricas disponíveis:

- Invocations
- Duration
- Errors
- Throttles
- Concurrent executions

Pela própria tela da Lambda, acesse:

```text
Monitor -> View CloudWatch logs
```

## Segurança e Governança

- As funções usam IAM Roles próprias.
- As permissões são aplicadas para acessar apenas os recursos necessários:
  - DynamoDB `Feedbacks`
  - SNS `feedback-notifications`
- Credenciais AWS não ficam no código.
- A URL real da Function URL deve ser configurada por variável de ambiente:

```powershell
$env:FEEDBACK_FUNCTION_URL="https://sua-function-url.lambda-url.us-east-2.on.aws/"
```

No repositório público, o `application.properties` usa um placeholder seguro.

## Ambiente Local

Existe suporte local com Docker Compose:

```bash
docker compose up -d
```

Esse ambiente sobe:

- DynamoDB Local
- LocalStack para SNS
- Lambda emulada na porta `9000`

Exemplo de chamada local:

```bash
curl -XPOST "http://localhost:9000/2015-03-31/functions/function/invocations" \
  -d '{"descricao":"A aula foi confusa","nota":3}'
```

## Observação Sobre Docker

O projeto contém `Dockerfile` e `docker-compose.yml`, pois a solução foi preparada para ambiente containerizado e testes locais. No deploy atual usado na AWS, o empacotamento está sendo feito via JAR para Lambda Java 17. O arquivo `infra/deploy-infra.sh` mantém uma alternativa de deploy por imagem Docker/ECR para evolução futura.

## Demonstração Sugerida

Para o vídeo/apresentação:

1. Mostrar as duas Lambdas na AWS.
2. Testar `processarFeedback` com nota `3`.
3. Mostrar o item salvo no DynamoDB.
4. Mostrar o e-mail recebido pelo SNS.
5. Testar `GerarRelatorioSemanal` com `{}`.
6. Mostrar os logs no CloudWatch.
7. Mostrar a regra EventBridge `weekly-feedback-report-cron` habilitada.
