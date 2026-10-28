package com.ywf.lanuchadvert;

import java.io.IOException;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.Comparator;
import java.util.stream.Stream;
import java.util.zip.CRC32;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;

public final class ZipPacker {
    private ZipPacker() {
    }

    public static String write(Path assetRoot, byte[] layoutJson, Path destination) throws Exception {
        Files.createDirectories(destination.getParent());
        Path temporary = destination.resolveSibling(destination.getFileName().toString() + ".tmp");
        try (OutputStream file = Files.newOutputStream(temporary);
             ZipOutputStream zip = new ZipOutputStream(file, StandardCharsets.UTF_8)) {
            if (Files.isDirectory(assetRoot)) {
                try (Stream<Path> walk = Files.walk(assetRoot)) {
                    for (Path path : walk.filter(Files::isRegularFile).sorted(Comparator.comparing(item -> assetRoot.relativize(item).toString())).collect(java.util.stream.Collectors.toList())) {
                        String name = assetRoot.relativize(path).toString().replace('\\', '/');
                        if ("layout.json".equals(name) || name.contains("..")) {
                            continue;
                        }
                        put(zip, name, Files.readAllBytes(path));
                    }
                }
            }
            put(zip, "layout.json", layoutJson);
        }
        Files.move(temporary, destination, java.nio.file.StandardCopyOption.REPLACE_EXISTING);
        return md5(destination);
    }

    private static void put(ZipOutputStream zip, String name, byte[] data) throws IOException {
        ZipEntry entry = new ZipEntry(name);
        CRC32 crc = new CRC32();
        crc.update(data);
        entry.setMethod(ZipEntry.STORED);
        entry.setSize(data.length);
        entry.setCompressedSize(data.length);
        entry.setCrc(crc.getValue());
        entry.setTime(0);
        zip.putNextEntry(entry);
        zip.write(data);
        zip.closeEntry();
    }

    public static String md5(Path file) throws Exception {
        MessageDigest digest = MessageDigest.getInstance("MD5");
        byte[] hash = digest.digest(Files.readAllBytes(file));
        StringBuilder builder = new StringBuilder();
        for (byte item : hash) {
            builder.append(String.format("%02x", item));
        }
        return builder.toString();
    }
}
