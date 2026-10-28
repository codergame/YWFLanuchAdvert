package com.ywf.lanuchadvert;

import jakarta.annotation.Priority;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpSession;
import jakarta.ws.rs.Priorities;
import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.container.ContainerRequestFilter;
import jakarta.ws.rs.core.Context;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.ext.Provider;

import java.util.Map;

@Provider
@Priority(Priorities.AUTHENTICATION)
public class AuthFilter implements ContainerRequestFilter {
    @Context
    private HttpServletRequest request;

    @Override
    public void filter(ContainerRequestContext context) {
        String path = context.getUriInfo().getPath();
        if ("login".equals(path) || path.endsWith("/login")) {
            return;
        }
        HttpSession session = request.getSession(false);
        if (session == null || session.getAttribute("admin") == null) {
            context.abortWith(Response.status(401)
                    .type(MediaType.APPLICATION_JSON)
                    .entity(Map.of("error", "请先登录"))
                    .build());
        }
    }
}
