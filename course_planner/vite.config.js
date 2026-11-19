import { defineConfig } from "vite";
export default defineConfig({
  base: "./",
  build: {
    outDir: "../site/planner",
    emptyOutDir: true,
    assetsDir: "",
    license: { fileName: "licenses.md" },
    rollupOptions: {
      output: {
        entryFileNames: "planner.js",
        assetFileNames: "[name][extname]",
      },
    },
  },
});
