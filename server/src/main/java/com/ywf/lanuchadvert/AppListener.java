package com.ywf.lanuchadvert;

import jakarta.servlet.ServletContextEvent;
import jakarta.servlet.ServletContextListener;

import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

public final class AppListener implements ServletContextListener {
    @Override
    public void contextInitialized(ServletContextEvent event) {
        try {
            Path home = resolveHome();
            Files.createDirectories(home.resolve("assets"));
            Files.createDirectories(home.resolve("packages"));
            Database database = new Database(home.resolve("launchadvert.db"));
            database.init();
            App.home = home;
            App.database = database;
        } catch (Exception exception) {
            throw new IllegalStateException("初始化 SQLite 失败", exception);
        }
    }

    @Override
    public void contextDestroyed(ServletContextEvent event) {
        Database database = App.database;
        App.database = null;
        if (database != null) {
            database.close();
        }
    }

    static Path resolveHome() {
        String configured = System.getenv("LAUNCHADVERT_HOME");
        if (configured != null && !configured.isBlank()) {
            return Paths.get(configured);
        }
        String catalina = System.getProperty("catalina.base");
        if (catalina == null || catalina.isBlank()) {
            catalina = System.getProperty("user.dir");
        }
        return Paths.get(catalina, "launchadvert");
    }
}
