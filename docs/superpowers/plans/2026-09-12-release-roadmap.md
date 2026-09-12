# v1.0 までの工程表 — 開いている issue 45 件の回収

2026-09-12、main `73fef59`。開いている issue 45 件・PR 2 本を全部回収して v1.0.0 を出すまでの段。

## リリースの定義

- `package.json` を `1.0.0` にし、`v1.0.0` のタグと GitHub Release を切る
- 配り先は今の `mmm.chiwawaz.workers.dev`（独自ドメインは持たない。`og:url` と `canonical` はここ）
- 出す条件: CI 緑・`pnpm run deploy:dry` 通過・`docs/browsers.md` の表の環境で実機を 1 周・`curl -sI` で守りのヘッダを確認

## 段

段の中は上から順。段どうしは触るファイルが重ならないので **A / B / C は並走できる**。D は C の後（`app/parts` を両方が触る）、E は A〜D の後（数字を測り直すので）。

大きさ: S = 1 PR 小、M = 1 PR 大か 2 PR、L = spec を書いてから 2〜3 PR。

### 段 0 片付け（0.5 日）

| # | 何をする | 大きさ |
|---|---|---|
| PR #297 | docs/picture-parity を main へ（#292 の定義。段 E の土台） | S |
| PR #154 / #148 | feat/menu-flip の積み（#121 → #154 → #124 → #105 → #57/#58）は**ユーザーが回収する**。触らない | — |
| #302 | merge 済みの枝 31 本を remote から消す。`deleteBranchOnMerge` を true に。`.worktrees/` の抜け殻 123 個を消す。改名前の枝 3 本（`style/popup` / `refactor/asks` / `feat/menu-flip`）はユーザーの手元 | S |
| #324 | `ai-docs/` を今の地図へ（`_build/`、消えた試験、作業ログの 1 行、消えた一時ディレクトリ） | S |
| #313 | `docs/design.md` の「ts」2 つを MoonBit の段へ。「id の順 = 文書順」の試験を `core/read` に足す | S |

### 段 A 保存が嘘をつかない（2 日）— `app/app.mbt` `app/disk/*` `app/web/fs.mbt`

| # | 何をする | 大きさ |
|---|---|---|
| #298 | 書く字を 1 つの変数に取り、`saved_text` はそれで立てる。書き込み中に打った字は汚れのまま残す | S |
| #299 | `write_soon` に取り消しの口を持たせ、`load_text` / 新規で捨てる。`save_file` も `gen` を見る | S |
| #300 | Recent の read-modify-write を 1 つの取引に。`find` の await も取引の中へ | M |
| #309 | Recent の行に `seen` の時刻と画像フォルダの名前を添える。同名は束ねない。**行の形は Drafts も使う** | S |
| #306 | 控え（Drafts）。spec は [2026-09-12-drafts-design.md](../specs/2026-09-12-drafts-design.md)。5 段に割る | L |
| #318 | 書く前に `lastModified` を見て、開いたときと違えば書かずに知らせる。**Autosave を捨てたので自動では起きない** — 残るのは手で押したときだけ | S |
| #310 | 狭い画面でも未保存の印は残す（名前だけ落とす）。置き場はロゴの隣 | S |

### 段 B 読みと書きが落とさない（2 日）— `core/tree/*` `core/op/*` `core/map/drop.mbt`

| # | 何をする | 大きさ |
|---|---|---|
| #312 | 頭が水平線の md で列 0 の項目より後ろの中身を落とさない（書き戻しの段）。冪等でない 7 通も同じ枝で | M |
| #315 | `barren` が `body` を見る。中身を抱えた Implicit は消さず、中身を親へ寄せる | S |
| #314 | 法則の見本に「頭が水平線」5 本と setext 1 本を足し、op 3 つ・合流 4 つの破れを直す（#312 / #315 の後に残るぶん） | M |
| #311 | `Flaw` を**木の整合**（DupeId / BarrenImplicit / SideCount）と**md に書けない形**（BorderBreak / ListSide / Swallowed / GappedItem / Unmarked）の 2 類に分け、`check` の約束は前者だけにする。lab の `健全` / `flawed` も前者で出す | M |
| #316 | setext の下線の長さを綴りとして保つ（`marker` / `offset` / `loose` と同じ側）。改名の編集列を名前の行だけに | M |
| #319 | `resolve` が項目の根の Left を返さない（`check` の ListSide を `core/map` が知る）。断られた op はしらせに出す | S |
| #291 | `Doc.body` は v1 では地図に出さない、と `docs/pictures.md` に理由ごと書いて閉じる。根の上に文書の箱を置く案は v1.1 の issue に | S |
| #46 | 上流（mizchi/markdown）への報告は人が書く。mmm 側は `ai-docs/markdown.md` の控えで足りるので閉じる | — |

### 段 C 公開の器（1.5 日）— `public/` `index.html` `app/link.mbt` `core/read/head.mbt` `app/web/clip.mbt` `app/disk/images.mbt`

| # | 何をする | 大きさ |
|---|---|---|
| #305 | `public/_headers` に CSP（`default-src 'self'`、`img-src 'self' blob: data:`、`frame-ancestors 'none'`）・`X-Content-Type-Options`・`Referrer-Policy`・`Permissions-Policy`。判断を `docs/spec.md` の「配る」に残す | S |
| #304 | 共有リンクは**展開後のバイト数**で止める（上限 2 MB）。超えたら開かず「too large to open」のしらせ | S |
| #322 | `normalize_path` がドライブ文字と `scheme:` を断る。値の改行も断る | S |
| #321 | 画像を置く道の `catch` を 3 つに割り、握りが腐ったときだけ `forget`。`name_problem` に制御文字・予約名・末尾の点と空白を足す | M |
| #308 | クリップボードの「断られた」を `None` で返し、Shift+L も Mod+V も `blocked`（「Allow clipboard access」）で言う | S |
| #303 | しらせの表 → 呼ぶ側の向きも `notice.test.ts` が見る。呼び手の無い 2 語は消す | S |
| #325 | `↗` を `external-link` の絵に。呼び手の無い絵は `circle-plus` だけになり、#48 で使う | S |
| #301 | `index.html` を `lang="en"` に（lab は `ja` のまま）。md ペインと地図の `lang` は立てない | S |
| #323 | テーマと色は**人が押したときだけ** `prefs` に書く。書いていないあいだは OS の変化を `addChangeListener` で追う | S |
| #70 | `scripts/icon.ts` を戻し、`logo` から PNG 192 / 512 / maskable を吐く。`manifest.webmanifest` と `theme-color`。未保存の印はアプリでは出さない（`setAppBadge` は使わない） | M |
| #71 | 同じ仕組みで `og:image` 1200×630（ロゴ + 名前）。`description` は README の 1 行、`og:url` は workers.dev | S |
| #62 | `vite.config.ts` の `manualChunks` で core（`_build/…/js.js`）を別チャンクに。警告が消えることを確かめる | S |

### 段 D 見た目と操作の詰め（3 日）— `src/style.css` `app/parts/*` `app/mindmap/*` `core/map/*` `docs/look.md` `lab/parts`

ここは見た目の決めが要るのでユーザーが主。#148 の積みが main に入ってから始める。

| # | 何をする | 大きさ |
|---|---|---|
| #320 | 帯のボタン 3 つに `aria-haspopup` / `aria-expanded`。見出しに `role="presentation"`。子メニューを `aria-controls` で結ぶ | S |
| #155 | Files の見出しに `file` / `folder` の絵を常に渡す | S |
| #124 | メニューの行に恒常の説明（`title`）を持たせ、Easy grab に付ける | S |
| #130 | 選択の見た目を 1 つに。持ち主は**面**で言い（地図が持つ間だけ面を塗る）、枠は 1 つ | M |
| #132 | 焦点の輪を 3:1 に。`:focus-within` をやめ `:focus-visible` でペインの縁に出す。「輪」の語を焦点だけに | S |
| #133 | 欄の角丸と枠に `cam.k` を掛け、箱と同じ形で追従させる | S |
| #307 | `docs/look.md` にノードの行（30/24、12/9）・`card_bleed`・`fan_band`・畳んだラベル 11px を載せ、尺の外の 9 / 0.6 / 5 を「揃っていないところ」へ | S |
| #317 | `lab/parts` に名乗り（8 通り）・ロゴ・分割線・立ち上がりの一覧を並べる。器は見本の側で作る | M |
| #115 | 落とし先の 6 つの数字にスライダーを差して実機で決め直し、理由を `drop.mbt` に書く | M |
| #48 | 選んだノードの周りに `+`（`circle-plus`）。Intent の表から引く。指の環境で 1 手にする | M |
| #58 | 画像カードの Rename で md とディスクを 1 つの操作に（#148 の積みの最後の段。ユーザー側） | M |

### 段 E 性能と書き出し（1.5 日）— `app/mindmap/render.mbt` `app/mindmap/svg.mbt` `app/web/canvas.mbt`

| # | 何をする | 大きさ |
|---|---|---|
| #64 | 描く側を測る。矩形選択の全ノード交差（#55）と画像 1 枚ごとの全描き直し（#77）を直し、5,001 ノードで longtask が出ないところまで | M |
| #292 | 写しに `class` と `<style>` を連れて行き、焼く属性の表を捨てる。`textLength` をやめ箱を字に合わせる。ラスタは woff2 を `@font-face` に埋める（PR #297 の定義どおり） | M |
| #172 | PNG はタイルに切ってバイトで組み、上限を外す。WebP は今のまま | M |

### 段 F 出す（0.5 日）

1. `docs/spec.md` / `README.md` の綴りを最終の地図に合わせる（#89 の測り方で 0 件を確かめる）
2. `package.json` を `1.0.0`、CHANGELOG は GitHub Release の本文で足りる（squash の題がそのまま並ぶ）
3. `pnpm run deploy:dry` → main へ → 自動配布 → `curl -sI` でヘッダ・OGP・manifest を確認
4. `docs/browsers.md` の環境で実機を 1 周（Windows Chrome / Edge、Android Chrome、iOS Safari は線の外の挙動）
5. `git tag v1.0.0` → `gh release create v1.0.0`

## 決めてほしいこと（推し付き）

**①は決まった**（2026-09-12）。残りは段が来たときに 1 つずつ聞く — 推しのまま進み、
分かれ道に着いたら止まる。

| 何 | 推し | 別の道 |
|---|---|---|
| ①リリースの形 ✅ | **`v1.0.0` タグ + GitHub Release。配り先は workers.dev のまま** | 独自ドメイン（#71 の `og:url` が変わる） |
| ②#70 アプリとして入れるか | 入れる。#71 の og:image と同じラスタ化で済む | 閉じる（タブで完結） |
| ③#306 控えの形 ✅ | **Autosave（ディスクへの自動書き込み）は捨てる。控え（Drafts）は保存した後も版として残す**（2026-09-12） | Autosave を残す／控えは届いていない字だけ |
| ④#311 `Flaw` の 2 類 | 分ける。`check` の約束は木の整合だけ | 約束の文だけ直す |
| ⑤#316 setext の下線 | 長さを綴りとして保つ | 3 本に決め打ちのまま（issue は閉じる） |
| ⑥#291 `Doc.body` | v1 は出さないと書いて閉じる。文書の箱は v1.1 | 根の上に文書の箱（L、記法 spec を触る） |
| ⑦#304 上限 | 展開後 2 MB。超えたら開かない | ノード数で測る／途中まで見せる |
| ⑧#130 持ち主の見せ方 | 面で言う。枠は 1 つ | 枠で言う |
| ⑨#48 `+` を v1 に入れるか | 入れる（spec が言っている機能） | v1.1 |
| ⑩#64 / #172 を v1 に入れるか | 入れる（測って直す段を 1 つ置く） | v1.1 |
| ⑪#46 上流への報告 | 人が書く。mmm 側は閉じる | mmm 側で span を測り直す |
| ⑫#302 `deleteBranchOnMerge` | true にする | 手で消し続ける |

## 数

| 段 | issue | 目安 |
|---|---:|---|
| 0 片付け | 4 + PR 2 | 0.5 日 |
| A 保存 | 7 | 2 日 |
| B 往復 | 8 | 2 日 |
| C 公開の器 | 12 | 1.5 日 |
| D 見た目と操作 | 11 | 3 日 |
| E 性能と書き出し | 3 | 1.5 日 |
| F 出す | — | 0.5 日 |
| 計 | 45 | 11 日（A / B / C を並走すれば 8 日） |

目安は 2026-09-11 の速さ（1 日 14 PR）を基準にした。D はユーザーの決めの速さで動く。
