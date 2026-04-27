package com.techchallenge.feedback.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.techchallenge.feedback.model.Feedback;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.DynamoDbClientBuilder;
import software.amazon.awssdk.services.dynamodb.model.PutItemRequest;
import software.amazon.awssdk.services.dynamodb.model.ScanRequest;
import software.amazon.awssdk.services.sns.SnsClient;
import software.amazon.awssdk.services.sns.SnsClientBuilder;
import software.amazon.awssdk.services.sns.model.PublishRequest;

import java.net.URI;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;

@Service
public class FeedbackService {

    private static final Logger log = LoggerFactory.getLogger(FeedbackService.class);

    private final DynamoDbClient dynamoDbClient;
    private final SnsClient snsClient;
    private final ObjectMapper objectMapper = new ObjectMapper();

    private final String tableName;
    private final String snsTopicArn;

    public FeedbackService() {
        this.tableName = envOrDefault("DYNAMODB_TABLE_NAME", "Feedbacks");
        this.snsTopicArn = System.getenv("SNS_TOPIC_ARN");

        String region = envOrDefault("AWS_REGION", "us-east-1");

        DynamoDbClientBuilder dynamoBuilder = DynamoDbClient.builder().region(Region.of(region));
        String dynamoEndpoint = System.getenv("DYNAMODB_ENDPOINT");
        if (dynamoEndpoint != null && !dynamoEndpoint.isBlank()) {
            dynamoBuilder.endpointOverride(URI.create(dynamoEndpoint));
        }
        this.dynamoDbClient = dynamoBuilder.build();

        SnsClientBuilder snsBuilder = SnsClient.builder().region(Region.of(region));
        String snsEndpoint = System.getenv("SNS_ENDPOINT");
        if (snsEndpoint != null && !snsEndpoint.isBlank()) {
            snsBuilder.endpointOverride(URI.create(snsEndpoint));
        }
        this.snsClient = snsBuilder.build();
    }

    public Feedback salvarFeedback(Feedback feedback) {
        feedback.setId(UUID.randomUUID().toString());
        feedback.setDataEnvio(Instant.now().toString());
        feedback.setUrgencia(feedback.getNota() < 5 ? "ALTA" : "NORMAL");

        log.info("Salvando feedback id={} nota={} urgencia={}", feedback.getId(), feedback.getNota(), feedback.getUrgencia());

        dynamoDbClient.putItem(PutItemRequest.builder()
                .tableName(tableName)
                .item(feedback.toAttributeValueMap())
                .build());

        if ("ALTA".equals(feedback.getUrgencia())) {
            enviarNotificacaoUrgencia(feedback);
        }

        return feedback;
    }

    private void enviarNotificacaoUrgencia(Feedback feedback) {
        if (snsTopicArn == null || snsTopicArn.isBlank()) {
            log.warn("SNS_TOPIC_ARN não configurado; pulando notificação de urgência.");
            return;
        }

        String mensagem = String.format(
                "ALERTA DE URGÊNCIA%n%nDescrição: %s%nUrgência: %s%nData: %s%nNota: %d",
                feedback.getDescricao(), feedback.getUrgencia(), feedback.getDataEnvio(), feedback.getNota());

        snsClient.publish(PublishRequest.builder()
                .topicArn(snsTopicArn)
                .message(mensagem)
                .subject("Feedback Crítico Recebido")
                .build());

        log.info("Notificação de urgência enviada para o tópico {}", snsTopicArn);
    }

    public List<Feedback> listarFeedbacksUltimaSemana() {
        Instant umaSemanaAtras = Instant.now().minus(7, ChronoUnit.DAYS);
        // Em produção: criar GSI por dataEnvio. Para o desafio, mantemos Scan com filtro em memória.
        return dynamoDbClient.scan(ScanRequest.builder().tableName(tableName).build())
                .items()
                .stream()
                .map(Feedback::fromAttributeValueMap)
                .filter(f -> {
                    try {
                        return Instant.parse(f.getDataEnvio()).isAfter(umaSemanaAtras);
                    } catch (Exception e) {
                        return false;
                    }
                })
                .sorted(Comparator.comparing(Feedback::getDataEnvio))
                .collect(Collectors.toList());
    }

    public void enviarRelatorioPorEmail(Map<String, Object> relatorio) {
        if (snsTopicArn == null || snsTopicArn.isBlank()) {
            log.warn("SNS_TOPIC_ARN não configurado; pulando envio do relatório semanal.");
            return;
        }

        try {
            String corpo = "Relatório semanal de feedbacks (" + Instant.now() + ")\n\n"
                    + objectMapper.writerWithDefaultPrettyPrinter().writeValueAsString(relatorio);

            snsClient.publish(PublishRequest.builder()
                    .topicArn(snsTopicArn)
                    .message(corpo)
                    .subject("Relatório Semanal de Feedbacks")
                    .build());

            log.info("Relatório semanal publicado no tópico SNS.");
        } catch (Exception e) {
            log.error("Falha ao serializar/enviar o relatório semanal", e);
        }
    }

    private static String envOrDefault(String key, String defaultValue) {
        String v = System.getenv(key);
        return (v == null || v.isBlank()) ? defaultValue : v;
    }
}
