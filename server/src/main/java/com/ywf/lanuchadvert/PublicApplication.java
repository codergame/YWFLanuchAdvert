package com.ywf.lanuchadvert;

import org.glassfish.jersey.jackson.JacksonFeature;
import org.glassfish.jersey.server.ResourceConfig;

public class PublicApplication extends ResourceConfig {
    public PublicApplication() {
        register(PublicAdsResource.class);
        register(JacksonFeature.class);
    }
}
