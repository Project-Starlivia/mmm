import { defineConfig } from "vite";

// Tauri との噛み合わせ。src-tauri/ は vite の監視から外す — target/ の
// ビルド中ファイルを掴んで EBUSY でクラッシュするため（フル再ビルド時に露見）。
// ポートは tauri.conf.json の devUrl と一致させ、勝手に変えさせない。
// 13131 = m は 13 番目のアルファベット(mmm)、かつ回文（鏡=mirror）。
// 他プロジェクトの既定ポート(5173等)と衝突しない専用ポート。
export default defineConfig({
  clearScreen: false, // vite の出力で tauri のログを消さない
  server: {
    port: 13131,
    strictPort: true,
    watch: { ignored: ["**/src-tauri/**"] },
  },
});
