import { defineConfig } from "vite";

// 13131 = m は 13 番目のアルファベット(mmm)、かつ回文（鏡=mirror）。
// 他プロジェクトの既定ポート(5173等)と衝突しない専用ポート。
export default defineConfig({
  server: {
    port: 13131,
    strictPort: true,
  },
});
