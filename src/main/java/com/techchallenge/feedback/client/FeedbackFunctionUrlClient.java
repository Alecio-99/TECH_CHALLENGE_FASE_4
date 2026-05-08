package com.techchallenge.feedback.client;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.Map;

@Component
public class FeedbackFunctionUrlClient {

    private final HttpClient httpClient;
    private final ObjectMapper objectMapper;

    @Value("${app.feedback-url}")
    private String feedbackUrl;

    public FeedbackFunctionUrlClient(ObjectMapper objectMapper) {
        this.httpClient = HttpClient.newHttpClient();
        this.objectMapper = objectMapper;
    }

    public HttpResponse<String> enviarFeedback(String descricao, int nota) throws Exception {
        String body = objectMapper.writeValueAsString(Map.of(
                "descricao", descricao,
                "nota", nota
        ));

        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(feedbackUrl))
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(body))
                .build();

        return httpClient.send(request, HttpResponse.BodyHandlers.ofString());
    }

    public String getFeedbackUrl() {
        return feedbackUrl;
    }
}
