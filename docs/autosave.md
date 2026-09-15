# Auto Save が守るもの — 退避と履歴

mmm の Auto Save（Files ▸ Open Autosave）は、ブラウザの中（IndexedDB）に本文の写しを取る。
ディスクの `.md` が正であることは変わらない（`spec.md`）。この文書は、**写しが何を守るのか**の
線と、その線を引いた根拠になった先例を残す。

2026-09-15 に先例を調べた。確認は各製品の公式文書と、公開されているソース・issue。
第三者の資料しか無かったものと、確かめられなかったものは【未確認】と書く。

## 線 — いまは退避だけ

**Auto Save は「落ちて失う」を防ぐ退避に絞る。** 前の版に戻る履歴は別の機能で、いまは持たない。

調べたどの製品も、この 2 つを**別の仕組み**として持っていた。

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

## 先例 — 退避

| 製品 | いつ取る | 保存・破棄したら | 復元の出し方 |
|---|---|---|---|
| VS Code（Hot Exit の backup） | 変わってから 1 秒（auto save が有効なら 2 秒） | 未保存でなくなった瞬間に消す | 次に開いたとき黙って戻す |
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

## mmm に効く事実

### いつ取るか

- 手が止まって 1 秒は、VS Code の既定と同じ（`app/app.mbt` の `quiet`）
- **打ち続けるあいだは取られない。** draw.io は最長 30 秒で必ず書く。debounce に上限を足すのが定番
- **閉じる直前の字は `visibilitychange`（hidden）と `pagehide` で書き切る。** モバイルでタブを
  閉じると `beforeunload` は鳴らない（Chrome の Page Lifecycle）。Safari はタブの × で
  hidden / pagehide を出さない既知の問題がある。hidden になってからの非同期の書き込みは
  完了が保証されないので、普段から取っておき、最後の 1 回はおまけと見る
- tldraw は「閉じるときに最後の 350ms 分が消える」を、pagehide / hidden での書き切りで直した（PR #10102）

### 何を取るか

- **ディスクと同じ字は写さない。** 写しは「ディスクより新しい差分」のためにある。draw.io は
  空の図を写さない処理を後から足した（復元の候補に意味の無い行が並ぶと紛らわしい）
- **ディスクと同じ字になったら消す**（VS Code は保存でも、元に戻して一致したときでも消す）

### 置き場は消えうる

- IndexedDB は既定で best-effort。容量が逼迫すると origin ごと消える。Safari は 7 日触られて
  いない origin のスクリプトが書く保存領域を消す（ホーム画面の web app は対象外）
- `navigator.storage.persist()` は、人の操作の中で、大事なものを置くときに頼む（Chrome と Safari は
  黙って許可か拒否を決め、Firefox は聞く）
- 書けなかったことは黙らない。Excalidraw は localStorage の上限を超えて作業を失った（#8395）

### 複数のタブ

- 1 つの鍵を後から書いたほうが勝つ作りは、他のタブの字を消す（Excalidraw #10770、未解決）。
  mmm は写しの鍵にタブごとの流れの id を含むので、この形は起きない
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

## 決めていないこと（推し）

線（退避だけ）以外はまだ決めていない。推しとして置く。

| 何 | 推し |
|---|---|
| いつ取るか | 手が止まって 1 秒のまま。打ち続けても 10 秒で必ず取る。hidden / pagehide で書き切る |
| 何を取るか | ディスクと違う字だけを、1 文書 1 件で上書き。同じ字になったら消す。5 分ごとの版はやめる |
| Don't Save のとき | 写しは残す（ディスクと違う字なので「違う字だけ」とも矛盾しない） |
| 保持 | 件数で。日数の期限は置かない |
| 書けなかったとき | 言う（`spec.md` が約束しているが未実装）。`persist()` を人の操作の中で頼む |
| 復元の出し方 | Open Autosave から人が開くまま。開いた `.md` に写しがあるときに言う形（Emacs / Vim）は、札の同一性が脆いので後回し |

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
