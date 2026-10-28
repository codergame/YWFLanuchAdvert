package com.ywf.lanuchadvert;

import java.nio.file.Path;

public final class PathsUtil {
    private PathsUtil() {
    }

    public static Path resolveInside(Path root, String relative) {
        if (relative == null || relative.isBlank()) {
            throw new IllegalArgumentException("路径为空");
        }
        String normalized = relative.replace('\\', '/');
        if (normalized.startsWith("/") || normalized.contains("..")) {
            throw new IllegalArgumentException("路径非法");
        }
        Path target = root.resolve(normalized).normalize();
        if (!target.startsWith(root.normalize())) {
            throw new IllegalArgumentException("路径非法");
        }
        return target;
    }
}
