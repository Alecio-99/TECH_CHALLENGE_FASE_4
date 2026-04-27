package com.techchallenge.feedback.model;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;

import java.time.Instant;
import java.util.HashMap;
import java.util.Map;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class Feedback {
    private String id;
    private String descricao;
    private int nota;
    private String urgencia;
    private String dataEnvio;

    public Map<String, AttributeValue> toAttributeValueMap() {
        Map<String, AttributeValue> item = new HashMap<>();
        item.put("id", AttributeValue.builder().s(id).build());
        item.put("descricao", AttributeValue.builder().s(descricao).build());
        item.put("nota", AttributeValue.builder().n(String.valueOf(nota)).build());
        item.put("urgencia", AttributeValue.builder().s(urgencia).build());
        item.put("dataEnvio", AttributeValue.builder().s(dataEnvio).build());
        return item;
    }

    public static Feedback fromAttributeValueMap(Map<String, AttributeValue> map) {
        return Feedback.builder()
                .id(map.get("id").s())
                .descricao(map.get("descricao").s())
                .nota(Integer.parseInt(map.get("nota").n()))
                .urgencia(map.get("urgencia").s())
                .dataEnvio(map.get("dataEnvio").s())
                .build();
    }
}
