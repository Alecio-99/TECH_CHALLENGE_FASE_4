package com.techchallenge.feedback;

import com.techchallenge.feedback.client.FeedbackFunctionUrlClient;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.WebApplicationType;
import org.springframework.context.ConfigurableApplicationContext;

import java.net.http.HttpResponse;

public class FeedbackFunctionUrlManualTest {

    public static void main(String[] args) throws Exception {
        String descricao = args.length > 0 ? args[0] : "Aula foi muito confusa e o audio estava ruim";
        int nota = args.length > 1 ? Integer.parseInt(args[1]) : 3;

        SpringApplication application = new SpringApplication(FeedbackApplication.class);
        application.setWebApplicationType(WebApplicationType.NONE);

        try (ConfigurableApplicationContext context = application.run(args)) {
            FeedbackFunctionUrlClient client = context.getBean(FeedbackFunctionUrlClient.class);

            System.out.println("Chamando app.feedback-url: " + client.getFeedbackUrl());
            System.out.println("Descricao: " + descricao);
            System.out.println("Nota: " + nota);

            HttpResponse<String> response = client.enviarFeedback(descricao, nota);

            System.out.println("Status: " + response.statusCode());
            System.out.println("Resposta: " + response.body());
        }
    }
}
