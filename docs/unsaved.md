# 未保存の字 — 落ちて失わないために

mmm はブラウザの中（IndexedDB）に、**ディスクに届いていない字**を残す。ディスクの `.md` が
正であることは変わらない（`spec.md`）。この文書は、残すものの線と決め、名前、その根拠に
なった先例を置く。

2026-09-15 に先例を調べ、同じ日に作者と決めた。確認は各製品の公式文書と、公開されている
ソース・issue。第三者の資料しか無かったものと、確かめられなかったものは【未確認】と書く。

**いまのコードはまだこの決めになっていない**（2026-09-12 の設計のまま。名前も Auto Save）。
今の動きは `spec.md`、この決めへの道は issue に置く。

## 線 — 退避だけ

**守るのは「落ちて失う」だけ。** 前の版に戻る履歴は別の機能で、いまは持たない。

調べたどの製品も、この 2 つを**別の仕組み**として持っていた（Blender も、Auto Save と `.blend1` の 2 本立て）。

| | 退避 | 履歴 |
|---|---|---|
| 守るもの | ディスクに届く前に、窓ごと失った字 | 保存した後で、間違いに気づいた版 |
| 中身 | ディスクより新しい全文、最新 1 つ | 版ごとの全文（差分のこともある） |
| 保存したら | **消す**（役目を終える） | 保存を起点に**増える** |

2026-09-12 の設計（`superpowers/specs/2026-09-12-drafts-design.md`、当時の名前は Drafts）は
1 つの棚で両方を担い、保存しても消さず、時間で版を切っていた。先例の中で珍しいのは
「履歴を持つこと」ではなく、**退避の写しを保存後も時間で版にして、1 つの一覧に貯める**形のほうだった。
開くたびに同じ字の写しが増える（#359）のも、20 流れの枠が変更の無い写しで埋まるのも、
兼ねていることから来ている。

当時の理由「間違いに気づくのは保存の直後」は、先例では退避ではなく**保存を起点にした履歴**が
受け持っている（Blender の `.blend1`、VS Code の Local History）。必要になったら、その形で別に足す。

## 決め

| 何 | 決め |
|---|---|
| 何を | **ディスクと違う字だけ**、全文を**1 文書 1 件**（書くたびに上書き）。版は持たない。保存していない文書は空の字（`""`）と比べる |
| いつ | 手が止まって 1 秒。**打ち続けても最長 10 秒**で必ず。**タブが隠れる（`visibilitychange` の hidden）・閉じる（`pagehide`）とき**に待ちをすぐ書く。保存を聞く前にも書く |
| 捨てる | **ディスクと同じ字になった**とき（保存・別名で保存・undo で戻る・空に戻す）／**Don't Save を選んだ**とき／20 件を超えた古いもの／Discard all unsaved |
| 残す | **選ばずに消えた**とき（タブやブラウザが落ちた・閉じた・再読み込みした）。閉じるときのブラウザの「離れますか」は、mmm にはどちらを押したか分からないので残す |
| 見せる | Files の `Open Unsaved ▸` に新しい順。**いま開いている文書自身の件は出さない**。開くと `●` を立てたまま戻し、**元の件を引き継ぐ**（同じ字の件を増やさない） |
| 保持 | 件数で 20。巨大な文書 1 つが棚を食い尽くさないよう、合計 20 MB の柵は残す。日数の期限は置かない |
| 書けなかったとき | 1 度だけ `Couldn't keep unsaved changes` と言う。最初に書くときに 1 度、`navigator.storage.persist()` を頼む（結果は問わない） |

Don't Save で捨てるのは VS Code・Word（既定）と同じ。人が「捨てる」を選んだのだから残さない。
そのぶん、たずねの補足（いまの `Unsaved changes are autosaved.`）は消す。
**保存を聞く前に書くのは残す** — たずねを開いたまま落ちても、字が残るように。

「ディスクと同じ字になったら消す」は、未保存でなくなった瞬間に消す VS Code の backup と同じ形。
保存で消すのは VS Code・Emacs・Word・draw.io に共通する。

## 名前 — Unsaved

| 語 | 見る場所 | 退けた理由 |
|---|---|---|
| **Unsaved**（とる） | Word（Recover Unsaved Documents）、Typora | — 状態の名前そのもので、比喩を足さない。保存した版の履歴とは意味の上で重ならない |
| Draft | メールの下書き、draw.io、Typora | 身近で挙動も重なるが、文章を書く道具では `.md` そのものが下書きに見える |
| Auto Save | Blender | VS Code・macOS・Word では本物のファイルに書く機能の名前。自動で取る履歴とも区別がつかない |
| Backup | VS Code（Hot Exit） | Emacs などで履歴の意味。ファイルの予備を広く指す |
| Recover / Restore | Word、Blender、ブラウザ | 将来の履歴（前の版を戻す）も同じ動詞で呼べてしまう |

作者の判断は「身近さ（Draft）より、指すものの正確さ」。

### 用語の表

| 指すもの | 日本語（docs・コメント） | コード | 画面 |
|---|---|---|---|
| 機能 | 未保存の字 | — | Unsaved |
| 1 件 | 未保存の字（1 件） | `UnsavedText` | 一覧の 1 行 `notes.md · 2 min ago` |
| 台帳 | 未保存の字の台帳 | `Unsaved`（`Recent` と同じく、台帳を中身で呼ぶ） | — |
| ファイル | — | `app/disk/unsaved.mbt` | — |
| 1 件の鍵 | id | `id`（`Recent` の `Known.id` と同じ語） | — |
| 置き場 | 未保存の字の棚 | `unsaved_shelf = "unsaved"`（DB の版を上げる。前の棚 `autosaves` の中身は移さない） | — |
| 比べる相手 | ディスクの字（保存していなければ空） | `disk_text`（いまの `saved_text`） | — |
| 最後に書いた字 | 書いた字（同じ字を二度書かないため） | `written`（いまの `kept`） | — |
| 開く | 未保存の字から開く | `open_unsaved` | `Open Unsaved ▸` |
| 1 件を捨てる | 捨てる | `discard` | —（人が押す口は Don't Save） |
| 全部捨てる | 全部捨てる | `discard_all` | `Discard all unsaved` |
| 無いとき | — | — | `Nothing unsaved` |
| 書けなかった | — | — | `Couldn't keep unsaved changes` |
| 未保存の印 | 未保存の印 | — | `●`（読み上げ名 `Unsaved changes`） |

消える語: `Autosave` / `Autosaves`、`flow`（流れ）、`seq`（版）、`born`、`span`、`keep_seqs`、`kept`、
`Forget all autosaves`、`Nothing autosaved yet`、`Unsaved changes are autosaved.`

## 決めていないこと

| 何 | いまの考え |
|---|---|
| 開いた `.md` に未保存の字があるとき言うか（Emacs / Vim の形） | 後回し。札の同一性が脆い（下記） |
| 複数のタブ（ほかのタブで開いている件を一覧から隠す、draw.io の形） | 後回し。鍵をタブごとに持つので、上書きで消える形は起きない |
| 保存した版の履歴（Blender の `.blend1` の形） | 持たない。要るときに別の機能として決める |

## 先例 — 退避

| 製品 | いつ取る | 保存・破棄したら | 復元の出し方 |
|---|---|---|---|
| VS Code（Hot Exit の backup） | 変わってから 1 秒（auto save が有効なら 2 秒） | 未保存でなくなった瞬間に消す（保存でも、戻して一致しても） | 次に開いたとき黙って戻す |
| Emacs（`#file#`） | 300 打鍵か 30 秒の無入力 | 保存で消す | 開いたとき、写しのほうが新しければ言う（`recover-file`） |
| Vim（swap） | 200 文字か 4 秒の無入力 | 保存しても消えない（編集をやめるまで） | 開くときに ATTENTION。別の Vim が編集中かの判定も兼ねる |
| Word（AutoRecover） | 既定 10 分 | 保存せず閉じれば消す。一度も保存していない文書だけ 4 日残す | 次の起動で、元と復元を並べて選ばせる |
| Blender（Auto Save） | 既定 2 分 | セッションに 1 つを上書きし続ける。置き場は OS の一時フォルダ | 起動時には言わず、File ▸ Recover ▸ Auto Save から人が選ぶ |
| draw.io（drafts） | 未保存になるたび。最長 30 秒で必ず | 保存が終われば消す。**空の図は写さない**（後から足された） | 1 件なら黙って読み込み、2 件以上なら選ばせる |
| Excalidraw | 300ms。blur / hidden / beforeunload で書き切る | 消さない（1 つを上書き） | 起動時に黙って読み込む |
| tldraw | 350ms で差分。hidden / pagehide で書き切る | 保存の概念が無い（常に同期） | 自動 |

## 先例 — 履歴

| 製品 | 版を作るとき | 保持 |
|---|---|---|
| Blender（`.blend1` / `.blend2`） | 保存のたび、直前の版を 1 つずらす | 既定 2 世代 |
| VS Code（Local History） | 保存のたび。10 秒以内の連続保存は 1 件にまとめる | 50 件、256 KB を超えるものは取らない |
| macOS（Versions） | 開く・保存・複製・改名・1 時間ごと | 【未確認】 |
| JetBrains（Local History） | 保存に関係なく常時。テスト・コミットでラベル | 5 作業日。IDE の更新で消える |
| Obsidian（File recovery） | 最低 5 分あけて | 7 日 |
| Joplin | 前の版から 10 分以上たっていれば | 90 日 |

日数で消す方式には、「10 日前に消した字が、保持 10 日のせいで戻せなかった」という報告があり、
件数で残す要望が出ている（Obsidian）。

## 決めの根拠になった事実

### いつ取るか

- 手が止まって 1 秒は、VS Code の既定と同じ（`app/app.mbt` の `quiet`）
- **打ち続けるあいだは取られない。** draw.io は最長 30 秒で必ず書く。debounce に上限を足すのが定番
- **閉じる直前の字は `visibilitychange`（hidden）と `pagehide` で書き切る。** モバイルでタブを
  閉じると `beforeunload` は鳴らない（Chrome の Page Lifecycle）。Safari はタブの × で
  hidden / pagehide を出さない既知の問題がある。hidden になってからの非同期の書き込みは
  完了が保証されないので、普段から取っておき、最後の 1 回はおまけと見る
- tldraw は「閉じるときに最後の 350ms 分が消える」を、pagehide / hidden での書き切りで直した（PR #10102）

### 何を取るか

- **ディスクと同じ字は写さない。** 写しは「ディスクより新しい字」のためにある。draw.io は
  空の図を写さない処理を後から足した（復元の候補に意味の無い行が並ぶと紛らわしい）
- 退避で差分を持つ例は見当たらない。どれも全文

### 置き場は消えうる

- IndexedDB は既定で best-effort。容量が逼迫すると origin ごと消える。Safari は 7 日触られて
  いない origin のスクリプトが書く保存領域を消す（ホーム画面の web app は対象外）
- `navigator.storage.persist()` は、人の操作の中で、大事なものを置くときに頼む（Chrome と Safari は
  黙って許可か拒否を決め、Firefox は聞く）
- 書けなかったことは黙らない。Excalidraw は localStorage の上限を超えて作業を失った（#8395）

### 複数のタブ

- 1 つの鍵を後から書いたほうが勝つ作りは、他のタブの字を消す（Excalidraw #10770、未解決）。
  mmm は 1 件の鍵を開くたびに振るので、この形は起きない
- draw.io は「いま生きているタブの写しは一覧に出さない」を localStorage の合図で持つ

### 札の同一性

- `isSameEntry` は `move()`（改名）の後の答えがブラウザで違う。Chromium は札をパスで持つので
  別物になり、Firefox は同じもの（whatwg/fs #59、仕様は未解決）。**写しとファイルを札の照合だけで
  結ぶのは脆い**（#358 の問いへの答えでもある）

### 元のファイルを黙って変えない

- Mac OS X Lion（2011）の Auto Save は本体を常に書き、Save As を Duplicate に置き換えた。
  批判の中心は「試しに触って閉じる」ができず、元が書き換わること。Mountain Lion で Save As と
  「最後に開いた版 / 保存した版に戻す」が戻った。mmm の「ディスクへ書くのは人が押したときだけ」
  （#306）はこの批判を避けた形になっている

## 出典

退避
- VS Code — [Basic editing（Auto Save / Hot Exit）](https://code.visualstudio.com/docs/editing/codebasics)、[workingCopyBackupTracker.ts](https://github.com/microsoft/vscode/blob/main/src/vs/workbench/services/workingCopy/common/workingCopyBackupTracker.ts)、[Hot Exit](https://code.visualstudio.com/blogs/2016/11/30/hot-exit-in-insiders)
- Emacs — [Auto Save Control](https://www.gnu.org/software/emacs/manual/html_node/emacs/Auto-Save-Control.html)、[files.texi](https://raw.githubusercontent.com/emacs-mirror/emacs/master/doc/emacs/files.texi)
- Vim — [options.txt](https://vimhelp.org/options.txt.html)、[recover.txt](https://vimhelp.org/recover.txt.html)
- Word — [What is AutoSave](https://support.microsoft.com/en-us/office/what-is-autosave-6d6bd723-ebfd-4e40-b5f6-ae6e8088f7a5)、[Recover lost or unsaved documents](https://learn.microsoft.com/en-us/troubleshoot/microsoft-365-apps/word/recover-lost-unsaved-corrupted-document)、[un-saved file（4 日）](https://learn.microsoft.com/en-us/archive/blogs/mssmallbiz/how-to-recover-that-un-saved-microsoft-office-excel-word-or-powerpoint-file-you-closed-before-saving)
- Blender — [Recovering Data](https://docs.blender.org/manual/en/latest/troubleshooting/recover.html)、[Save & Load preferences](https://projects.blender.org/blender/blender-manual/raw/branch/main/manual/editors/preferences/save_load.rst)
- draw.io — [DrawioFile.js](https://github.com/jgraph/drawio/blob/dev/src/main/webapp/js/diagramly/DrawioFile.js)、[App.js](https://github.com/jgraph/drawio/blob/dev/src/main/webapp/js/diagramly/App.js)
- Excalidraw — [excalidraw-app/App.tsx](https://github.com/excalidraw/excalidraw/blob/master/excalidraw-app/App.tsx)、[#8395](https://github.com/excalidraw/excalidraw/issues/8395)、[#10770](https://github.com/excalidraw/excalidraw/issues/10770)
- tldraw — [TLLocalSyncClient.ts](https://github.com/tldraw/tldraw/blob/main/packages/editor/src/lib/utils/sync/TLLocalSyncClient.ts)、[PR #10102](https://github.com/tldraw/tldraw/pull/10102)
- Typora — [Auto Save](https://support.typora.io/Auto-Save/)

履歴
- VS Code Local History — [v1.66 release notes](https://code.visualstudio.com/updates/v1_66)、[workingCopyHistoryService.ts](https://github.com/microsoft/vscode/blob/main/src/vs/workbench/services/workingCopy/common/workingCopyHistoryService.ts)
- macOS — [autosavesInPlace](https://developer.apple.com/documentation/appkit/nsdocument/autosavesinplace)、[Document-Based App Programming Guide](https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/DocBasedAppProgrammingGuideForOSX/StandardBehaviors/StandardBehaviors.html)
- JetBrains — [Local History](https://www.jetbrains.com/help/idea/local-history.html)
- Obsidian — [File recovery](https://obsidian.md/help/Plugins/File+recovery)、[件数で残す要望](https://forum.obsidian.md/t/file-recovery-by-number-of-snapshots/53749)
- Joplin — [history spec](https://github.com/laurent22/joplin/blob/dev/readme/dev/spec/history.md)

ブラウザと議論
- [Page Lifecycle API](https://developer.chrome.com/docs/web-platform/page-lifecycle-api)、[page-lifecycle #2（Safari）](https://github.com/GoogleChromeLabs/page-lifecycle/issues/2)、[beforeunload](https://developer.mozilla.org/en-US/docs/Web/API/Window/beforeunload_event)
- [Storage quotas and eviction criteria](https://developer.mozilla.org/en-US/docs/Web/API/Storage_API/Storage_quotas_and_eviction_criteria)、[Persistent storage](https://web.dev/articles/persistent-storage)、[WebKit: 7-day cap](https://webkit.org/blog/10218/full-third-party-cookie-blocking-and-more/)
- [whatwg/fs #59（move 後の isSameEntry）](https://github.com/whatwg/fs/issues/59)
- Lion の Auto Save — [TidBITS: Duplicate](https://tidbits.com/2011/10/27/the-problem-with-lions-duplicate-command/)、[TidBITS: 10.8.2](https://tidbits.com/2012/09/20/with-10-8-2-mountain-lion-saves-even-better/)
- [Ink & Switch: Local-first software](https://www.inkandswitch.com/essay/local-first/)
