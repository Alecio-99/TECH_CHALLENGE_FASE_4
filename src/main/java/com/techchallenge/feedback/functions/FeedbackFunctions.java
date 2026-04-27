package com.techchallenge.feedback.functions;

import com.techchallenge.feedback.model.Feedback;
import com.techchallenge.feedback.service.FeedbackService;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.util.List;
import java.util.Map;
import java.util.function.Function;
import java.util.function.Supplier;
import java.util.stream.Collectors;

@Configuration
public class FeedbackFunctions {

    private final FeedbackService feedbackService;

    public FeedbackFunctions(FeedbackService feedbackService) {
        this.feedbackService = feedbackService;
    }

    @Bean
    public Function<Feedback, Feedback> processarFeedback() {
        return feedbackService::salvarFeedback;
    }

    @Bean
    public Supplier<Map<String, Object>> gerarRelatorioSemanal() {
        return () -> {
            List<Feedback> feedbacks = feedbackService.listarFeedbacksUltimaSemana();

            double mediaAvaliacoes = feedbacks.stream()
                    .mapToInt(Feedback::getNota)
                    .average()
                    .orElse(0.0);

            long totalUrgenciaAlta = feedbacks.stream()
                    .filter(f -> "ALTA".equals(f.getUrgencia()))
                    .count();

            Map<String, Long> avaliacoesPorDia = feedbacks.stream()
                    .collect(Collectors.groupingBy(f -> f.getDataEnvio().substring(0, 10), Collectors.counting()));

            Map<String, Long> avaliacoesPorUrgencia = feedbacks.stream()
                    .collect(Collectors.groupingBy(Feedback::getUrgencia, Collectors.counting()));

            Map<String, Object> relatorio = Map.of(
                    "mediaAvaliacoes", mediaAvaliacoes,
                    "totalFeedbacks", feedbacks.size(),
                    "totalUrgenciaAlta", totalUrgenciaAlta,
                    "avaliacoesPorDia", avaliacoesPorDia,
                    "avaliacoesPorUrgencia", avaliacoesPorUrgencia
            );

            feedbackService.enviarRelatorioPorEmail(relatorio);
            return relatorio;
        };
    }
}
