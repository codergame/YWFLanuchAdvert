package com.ywf.lanuchadvert;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.networknt.schema.JsonSchema;
import com.networknt.schema.JsonSchemaFactory;
import com.networknt.schema.SpecVersion;
import com.networknt.schema.ValidationMessage;

import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;

public final class LayoutValidator {
    private static final ObjectMapper MAPPER = new ObjectMapper();
    private static final JsonSchema SCHEMA = load();

    private LayoutValidator() {
    }

    public static List<String> validate(JsonNode document, Path assetRoot) {
        List<String> errors = new ArrayList<>();
        Set<ValidationMessage> messages = SCHEMA.validate(document);
        for (ValidationMessage message : messages) {
            errors.add(message.getMessage());
        }
        if (document != null && document.has("root")) {
            collect(document.get("root"), assetRoot, errors);
        }
        return errors;
    }

    private static void collect(JsonNode node, Path assetRoot, List<String> errors) {
        if (node == null || !node.isObject()) {
            return;
        }
        if ("image".equals(text(node, "type"))) {
            checkRef(text(node, "src"), assetRoot, errors);
        }
        JsonNode source = node.get("source");
        if (source != null && "zip".equals(text(source, "type"))) {
            String path = text(source, "path");
            if (path != null && path.startsWith("zip://")) {
                path = path.substring("zip://".length());
            }
            checkRelative(path, assetRoot, errors);
        }
        JsonNode click = node.get("click");
        if (click != null && "openUrl".equals(text(click, "type"))) {
            String url = text(click, "url");
            if (url == null || !(url.startsWith("https://") || url.startsWith("http://"))) {
                errors.add(text(node, "id") + " 的打开链接必须是 http 或 https");
            }
        }
        JsonNode children = node.get("children");
        if (children != null && children.isArray()) {
            for (JsonNode child : children) {
                collect(child, assetRoot, errors);
            }
        }
    }

    private static void checkRef(String ref, Path assetRoot, List<String> errors) {
        if (ref == null) {
            return;
        }
        if (ref.startsWith("bundle://")) {
            return;
        }
        if (!ref.startsWith("zip://")) {
            errors.add("图片地址必须是 zip:// 或 bundle://");
            return;
        }
        checkRelative(ref.substring("zip://".length()), assetRoot, errors);
    }

    private static void checkRelative(String relative, Path assetRoot, List<String> errors) {
        if (relative == null || relative.isBlank() || relative.contains("..") || relative.startsWith("/")) {
            errors.add("素材路径非法: " + relative);
            return;
        }
        if (assetRoot == null) {
            return;
        }
        Path file = assetRoot.resolve(relative).normalize();
        if (!file.startsWith(assetRoot.normalize()) || !Files.isRegularFile(file)) {
            errors.add("素材不存在: " + relative);
        }
    }

    private static String text(JsonNode node, String field) {
        JsonNode value = node.get(field);
        return value == null || value.isNull() ? null : value.asText();
    }

    private static JsonSchema load() {
        try (InputStream input = LayoutValidator.class.getResourceAsStream("/splash-layout.schema.json")) {
            if (input == null) {
                throw new IllegalStateException("缺少 splash-layout.schema.json");
            }
            JsonSchemaFactory factory = JsonSchemaFactory.getInstance(SpecVersion.VersionFlag.V7);
            return factory.getSchema(MAPPER.readTree(input));
        } catch (Exception exception) {
            throw new IllegalStateException("无法加载布局 Schema", exception);
        }
    }
}
