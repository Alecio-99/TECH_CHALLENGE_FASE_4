# =========================================================
# Tech Challenge Fase 4 - Imagem da Lambda (Container Image)
# =========================================================
# Esta imagem é utilizada para fazer deploy das duas funções
# Lambda (processarFeedback e gerarRelatorioSemanal).
# A definição de qual função é executada é feita pela variável
# de ambiente SPRING_CLOUD_FUNCTION_DEFINITION na configuração
# da Lambda na AWS, então a MESMA imagem serve para as duas.
#
# Base oficial AWS Lambda Java 17:
#   https://gallery.ecr.aws/lambda/java
# =========================================================

# ---------- Stage 1: build com Maven ----------
FROM maven:3.9.6-eclipse-temurin-17 AS builder

WORKDIR /build

COPY pom.xml ./
RUN mvn -B -q dependency:go-offline

COPY src ./src
RUN mvn -B -q clean package -DskipTests

# ---------- Stage 2: runtime Lambda ----------
FROM public.ecr.aws/lambda/java:17

COPY --from=builder /build/target/feedback-service-0.0.1-SNAPSHOT-aws.jar ${LAMBDA_TASK_ROOT}/lib/

CMD ["org.springframework.cloud.function.adapter.aws.FunctionInvoker::handleRequest"]
