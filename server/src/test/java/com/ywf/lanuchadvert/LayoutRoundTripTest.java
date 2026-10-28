package com.ywf.lanuchadvert;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.zip.ZipFile;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class LayoutRoundTripTest {
    private final ObjectMapper mapper = new ObjectMapper();

    @Test
    void sampleLayoutValidatesAndPacks(@TempDir Path dir) throws Exception {
        Path assets = dir.resolve("assets");
        Files.createDirectories(assets.resolve("images"));
        Files.write(assets.resolve("images/hero.png"), new byte[]{1, 2, 3, 4});
        JsonNode layout = mapper.readTree(Path.of("../schema/sample-splash.json").toFile());
        List<String> errors = LayoutValidator.validate(layout, assets);
        assertTrue(errors.isEmpty(), String.join("\n", errors));
        Path zip = dir.resolve("packages/1.zip");
        String first = ZipPacker.write(assets, mapper.writeValueAsBytes(layout), zip);
        String second = ZipPacker.md5(zip);
        assertEquals(first, second);
        try (ZipFile archive = new ZipFile(zip.toFile())) {
            assertTrue(archive.getEntry("layout.json") != null);
            assertTrue(archive.getEntry("images/hero.png") != null);
            assertEquals(0, archive.getEntry("images/hero.png").getMethod());
        }
        ObjectMapper check = mapper;
        JsonNode packed = check.readTree(new String(readEntry(zip, "layout.json"), StandardCharsets.UTF_8));
        assertEquals(5, packed.get("duration").asInt());
    }

    @Test
    void negativeDurationIsValid(@TempDir Path dir) throws Exception {
        JsonNode layout = mapper.readTree(Path.of("../schema/sample-splash.json").toFile());
        ((com.fasterxml.jackson.databind.node.ObjectNode) layout).put("duration", -1);
        Path assets = dir.resolve("assets");
        Files.createDirectories(assets.resolve("images"));
        Files.write(assets.resolve("images/hero.png"), new byte[]{9});
        assertTrue(LayoutValidator.validate(layout, assets).isEmpty());
    }

    private static byte[] readEntry(Path zip, String name) throws Exception {
        try (ZipFile archive = new ZipFile(zip.toFile())) {
            return archive.getInputStream(archive.getEntry(name)).readAllBytes();
        }
    }
}
