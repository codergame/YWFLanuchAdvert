package com.ywf.lanuchadvert;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;
import java.nio.file.Path;
import java.util.stream.Collectors;

public final class Database {
    private final Connection connection;

    public Database(Path dbFile) throws SQLException {
        try {
            Class.forName("org.sqlite.JDBC");
        } catch (ClassNotFoundException exception) {
            throw new SQLException("找不到 sqlite-jdbc", exception);
        }
        connection = DriverManager.getConnection("jdbc:sqlite:" + dbFile.toAbsolutePath());
        try (Statement statement = connection.createStatement()) {
            statement.execute("PRAGMA journal_mode=WAL");
            statement.execute("PRAGMA busy_timeout=5000");
        }
    }

    public synchronized void init() throws Exception {
        String sql;
        try (InputStream input = Database.class.getResourceAsStream("/schema.sql")) {
            if (input == null) {
                throw new IllegalStateException("缺少 schema.sql");
            }
            sql = new BufferedReader(new InputStreamReader(input, StandardCharsets.UTF_8))
                    .lines()
                    .collect(Collectors.joining("\n"));
        }
        try (Statement statement = connection.createStatement()) {
            for (String part : sql.split(";")) {
                String trimmed = part.trim();
                if (!trimmed.isEmpty()) {
                    statement.execute(trimmed);
                }
            }
            try (ResultSet rows = statement.executeQuery("SELECT COUNT(*) FROM schema_version")) {
                rows.next();
                if (rows.getInt(1) == 0) {
                    statement.execute("INSERT INTO schema_version (version) VALUES (1)");
                }
            }
        }
    }

    public synchronized void close() {
        try {
            connection.close();
        } catch (SQLException ignored) {
            // 容器关闭时连接可能已经释放。
        }
    }

    public synchronized long insertAd(String name, String appKey) throws SQLException {
        String now = now();
        try (PreparedStatement statement = connection.prepareStatement(
                "INSERT INTO ads (app_key, name, status, created_at, updated_at) VALUES (?, ?, 'draft', ?, ?)",
                Statement.RETURN_GENERATED_KEYS)) {
            statement.setString(1, appKey);
            statement.setString(2, name);
            statement.setString(3, now);
            statement.setString(4, now);
            statement.executeUpdate();
            try (ResultSet keys = statement.getGeneratedKeys()) {
                keys.next();
                return keys.getLong(1);
            }
        }
    }

    public synchronized AdRecord find(long id) throws SQLException {
        try (PreparedStatement statement = connection.prepareStatement("SELECT * FROM ads WHERE id = ?")) {
            statement.setLong(1, id);
            try (ResultSet rows = statement.executeQuery()) {
                if (!rows.next()) {
                    return null;
                }
                return read(rows);
            }
        }
    }

    public synchronized List<AdRecord> list() throws SQLException {
        List<AdRecord> ads = new ArrayList<>();
        try (Statement statement = connection.createStatement();
             ResultSet rows = statement.executeQuery("SELECT * FROM ads ORDER BY updated_at DESC, id DESC")) {
            while (rows.next()) {
                ads.add(read(rows));
            }
        }
        return ads;
    }

    public synchronized List<AdRecord> listPublished(String appKey) throws SQLException {
        List<AdRecord> ads = new ArrayList<>();
        try (PreparedStatement statement = connection.prepareStatement(
                "SELECT * FROM ads WHERE status = 'published' AND app_key = ? ORDER BY priority DESC, updated_at DESC")) {
            statement.setString(1, appKey);
            try (ResultSet rows = statement.executeQuery()) {
                while (rows.next()) {
                    ads.add(read(rows));
                }
            }
        }
        return ads;
    }

    public synchronized void markAssetsDirty(long id) throws SQLException {
        try (PreparedStatement statement = connection.prepareStatement(
                "UPDATE ads SET status = 'draft', package_verified = 0, updated_at = ? WHERE id = ?")) {
            statement.setString(1, now());
            statement.setLong(2, id);
            statement.executeUpdate();
        }
    }

    public synchronized void markStored(long id, String name, String layoutJson, String md5) throws SQLException {
        try (PreparedStatement statement = connection.prepareStatement(
                "UPDATE ads SET name = ?, layout_json = ?, status = 'stored', package_md5 = ?, package_url = NULL, "
                        + "package_source = NULL, package_verified = 0, updated_at = ? WHERE id = ?")) {
            statement.setString(1, name);
            statement.setString(2, layoutJson);
            statement.setString(3, md5);
            statement.setString(4, now());
            statement.setLong(5, id);
            statement.executeUpdate();
        }
    }

    public synchronized void markLink(long id, String source, String url, boolean verified) throws SQLException {
        try (PreparedStatement statement = connection.prepareStatement(
                "UPDATE ads SET package_source = ?, package_url = ?, package_verified = ?, updated_at = ? WHERE id = ?")) {
            statement.setString(1, source);
            statement.setString(2, url);
            statement.setInt(3, verified ? 1 : 0);
            statement.setString(4, now());
            statement.setLong(5, id);
            statement.executeUpdate();
        }
    }

    public synchronized void publish(long id, String layoutJson, String start, String end, int duration, int priority) throws SQLException {
        try (PreparedStatement statement = connection.prepareStatement(
                "UPDATE ads SET layout_json = ?, start_time = ?, end_time = ?, duration = ?, priority = ?, "
                        + "status = 'published', updated_at = ? WHERE id = ?")) {
            statement.setString(1, layoutJson);
            statement.setString(2, start);
            statement.setString(3, end);
            statement.setInt(4, duration);
            statement.setInt(5, priority);
            statement.setString(6, now());
            statement.setLong(7, id);
            statement.executeUpdate();
        }
    }

    public synchronized void delete(long id) throws SQLException {
        try (PreparedStatement events = connection.prepareStatement("DELETE FROM events WHERE ad_id = ?")) {
            events.setLong(1, id);
            events.executeUpdate();
        }
        try (PreparedStatement ads = connection.prepareStatement("DELETE FROM ads WHERE id = ?")) {
            ads.setLong(1, id);
            ads.executeUpdate();
        }
    }

    public synchronized void addEvent(long id, String type) throws SQLException {
        try (PreparedStatement statement = connection.prepareStatement(
                "INSERT INTO events (ad_id, type, created_at) VALUES (?, ?, ?)")) {
            statement.setLong(1, id);
            statement.setString(2, type);
            statement.setString(3, now());
            statement.executeUpdate();
        }
    }

    public synchronized int countEvents(long id, String type) throws SQLException {
        try (PreparedStatement statement = connection.prepareStatement(
                "SELECT COUNT(*) FROM events WHERE ad_id = ? AND type = ?")) {
            statement.setLong(1, id);
            statement.setString(2, type);
            try (ResultSet rows = statement.executeQuery()) {
                rows.next();
                return rows.getInt(1);
            }
        }
    }

    private static AdRecord read(ResultSet rows) throws SQLException {
        AdRecord record = new AdRecord();
        record.id = rows.getLong("id");
        record.appKey = rows.getString("app_key");
        record.name = rows.getString("name");
        record.status = rows.getString("status");
        record.priority = rows.getInt("priority");
        record.layoutJson = rows.getString("layout_json");
        int duration = rows.getInt("duration");
        record.duration = rows.wasNull() ? null : duration;
        record.startTime = rows.getString("start_time");
        record.endTime = rows.getString("end_time");
        record.packageUrl = rows.getString("package_url");
        record.packageMd5 = rows.getString("package_md5");
        record.packageSource = rows.getString("package_source");
        record.packageVerified = rows.getInt("package_verified") == 1;
        record.createdAt = rows.getString("created_at");
        record.updatedAt = rows.getString("updated_at");
        return record;
    }

    public static String now() {
        return OffsetDateTime.now(ZoneOffset.UTC).format(DateTimeFormatter.ISO_INSTANT);
    }

    public static final class AdRecord {
        public long id;
        public String appKey;
        public String name;
        public String status;
        public int priority;
        public String layoutJson;
        public Integer duration;
        public String startTime;
        public String endTime;
        public String packageUrl;
        public String packageMd5;
        public String packageSource;
        public boolean packageVerified;
        public String createdAt;
        public String updatedAt;
    }
}
