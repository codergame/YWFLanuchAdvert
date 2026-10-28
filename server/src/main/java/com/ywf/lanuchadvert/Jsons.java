package com.ywf.lanuchadvert;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;

public final class Jsons {
    public static final ObjectMapper MAPPER = new ObjectMapper();

    private Jsons() {
    }

    public static ObjectNode error(String message) {
        ObjectNode node = MAPPER.createObjectNode();
        node.put("error", message);
        return node;
    }
}
