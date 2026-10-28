package com.ywf.lanuchadvert;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.Context;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

import java.nio.file.Files;
import java.util.Map;

@Path("/v1/ads")
public class PublicAdsResource {
    private final ObjectMapper mapper = new ObjectMapper();

    @GET
    @Produces(MediaType.APPLICATION_JSON)
    public Response list(@QueryParam("appKey") String appKey, @Context HttpServletRequest request) throws Exception {
        String key = appKey == null || appKey.isBlank() ? "default" : appKey;
        ObjectNode root = mapper.createObjectNode();
        root.put("serverTime", Database.now());
        ArrayNode ads = root.putArray("ads");
        for (Database.AdRecord record : App.database.listPublished(key)) {
            if (record.layoutJson == null || record.packageMd5 == null) {
                continue;
            }
            ObjectNode ad = ads.addObject();
            ad.put("id", Long.toString(record.id));
            ad.put("priority", record.priority);
            ad.put("updatedAt", record.updatedAt);
            ad.put("startTime", record.startTime == null ? "" : record.startTime);
            ad.put("endTime", record.endTime == null ? "" : record.endTime);
            ad.put("packageUrl", packageUrl(record, request));
            ad.put("packageMd5", record.packageMd5);
            ObjectNode layout = (ObjectNode) mapper.readTree(record.layoutJson);
            if (record.duration != null) {
                layout.put("duration", record.duration);
            }
            ad.set("layout", layout);
        }
        return Response.ok(root).build();
    }

    @GET
    @Path("/{id}/package")
    public Response download(@PathParam("id") long id, @Context HttpServletRequest request) throws Exception {
        Database.AdRecord record = App.database.find(id);
        java.nio.file.Path file = App.home.resolve("packages").resolve(id + ".zip");
        if (record == null || !Files.isRegularFile(file)) {
            return Response.status(404).type(MediaType.APPLICATION_JSON)
                    .entity(Map.of("error", "素材包不存在")).build();
        }
        return RangeResponses.zip(file, request.getHeader("Range"), "ad-" + id + ".zip");
    }

    @POST
    @Path("/{id}/events")
    @Consumes(MediaType.APPLICATION_JSON)
    public Response event(@PathParam("id") long id, Map<String, String> body) throws Exception {
        Database.AdRecord record = App.database.find(id);
        if (record == null) {
            return Response.status(404).entity(Map.of("error", "广告不存在")).build();
        }
        String type = body == null ? "" : body.getOrDefault("type", "");
        if (!"impression".equals(type) && !"click".equals(type)) {
            return Response.status(400).entity(Map.of("error", "事件类型只能是 impression 或 click")).build();
        }
        App.database.addEvent(id, type);
        return Response.noContent().build();
    }

    private static String packageUrl(Database.AdRecord record, HttpServletRequest request) {
        if ("cdn".equals(record.packageSource) && record.packageUrl != null && !record.packageUrl.isBlank()) {
            return record.packageUrl;
        }
        String proto = header(request, "X-Forwarded-Proto", request.getScheme());
        String host = header(request, "X-Forwarded-Host", request.getHeader("Host"));
        String context = request.getContextPath() == null ? "" : request.getContextPath();
        return proto + "://" + host + context + "/api/v1/ads/" + record.id + "/package";
    }

    private static String header(HttpServletRequest request, String name, String fallback) {
        String value = request.getHeader(name);
        if (value == null || value.isBlank()) {
            return fallback;
        }
        int comma = value.indexOf(',');
        return (comma >= 0 ? value.substring(0, comma) : value).trim();
    }
}
