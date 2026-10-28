package com.ywf.lanuchadvert;

import org.glassfish.jersey.jackson.JacksonFeature;
import org.glassfish.jersey.media.multipart.MultiPartFeature;
import org.glassfish.jersey.server.ResourceConfig;

public class AdminApplication extends ResourceConfig {
    public AdminApplication() {
        register(AdminResource.class);
        register(AuthFilter.class);
        register(JacksonFeature.class);
        register(MultiPartFeature.class);
    }
}
