package com.ywf.lanuchadvert;

import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.core.StreamingOutput;

import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;

public final class RangeResponses {
    private RangeResponses() {
    }

    public static Response zip(Path file, String rangeHeader, String downloadName) throws Exception {
        long length = Files.size(file);
        long start = 0;
        long end = length == 0 ? 0 : length - 1;
        boolean partial = false;
        if (rangeHeader != null && rangeHeader.startsWith("bytes=") && length > 0) {
            partial = true;
            String spec = rangeHeader.substring("bytes=".length()).split(",")[0].trim();
            int dash = spec.indexOf('-');
            if (dash < 0) {
                return Response.status(416).header("Content-Range", "bytes */" + length).header("Accept-Ranges", "bytes").build();
            }
            String left = spec.substring(0, dash).trim();
            String right = spec.substring(dash + 1).trim();
            try {
                if (left.isEmpty()) {
                    long suffix = Long.parseLong(right);
                    start = Math.max(0, length - suffix);
                } else {
                    start = Long.parseLong(left);
                    if (!right.isEmpty()) {
                        end = Long.parseLong(right);
                    }
                }
            } catch (NumberFormatException exception) {
                return Response.status(416).header("Content-Range", "bytes */" + length).header("Accept-Ranges", "bytes").build();
            }
            if (start < 0 || start >= length || end < start) {
                return Response.status(416).header("Content-Range", "bytes */" + length).header("Accept-Ranges", "bytes").build();
            }
            if (end >= length) {
                end = length - 1;
            }
        }
        final long from = start;
        final long to = length == 0 ? -1 : end;
        final long count = length == 0 ? 0 : to - from + 1;
        StreamingOutput body = output -> {
            try (InputStream input = Files.newInputStream(file)) {
                long skipped = 0;
                while (skipped < from) {
                    long step = input.skip(from - skipped);
                    if (step <= 0) {
                        break;
                    }
                    skipped += step;
                }
                byte[] buffer = new byte[8192];
                long left = count;
                while (left > 0) {
                    int read = input.read(buffer, 0, (int) Math.min(buffer.length, left));
                    if (read < 0) {
                        break;
                    }
                    output.write(buffer, 0, read);
                    left -= read;
                }
            }
        };
        Response.ResponseBuilder builder = Response.status(partial ? 206 : 200)
                .type("application/zip")
                .header("Accept-Ranges", "bytes")
                .header("Content-Length", count)
                .header("Content-Disposition", "attachment; filename=\"" + downloadName + "\"")
                .entity(body);
        if (partial) {
            builder.header("Content-Range", "bytes " + from + "-" + to + "/" + length);
        }
        return builder.build();
    }
}
