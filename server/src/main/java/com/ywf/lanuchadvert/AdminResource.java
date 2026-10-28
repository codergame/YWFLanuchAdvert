package com.ywf.lanuchadvert;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.DELETE;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.PUT;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.Context;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import org.glassfish.jersey.media.multipart.FormDataContentDisposition;
import org.glassfish.jersey.media.multipart.FormDataParam;

import java.io.InputStream;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.time.Duration;
import java.time.OffsetDateTime;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.stream.Stream;

@Path("/")
@Produces(MediaType.APPLICATION_JSON)
public class AdminResource {
    private static final ObjectMapper MAPPER = new ObjectMapper();
    private static final HttpClient HTTP = HttpClient.newBuilder()
            .followRedirects(HttpClient.Redirect.NORMAL)
            .connectTimeout(Duration.ofSeconds(20))
            .build();

    @POST
    @Path("login")
    @Consumes(MediaType.APPLICATION_JSON)
    public Response login(Map<String, String> body, @Context HttpServletRequest request) {
        String username = body == null ? "" : body.getOrDefault("username", "");
        String password = body == null ? "" : body.getOrDefault("password", "");
        String expectUser = env("LAUNCHADVERT_ADMIN_USER", "admin");
        String expectPass = env("LAUNCHADVERT_ADMIN_PASSWORD", "admin");
        if (!constantEquals(username, expectUser) || !constantEquals(password, expectPass)) {
            return error(401, "账号或口令错误");
        }
        request.getSession(true).setAttribute("admin", username);
        return Response.ok(Map.of("ok", true)).build();
    }

    @POST
    @Path("logout")
    public Response logout(@Context HttpServletRequest request) {
        var session = request.getSession(false);
        if (session != null) {
            session.invalidate();
        }
        return Response.ok(Map.of("ok", true)).build();
    }

    @GET
    @Path("me")
    public Response me() {
        return Response.ok(Map.of("ok", true)).build();
    }

    @GET
    @Path("ads")
    public Response list() throws Exception {
        ArrayNode array = MAPPER.createArrayNode();
        for (Database.AdRecord record : App.database.list()) {
            array.add(summary(record));
        }
        return Response.ok(array).build();
    }

    @POST
    @Path("ads")
    @Consumes(MediaType.APPLICATION_JSON)
    public Response create(Map<String, String> body) throws Exception {
        String name = body == null ? "" : body.getOrDefault("name", "").trim();
        String appKey = body == null ? "default" : body.getOrDefault("appKey", "default").trim();
        if (name.isEmpty()) {
            return error(400, "请填写广告名称");
        }
        if (appKey.isEmpty()) {
            appKey = "default";
        }
        long id = App.database.insertAd(name, appKey);
        return Response.ok(detail(App.database.find(id))).build();
    }

    @GET
    @Path("ads/{id}")
    public Response get(@PathParam("id") long id) throws Exception {
        Database.AdRecord record = App.database.find(id);
        if (record == null) {
            return error(404, "广告不存在");
        }
        return Response.ok(detail(record)).build();
    }

    @DELETE
    @Path("ads/{id}")
    public Response delete(@PathParam("id") long id) throws Exception {
        if (App.database.find(id) == null) {
            return error(404, "广告不存在");
        }
        App.database.delete(id);
        deleteTree(assets(id));
        Files.deleteIfExists(packageFile(id));
        return Response.ok(Map.of("ok", true)).build();
    }

    @POST
    @Path("ads/{id}/assets")
    @Consumes(MediaType.MULTIPART_FORM_DATA)
    public Response upload(@PathParam("id") long id,
                           @FormDataParam("file") InputStream input,
                           @FormDataParam("file") FormDataContentDisposition disposition,
                           @FormDataParam("path") String path) throws Exception {
        if (App.database.find(id) == null) {
            return error(404, "广告不存在");
        }
        if (input == null) {
            return error(400, "请选择文件");
        }
        String relative = sanitize(path != null && !path.isBlank() ? path : fileName(disposition));
        if (relative == null || "layout.json".equals(relative)) {
            return error(400, "文件路径非法");
        }
        java.nio.file.Path root = assets(id);
        java.nio.file.Path destination = root.resolve(relative).normalize();
        if (!destination.startsWith(root)) {
            return error(400, "文件路径非法");
        }
        Files.createDirectories(destination.getParent());
        Files.copy(input, destination, java.nio.file.StandardCopyOption.REPLACE_EXISTING);
        App.database.markAssetsDirty(id);
        return Response.ok(Map.of("path", relative)).build();
    }

    @GET
    @Path("ads/{id}/assets/file")
    public Response assetFile(@PathParam("id") long id, @QueryParam("path") String path) throws Exception {
        String relative = sanitize(path);
        if (relative == null) {
            return error(400, "文件路径非法");
        }
        java.nio.file.Path file = assets(id).resolve(relative).normalize();
        if (!file.startsWith(assets(id)) || !Files.isRegularFile(file)) {
            return error(404, "文件不存在");
        }
        String type = Files.probeContentType(file);
        return Response.ok(Files.readAllBytes(file))
                .type(type == null ? MediaType.APPLICATION_OCTET_STREAM : type)
                .build();
    }

    @DELETE
    @Path("ads/{id}/assets")
    public Response deleteAsset(@PathParam("id") long id, @QueryParam("path") String path) throws Exception {
        String relative = sanitize(path);
        if (relative == null) {
            return error(400, "文件路径非法");
        }
        java.nio.file.Path file = assets(id).resolve(relative).normalize();
        if (!file.startsWith(assets(id))) {
            return error(400, "文件路径非法");
        }
        Files.deleteIfExists(file);
        App.database.markAssetsDirty(id);
        return Response.ok(Map.of("ok", true)).build();
    }

    @POST
    @Path("ads/{id}/store")
    @Consumes(MediaType.APPLICATION_JSON)
    public Response store(@PathParam("id") long id, JsonNode body) throws Exception {
        Database.AdRecord record = App.database.find(id);
        if (record == null) {
            return error(404, "广告不存在");
        }
        JsonNode layout = body.get("layout");
        String name = body.path("name").asText(record.name).trim();
        if (name.isEmpty()) {
            return error(400, "请填写广告名称");
        }
        if (layout == null || !layout.isObject()) {
            return error(400, "缺少布局");
        }
        List<String> errors = LayoutValidator.validate(layout, assets(id));
        if (!errors.isEmpty()) {
            return error(400, String.join("\n", errors));
        }
        byte[] json = MAPPER.writeValueAsBytes(layout);
        String md5 = ZipPacker.write(assets(id), json, packageFile(id));
        App.database.markStored(id, name, MAPPER.writeValueAsString(layout), md5);
        return Response.ok(detail(App.database.find(id))).build();
    }

    @PUT
    @Path("ads/{id}/link")
    @Consumes(MediaType.APPLICATION_JSON)
    public Response link(@PathParam("id") long id, JsonNode body, @Context HttpServletRequest request) throws Exception {
        Database.AdRecord record = App.database.find(id);
        if (record == null) {
            return error(404, "广告不存在");
        }
        if (record.packageMd5 == null || !Files.isRegularFile(packageFile(id))) {
            return error(400, "请先存储广告并生成 zip");
        }
        String source = body.path("source").asText("");
        if ("server".equals(source)) {
            App.database.markLink(id, "server", null, true);
            return Response.ok(detail(App.database.find(id))).build();
        }
        if (!"cdn".equals(source)) {
            return error(400, "素材来源只能是 cdn 或 server");
        }
        String url = body.path("url").asText("").trim();
        if (!url.startsWith("https://")) {
            return error(400, "CDN 链接必须是 https");
        }
        java.nio.file.Path temp = Files.createTempFile("lanuchadvert-", ".zip");
        try {
            HttpRequest httpRequest = HttpRequest.newBuilder(URI.create(url))
                    .timeout(Duration.ofMinutes(2))
                    .GET()
                    .build();
            HttpResponse<java.nio.file.Path> response = HTTP.send(httpRequest, HttpResponse.BodyHandlers.ofFile(temp));
            if (response.statusCode() != 200) {
                return error(400, "拉取 CDN 失败，HTTP " + response.statusCode());
            }
            String remoteMd5 = ZipPacker.md5(temp);
            if (!remoteMd5.equalsIgnoreCase(record.packageMd5)) {
                return error(400, "CDN 文件 MD5 与服务器生成的 zip 不一致");
            }
        } finally {
            Files.deleteIfExists(temp);
        }
        App.database.markLink(id, "cdn", url, true);
        return Response.ok(detail(App.database.find(id))).build();
    }

    @POST
    @Path("ads/{id}/publish")
    @Consumes(MediaType.APPLICATION_JSON)
    public Response publish(@PathParam("id") long id, JsonNode body) throws Exception {
        Database.AdRecord record = App.database.find(id);
        if (record == null) {
            return error(404, "广告不存在");
        }
        if (!record.packageVerified || record.packageMd5 == null || !Files.isRegularFile(packageFile(id))) {
            return error(400, "请先完成素材链接校验");
        }
        if (record.layoutJson == null) {
            return error(400, "请先存储广告");
        }
        if (!body.has("duration") || !body.get("duration").isIntegralNumber() || !body.get("duration").canConvertToInt()) {
            return error(400, "展示时长必须是整数");
        }
        int duration = body.get("duration").intValue();
        int priority = body.path("priority").asInt(0);
        String start = body.path("startTime").asText("");
        String end = body.path("endTime").asText("");
        OffsetDateTime startTime;
        OffsetDateTime endTime;
        try {
            startTime = OffsetDateTime.parse(start);
            endTime = OffsetDateTime.parse(end);
        } catch (Exception exception) {
            return error(400, "生效时间格式不正确");
        }
        if (!startTime.isBefore(endTime)) {
            return error(400, "生效结束时间必须晚于开始时间");
        }
        ObjectNode layout = (ObjectNode) MAPPER.readTree(record.layoutJson);
        layout.put("duration", duration);
        List<String> errors = LayoutValidator.validate(layout, assets(id));
        if (!errors.isEmpty()) {
            return error(400, String.join("\n", errors));
        }
        App.database.publish(id, MAPPER.writeValueAsString(layout), start, end, duration, priority);
        return Response.ok(detail(App.database.find(id))).build();
    }

    private ObjectNode summary(Database.AdRecord record) throws Exception {
        ObjectNode node = MAPPER.createObjectNode();
        node.put("id", record.id);
        node.put("name", record.name);
        node.put("appKey", record.appKey);
        node.put("status", record.status);
        node.put("priority", record.priority);
        if (record.duration != null) {
            node.put("duration", record.duration);
        } else {
            node.putNull("duration");
        }
        putText(node, "startTime", record.startTime);
        putText(node, "endTime", record.endTime);
        node.put("impressionCount", App.database.countEvents(record.id, "impression"));
        node.put("clickCount", App.database.countEvents(record.id, "click"));
        node.put("updatedAt", record.updatedAt);
        return node;
    }

    private ObjectNode detail(Database.AdRecord record) throws Exception {
        ObjectNode node = summary(record);
        if (record.layoutJson != null) {
            node.set("layout", MAPPER.readTree(record.layoutJson));
        } else {
            node.putNull("layout");
        }
        putText(node, "packageMd5", record.packageMd5);
        putText(node, "packageSource", record.packageSource);
        node.put("packageVerified", record.packageVerified);
        putText(node, "packageUrl", "cdn".equals(record.packageSource) ? record.packageUrl : null);
        ArrayNode assets = node.putArray("assets");
        java.nio.file.Path root = assets(record.id);
        if (Files.isDirectory(root)) {
            try (Stream<java.nio.file.Path> walk = Files.walk(root)) {
                walk.filter(Files::isRegularFile)
                        .sorted(Comparator.comparing(path -> root.relativize(path).toString()))
                        .forEach(path -> assets.add(root.relativize(path).toString().replace('\\', '/')));
            }
        }
        return node;
    }

    private static java.nio.file.Path assets(long id) {
        return App.home.resolve("assets").resolve(Long.toString(id));
    }

    private static java.nio.file.Path packageFile(long id) {
        return App.home.resolve("packages").resolve(id + ".zip");
    }

    private static void deleteTree(java.nio.file.Path root) throws Exception {
        if (!Files.exists(root)) {
            return;
        }
        try (Stream<java.nio.file.Path> walk = Files.walk(root)) {
            for (java.nio.file.Path path : walk.sorted(Comparator.reverseOrder()).collect(java.util.stream.Collectors.toList())) {
                Files.deleteIfExists(path);
            }
        }
    }

    private static String sanitize(String raw) {
        if (raw == null) {
            return null;
        }
        String name = raw.replace('\\', '/').trim();
        while (name.startsWith("/")) {
            name = name.substring(1);
        }
        if (name.isBlank() || name.contains("..") || name.contains("\0")) {
            return null;
        }
        String lower = name.toLowerCase(Locale.ROOT);
        if (!(lower.endsWith(".png") || lower.endsWith(".jpg") || lower.endsWith(".jpeg")
                || lower.endsWith(".gif") || lower.endsWith(".webp") || lower.endsWith(".html")
                || lower.endsWith(".htm") || lower.endsWith(".css") || lower.endsWith(".js")
                || lower.endsWith(".svg") || lower.endsWith(".json") || lower.endsWith(".txt"))) {
            return null;
        }
        return name;
    }

    private static String fileName(FormDataContentDisposition disposition) {
        if (disposition == null || disposition.getFileName() == null) {
            return "";
        }
        String name = disposition.getFileName().replace('\\', '/');
        int slash = name.lastIndexOf('/');
        return slash >= 0 ? name.substring(slash + 1) : name;
    }

    private static void putText(ObjectNode node, String field, String value) {
        if (value == null) {
            node.putNull(field);
        } else {
            node.put(field, value);
        }
    }

    private static Response error(int status, String message) {
        return Response.status(status).entity(Map.of("error", message)).build();
    }

    private static String env(String name, String fallback) {
        String value = System.getenv(name);
        return value == null || value.isBlank() ? fallback : value;
    }

    private static boolean constantEquals(String left, String right) {
        return MessageDigest.isEqual(left.getBytes(java.nio.charset.StandardCharsets.UTF_8),
                right.getBytes(java.nio.charset.StandardCharsets.UTF_8));
    }
}
