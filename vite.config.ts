import { readFileSync } from "node:fs";
import { type Plugin, defineConfig } from "vite";
import { logoSvg } from "./src/app/logo.ts";

/**
 * 素の favicon を `/favicon.svg` に置く。形の源は logo.ts、色の源は
 * style.css の `--accent` — どちらも実行時と同じ 1 つを読む（静的ファイルを
 * 手で置くと源が 2 つになり、以前 favicon だけ左右が反転していたのと同じ
 * 事故になる）。JS が走る前からタブに出て、`/favicon.ico` の 404 も消える。
 * 色と未保存の印は theme.ts が data URL で上書きする。
 */
function favicon(): Plugin {
  const file = "favicon.svg";
  const svg = (): string => {
    const m = /--accent:\s*(#[0-9a-f]{6})/i.exec(readFileSync("src/style.css", "utf8"));
    if (!m) throw new Error("style.css の --accent が読めない");
    return logoSvg(m[1]);
  };
  return {
    name: "favicon",
    configureServer(server) {
      server.middlewares.use((req, res, next) => {
        if (req.url !== `/${file}`) return next();
        res.setHeader("Content-Type", "image/svg+xml");
        res.end(svg());
      });
    },
    generateBundle() {
      this.emitFile({ type: "asset", fileName: file, source: svg() });
    },
  };
}

// 13131 = m は 13 番目のアルファベット(mmm)、かつ回文（鏡=mirror）。
// 他プロジェクトの既定ポート(5173等)と衝突しない専用ポート。
export default defineConfig({
  plugins: [favicon()],
  server: {
    port: 13131,
    strictPort: true,
  },
});
