import { defineConfig } from "vite";
import vue from "@vitejs/plugin-vue";

export default defineConfig({
  plugins: [vue()],
  build: {
    outDir: "../src/main/webapp",
    emptyOutDir: false,
    assetsDir: "assets"
  },
  server: {
    proxy: {
      "/admin/api": "http://127.0.0.1:8080",
      "/api": "http://127.0.0.1:8080"
    }
  }
});
