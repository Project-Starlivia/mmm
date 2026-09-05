# 知見の集め方 — 実測

リファクタと性能の知見を外から引くときの、資料の在り処と取り方。取り口の事実だけを置く（個々の知見の中身は含まない）。

確認日 2026-09-05。環境 `node v24.16.0` / `tsc 5.9.3` / `moon 0.1.20260803 (c19f78e 2026-08-03)` / Windows 11。
HTTP は `curl -sL --max-time` で叩いた実測値（status とバイト数）。バイト数はその時点の応答長。

取り口は 3 つに分かれた。**索引を配っている**（llms.txt）、**生の markdown を配っている**（拡張子の流儀）、**手元で吐かせる**（CLI）。


## 1. 索引を配っているところ — llms.txt

`llms.txt` は [llmstxt.org](https://llmstxt.org/) の規約。H1 + 引用の要約 + H2 区切りのリンク表。
**そのパス配下の URL を覆う。複数当てはまるときは最も深いものを使う**（仕様の記述）。ルートに無くても下にあることがある。

| URL | status | bytes |
|---|---|---|
| `https://developer.chrome.com/docs/llms.txt` | 200 | 227,922 |
| `https://www.moonbitlang.com/llms.txt` | 200 | 218,707 |
| `https://web.dev/articles/llms.txt` | 200 | 176,828 |
| `https://oxc.rs/llms.txt` | 200 | 97,420 |
| `https://nodejs.org/llms.txt` | 200 | 14,179 |
| `https://vite.dev/llms.txt` | 200 | 3,528 |

`llms-full.txt`（本文を全部埋め込んだ版）:

| URL | status | bytes |
|---|---|---|
| `https://oxc.rs/llms-full.txt` | 200 | 1,670,539 |
| `https://www.moonbitlang.com/llms-full.txt` | 200 | 28,944 |

404 だったもの: `typescriptlang.org` / `developer.mozilla.org` / `docs.moonbitlang.com` / `typescript-eslint.io` / `biomejs.dev` / `v8.dev` の各ルート、`nodejs.org/llms-full.txt`、`docs.moonbitlang.com/llms-full.txt`。
`developer.chrome.com` と `web.dev` は**ルートが 404、下の階層が 200**。

中身の規模:
- `developer.chrome.com/docs/llms.txt` — リンク 1,191 本、H2 は `## Docs` の 1 つ
- `web.dev/articles/llms.txt` — リンク 817 本
- `nodejs.org/llms.txt` — H2 は `## API Documentations` の 1 つ。各 API ページの `.md` へのリンク
- `moonbitlang.com/llms.txt` — H2 は `Get started` / `Useful Sources` / `Tutorial` / `MoonBit Language` ほか

Lighthouse には `llms.txt` の監査項目がある（Agentic Browsing カテゴリ）。取得時にサーバエラーなら flag、404 なら Not Applicable（提供は任意のため）。


## 2. 生の markdown を配っているところ — 拡張子の流儀が 3 通り

**(a) `.md` を足す** — `Content-Type: text/markdown` が返る

| URL | status | bytes |
|---|---|---|
| `https://nodejs.org/docs/latest/api/cli.md` | 200 | 130,574 |
| `https://oxc.rs/docs/guide/usage/linter/rules/eslint/no-await-in-loop.md` | 200 | 796 |

**(b) `.md.txt` を足す** — Google 系（`web.dev` / `developer.chrome.com`）

| URL | status | Content-Type | bytes |
|---|---|---|---|
| `https://web.dev/articles/rendering-performance.md.txt` | 200 | text/markdown | 11,388 |
| `https://developer.chrome.com/docs/chromium/renderingng-architecture.md.txt` | 200 | text/markdown | 24,356 |

罠 — この 2 サイトは `.md` でも **200 を返すが `text/html`**（普通のページが返るだけ）。
`.md` で 200 が返ったからといって markdown とは限らない。**Content-Type を見ないと分からない**。
`llms.txt` の中のリンクは `.md.txt` で書かれているので、そこから辿れば間違えない。

**(c) 配っていない → GitHub の raw を叩く**

| URL | status | bytes |
|---|---|---|
| `raw.githubusercontent.com/mdn/content/main/files/en-us/web/svg/reference/element/path/index.md` | 200 | 1,528 |
| `raw.githubusercontent.com/typescript-eslint/typescript-eslint/main/packages/eslint-plugin/docs/rules/no-unnecessary-condition.mdx` | 200 | 10,263 |
| `raw.githubusercontent.com/eslint/eslint/main/docs/src/rules/no-await-in-loop.md` | 200 | 7,091 |

MDN は `.md` サフィックスが 404。ただし各ページに `index.json` がある
（`developer.mozilla.org/en-US/docs/Web/SVG/Reference/Element/path/index.json` → 200 / 39,170）。


## 3. npm レジストリに置かれている機械可読データ

`registry.npmjs.org/<pkg>/latest` で確認した最新版（2026-09-05 時点）。

| パッケージ | version | 中身 |
|---|---|---|
| `@mdn/browser-compat-data` | 8.1.0 | ブラウザ対応表の元データ（MDN の表はこれを描いている） |
| `web-features` | 3.37.0 | Web 機能の一覧（Baseline の元データ） |
| `eslint` | 10.10.0 | 組み込みルールと各ルールの `meta` |
| `typescript-eslint` | 8.69.0 | TS 向けルールと各ルールの `meta` |
| `oxlint` | 1.81.0 | Rust 実装の lint |


## 4. lint のルール表 = アンチパターンの目録

`oxc.rs/llms.txt` からルールページの URL を数えた内訳（合計 870）:

| namespace | 件数 |
|---|---|
| eslint | 187 |
| unicorn | 138 |
| typescript | 110 |
| react | 85 |
| vitest | 73 |
| jest | 60 |
| vue | 46 |
| jsx_a11y | 36 |
| import | 33 |
| oxc | 27 |
| jsdoc | 23 |
| nextjs | 21 |
| promise | 16 |
| node | 11 |
| react_perf | 4 |

各ルールページは 1 本の URL で markdown が取れる（上の (a)）。`llms-full.txt` を 1 回落とせば全部入り（1.6 MB）。


## 5. 手元で吐かせる — 実行して確かめたもの

### TypeScript

`tsc --noEmit --extendedDiagnostics` — このリポジトリで実行した出力そのもの:

```
Files:                         249
Lines of Library:            51394
Lines of Definitions:        66914
Lines of TypeScript:          8703
Identifiers:                108128
Symbols:                     87372
Types:                       16187
Instantiations:              13451
Memory used:               162736K
Program time:                0.28s
Bind time:                   0.09s
Check time:                  0.40s
Total time:                  0.77s
```

`tsc --noEmit --generateTrace <dir>` — `trace.json`（230,266 B）と `types.json`（4,467,513 B）が出た。
`trace.json` は Chrome の trace 形式でイベント 1,250 件。内訳:

```
createSourceFile 498 / bindSourceFile 498 / checkSourceFile 94 / checkExpression 72
findSourceFile 42 / structuredTypeRelatedTo 14 / checkVariableDeclaration 10
checkDeferredNode 5 / resolveModuleNamesWorker 3 / createProgram 2
```

`trace.json` は `chrome://tracing` や [ui.perfetto.dev](https://ui.perfetto.dev/) にそのまま流せる。
`npx @typescript/analyze-trace <dir>` でホットスポットの並びが出る（**未実行** — インストールが要るため確かめていない）。
TypeScript 4.1 で `--generateTrace` が入った。増分ビルドだと結果が歪むので `-f` / `--incremental false` を付けると良い、と wiki にある。

[TypeScript-wiki/Performance.md](https://github.com/microsoft/TypeScript-wiki/blob/main/Performance.md) が挙げているもの（そのまま列挙）:

- フラグ — `--incremental` `--skipDefaultLibCheck` `--skipLibCheck` `--strictFunctionTypes` `--isolatedModules` `--extendedDiagnostics` `--showConfig` `--listFilesOnly` `--listFiles` `--explainFiles` `--traceResolution` `--generateTrace` `--generateCpuProfile` `--emitDeclarationOnly`
- 道具 — `@typescript/analyze-trace` / `dexnode` / `pprof-it` / `pprof` / SpeedScope / `fork-ts-checker-webpack-plugin` / VS Code の `TypeScript: Open TS Server log`
- tsconfig — `files` / `include`・`exclude` / `types`（空配列を推奨）/ `typeRoots` / `paths` / `composite` / `disableReferencedProjectLoad` / `disableSolutionSearching`
- 遅くなる書き方として挙がっているもの — 交差型（`extends` の interface を推奨）/ 型注釈の省略（特に戻り値）/ 10 要素以上の大きな union / 複雑なインライン条件型 / `@types` の自動全取り込み / `include`・`exclude` の設定漏れ（`node_modules` や `.git` が混ざる）/ isolated module 変換下の const enum

### Node

`nodejs.org/docs/latest/api/cli.md` を落として見出しを機械抽出した結果、診断系のフラグ:

```
--cpu-prof  --cpu-prof-dir  --cpu-prof-interval  --cpu-prof-name
--heap-prof --heap-prof-dir --heap-prof-interval --heap-prof-name
--heap-snapshot-on-oom  --heapsnapshot-near-heap-limit  --heapsnapshot-signal  --track-heap-objects
--prof  --prof-process  --perf-basic-prof  --perf-basic-prof-only-functions  --perf-prof  --perf-prof-unwinding-info
--report-* (compact / dir / filename / on-fatalerror / on-signal / signal / uncaught-exception / exclude-env / exclude-network)
--trace-* (deprecation / env / env-js-stack / env-native-stack / event-categories / event-file-pattern /
           events-enabled / exit / require-module / sigint / sync-io / tls / uncaught / warnings)
--inspect  --inspect-brk  --inspect-wait  --inspect-port  --allow-inspector
--diagnostic-dir  --max-heap-size  --stack-trace-limit
```

実行して確かめた — `node --cpu-prof --cpu-prof-dir=<dir> --test test/layout.test.ts`:

```
CPU.20260905.212318.23988.0.001.cpuprofile   54,834 B
nodes: 309   samples: 43   duration: 73,693 us
```

`.cpuprofile` は Chrome DevTools の Performance パネルにドロップすれば読める。JSON なので自前で集計もできる。

### MoonBit

`moon` のサブコマンドのうち、知見の採取に使えるもの（`moon help` の実物）:

| コマンド | すること |
|---|---|
| `moon explain --diagnostic` | 診断コードと名前の一覧 |
| `moon explain --diagnostic <名前>` | 説明 + **Erroneous example**（悪い書き方の実例） |
| `moon explain --attribute` | 属性の一覧 |
| `moon bench` | ベンチ実行（`--target js` 可）。平均・標準偏差・min/max・回数 |
| `moon check --output-json` | 診断を JSON で |
| `moon info` | 公開インタフェース（`.mbti`）を吐く |
| `moon coverage` | カバレッジ |
| `moon doc <型>` | 型のメソッド一覧 |

`moon explain --diagnostic` の実測: **警告 86 件 + 非警告の診断 75 件（計 161）**。
警告は `unused_value` / `partial_match` / `unreachable_code` / `useless_loop` / `unused_try` / `ambiguous_loop_argument` / `implicit_use_builtin` など。
`moon explain --attribute` は 19 個（`#inline` `#deprecated` `#borrow, #owned` `#external` `#coverage.skip` ほか）。

1 件ずつの出力の形（`moon explain --diagnostic unused_constructor` の冒頭）:

````
# E0006
Warning name: `unused_constructor`
Variant is never read, never constructed, or both.
...
## Erroneous example
```moonbit
...
````

→ **161 件をループで回せば、公式のアンチパターン集がオフラインで全部落ちる。**

`moon bench` は `b : @bench.Test` を引数に取るベンチ関数を拾う。

公式ブログに JS バックエンドと最適化の記事がある:
[JS backend](https://www.moonbitlang.com/blog/js-support) / [Optimizing MoonBit](https://www.moonbitlang.com/pearls/optimize-moonbit-core) / [Profiling MoonBit-Generated Wasm using Chrome](https://www.moonbitlang.com/blog/profile-wasm-from-js)。
`moon build --target js` の出力は `target/js/release/build/*.js`（吐かれたコードを直接読める）。


## 6. SVG・描画まわりの一次資料の所在

すべて 200 を確認。

| 資料 | URL | 性格 |
|---|---|---|
| SVG 2 勧告 | `https://www.w3.org/TR/SVG2/` | 規範。**性能の記述は無い** |
| SVG 2 編集稿 | `https://svgwg.org/svg2-draft/` | 同上、更新が早い |
| Blink の paint README | `chromium.googlesource.com/chromium/src/+/main/third_party/blink/renderer/core/paint/README.md?format=TEXT` | 実装のソース内文書（43,232 B） |
| RenderingNG | `developer.chrome.com/docs/chromium/renderingng` | Chromium 描画アーキテクチャ。`.md.txt` で raw |
| RenderingNG architecture | `developer.chrome.com/docs/chromium/renderingng-architecture` | 同上 |
| Rendering performance | `web.dev/articles/rendering-performance` | `.md.txt` で 11,388 B |
| What forces layout / reflow | `gist.githubusercontent.com/paulirish/5d52fb081b3570c81e3a/raw` | 同期レイアウトを強制する DOM API の列挙。136 行 |
| CSS Triggers | `csstriggers.com` | 200。**データの出典と更新時期はページから判別できなかった** |

`developer.chrome.com/docs/llms.txt` の中に RenderingNG 系が並んでいる（`blinkng` / `layoutng` / `renderingng` / `renderingng-architecture` / `renderingng-data-structures` / `renderingng-fragmentation` / `cvd`）。

一方、**「SVG の性能」で検索して上位に出るのはブログと SEO 記事が主**で、一次情報は出てこなかった
（Cloud Four、O'Reilly の付録章、CodePen の記事、個人ブログ、その他 2025〜2026 の「ガイド」記事）。
SVG に限った公式の性能文書は見つからなかった。描画一般（web.dev / RenderingNG / Blink）から降りてくる形になる。


## 7. この環境で効いてくる制約

- `WebSearch` は US のみ。結果は URL とタイトルのリスト
- `WebFetch` は URL ごとに **15 分キャッシュ**。ホスト跨ぎのリダイレクトは追わず、返されたリダイレクト先で叩き直す必要がある
- `WebFetch` は取得したページを小さいモデルに読ませて答えさせる方式。**原文をそのまま持ってくるなら `curl` で直接落とす方が確実**（上の表は全部 curl）
- `web-perf` skill は Chrome DevTools MCP を前提にしているが、このセッションに **その MCP は接続されていない**（接続済みは blender / claude-in-chrome / terminal / visualize / ccd_*）
- Browser pane には `javascript_tool` / `read_console_messages` / `read_network_requests` があるので、ページ内で `performance.measure` や `PerformanceObserver` を回して値を取ることはできる


## 8. 一次情報が「無い」ことが分かったもの

- **SVG 専用の公式性能文書** — W3C にも MDN にも Chrome にも無い
- **`developer.mozilla.org` の `llms.txt`** — 404。MDN を機械的に読むなら `index.json` か GitHub の `mdn/content`
- **`typescriptlang.org` の `llms.txt`** — 404。TS の性能知見は GitHub wiki（`microsoft/TypeScript-wiki`）に置かれている
- **`docs.moonbitlang.com` の `llms.txt`** — 404。`moonbitlang.com`（ブログ・ドキュメント本体）側にはある
- **`v8.dev` / `biomejs.dev` / `typescript-eslint.io` の `llms.txt`** — 404
