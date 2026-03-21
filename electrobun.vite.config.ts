import { resolve } from "node:path";
import react from "@vitejs/plugin-react";

const rootDir = import.meta.dir;

export default {
  renderer: {
    vite: {
      root: resolve(rootDir, "src/ui"),
      base: "./",
      plugins: [react()],
      build: {
        outDir: resolve(rootDir, "dist"),
        emptyOutDir: true,
        sourcemap: true,
        rollupOptions: {
          output: {
            entryFileNames: "assets/[name].js",
            chunkFileNames: "assets/[name].js",
            assetFileNames: "assets/[name][extname]",
          },
        },
      },
      server: {
        host: "127.0.0.1",
        port: 5173,
        strictPort: true,
      },
    },
  },
  electrobun: {
    configFile: false,
    outDir: "dist",
    config: ({ outDir }: { outDir: string }) => ({
      app: {
        name: "CX Switch",
        identifier: "com.bigo.cx-switch",
        version: "0.0.1",
      },
      runtime: {
        exitOnLastWindowClosed: false,
      },
      scripts: {
        postBuild: "scripts/postbuild.mjs",
      },
      build: {
        bun: {
          entrypoint: "src/bun/index.ts",
        },
        copy: {
          "logo.png": "views/app/assets/tray.png",
          [`${outDir}/index.html`]: "views/app/index.html",
          [`${outDir}/assets/index.css`]: "views/app/assets/index.css",
          [`${outDir}/assets/index.js`]: "views/app/assets/index.js",
        },
      },
    }),
  },
};
