# どこまで届くか

`docs/web.md` は「**Chromium 系でしか動かない**と言い切る」と決めた。この文書は、
その線が**いま実際にどこを走っているか**と、**線の外で何をするか**を残す。

2026-08-28 に調べ直したところ、当時の理解に誤りがあった。その訂正も含む。

## 「File System Access API が無い」は 3 つを混ぜた言い方だった

| 層 | 何 | 仕様の置き場 | Firefox / Safari |
|---|---|---|---|
| ハンドルの機構 | `FileSystemFileHandle` / `FileSystemDirectoryHandle` / `getFile` / `createWritable` / `getFileHandle` | WHATWG File System | **ある** |
| OPFS | オリジン専用の実ファイルシステム。`navigator.storage.getDirectory()` が根を返す | WHATWG File System | **ある** |
| ピッカー | `showOpenFilePicker` / `showSaveFilePicker` / `showDirectoryPicker` / `DataTransferItem.getAsFileSystemHandle` | WICG File System Access | **無い** |

**欠けているのは入口だけで、扉の向こうの道具立ては同じ。** `io.ts` の `readDoc` /
`write` も、`assets.ts` のパス解決（`getDirectoryHandle` → `getFileHandle` の連鎖）も、
**ハンドルの出所を問わない**。実際 `.md` のドロップは既に、ピッカーではなく
`getAsFileSystemHandle()` から来たハンドルを同じ `io.openHandle` へ流している。
入口が 2 つあることは、下流にとって最初から見えていない。

## 分断線は「Chromium かどうか」。デスクトップ / モバイルではない

**訂正**: 以前は「スマホのブラウザにはピッカーが無い」と書いていた。**誤り。**
Chrome for Android は **M132 でピッカーを持った**（Intent to Ship: File System
Access on Android and WebView。「4 つのプラットフォームでは M86 から対応済みで、
残る 2 つ（Android と WebView）にも対応する」）。

caniuse は 2026-08 時点でまだ「Chrome for Android: Not supported」と書いているが、
同じ表がデスクトップ Chrome の対応開始を 105 としており（実際は 86）、この項目の
データが古い。

| | ピッカー | 主な入力 |
|---|---|---|
| デスクトップ Chromium | ある | マウス |
| デスクトップ Firefox / Safari | **無い** | マウス |
| タッチ対応 Chromium（Chromebook / Surface） | ある | 指 |
| Android Chrome | **ある** | 指 |
| iOS の全ブラウザ（WebKit 強制）/ Firefox Android | **無い** | 指 |

**「能力（ピッカーの有無）」と「入力（指かマウスか）」は独立した 2 軸**で、
4 行目がその証拠。**「スマホ」はファイルの話については分類として成立しない。**

## この線は動かない

| | OPFS | ピッカー |
|---|---|---|
| 仕様 | WHATWG File System Standard（living standard） | WICG File System Access（インキュベーション） |
| 実装 | Chrome / Firefox 111+ / Safari 15.2+ | Chromium だけ |
| Mozilla の立場 | positive、実装済み | **negative**（issue クローズ済み） |
| WebKit の立場 | 実装済み | **oppose**（`concerns: security`、issue クローズ済み） |
| Baseline | `createWritable` が Baseline 2025 到達 | Limited availability（未達） |

他の 2 エンジンは「まだ手が回っていない」のではなく、**正式に反対を表明して issue を
閉じている**。反対の理由はセキュリティの原理（ページが任意のユーザーファイルへの
書き込み可能な参照を持ち続ける）で、実装を磨いて解ける類ではない。

**分断線は偶然ではなく狙って引かれている** — Mozilla は同じ API 群のうち OPFS には
positive を出しつつ、ローカルファイル部分を harmful と評価している。

**だから `docs/web.md` の言い切りは、書かれた当時より正しい。** 揃うのを待たない
判断ではなく、**揃わないことが確定した線の上に立つ**判断になった。ピッカーは
「ウェブの機能」ではなく「Chromium プラットフォームの機能」として定着している。

## 線の外で、いま何が起きているか

`Files` の該当行は無効になって理由を言い、ショートカットも同じ理由を出す。
落ちはしない。だが**アプリの残りは、まだファイル編集器の顔をしている**。

- 帯に**ファイル名が出る** — `docName()` が本文から `xxx.md` を導く。存在しないし、
  これから存在しようもないファイルの名前
- **未保存の `●` が点きっぱなし** — `savedText` は保存成功でしか更新されない
- **閉じるたびに未保存の警告** — 解消する手段が無いのに毎回
- ファイル名のクリックが**無言の空振り**（復元するハンドルが無い）
- `.md` のドロップも**無言**（`getAsFileSystemHandle` が無いので項目を読み飛ばす）

**断り書きは出しているが、シェルは反対のことを言い続けている。**

## 線の外で何をするか — 3 つの段

| | 何ができる | 要るもの | リロードで |
|---|---|---|---|
| **(b′) 正直な機能オフ** | 書く・書き出す | 帯 / `●` / beforeunload / 空振り 2 か所を本当のことにする | 消える（と言ってある） |
| **(c) 持ち込み・持ち出し** | ＋ 読み込み | `<input type=file>` の 1 経路。**保存層ゼロ** | 消える |
| **(a) OPFS 版** | ＋ 保存 | 保存層の差し替え | **退去され得る** |

**読むだけなら全ブラウザでできる**（`<input type=file>` / `getAsFile()`）。mmm が
それをやっていないのは、読めても書き戻せない文書ができるからで、これは web.md の
懸念そのもの。ただし「**持ち込んで、編集して、持ち出す**」と最初から名乗るなら、
書き戻せないことは欠陥ではなく仕様になる。**所有すると言わないから嘘にならない。**

**(c) は (a) への遠回りではない。** OPFS 版もピッカーを使えないので、同じ
`<input type=file>` の入口が要る。

### OPFS は web.md の懸念のどちらを解消し、どちらを悪化させるか

- **「画像が死ぬ」→ 解消。** `.md` と画像が同じ木に並ぶので相対パスが生き、
  `assets.ts` の構造がそのまま乗る
- **「実体はただの `.md` が壊れる」→ 悪化。** ダウンロード方式なら、ユーザーは
  「ダウンロードした」と自覚できる。OPFS だとアプリは「保存しました」と言い、
  帯に名前が出て、ファイルは**本物**で、しかし見つけられず、ブラウザに消され得る。
  **成功に見えすぎる**

だから OPFS 版を作るなら、**`.md` を手元に落とす書き出しが「あれば良い機能」では
なく生命線**になる。いまの書き出し（SVG / PNG）とは役割が違う。

## 決めたこと

1. **Chromium 専用は維持する。ランタイムのフォールバックは持たない。**
   web.md の決定は覆さない — 理由は当時より強くなった
2. **(b′) を次にやる。別ブランチで。** Task 10 と同じ原則（無いものを黙って
   落とさない）を、言い忘れていた場所に当てるだけ。新機能ではなく、やりかけの完成
3. **(c) と (a) は、欲しい人が現れるまで作らない。** どちらも新しい約束で、
   1 製品ぶんの維持費が増える
4. **もし作るなら、OPFS 版は「非対応ブラウザへの救済」ではなく別の製品**として作る。
   ディスク版 = 手元のファイルを編集する道具（**Chromium 専用であることが仕様**）、
   OPFS 版 = どこでも同じに動く書き留める場所（消え得るので書き出しが生命線）。
   上下関係ではない。**分岐はランタイムではなくビルド時に置く** — そうすれば
   それぞれの中の道は 1 本のままで、「動く道が 1 本だけあるほうが良い」が守られる

## まだ答えが無いこと

**誰が困っているか。** デスクトップの Firefox / Safari 使い（いずれ手元のファイルに
したい）なのか、iOS で書き留めたい人（ブラウザの中で完結してよい）なのか。
前者なら import / export が主役、後者なら永続性が主役で、**同じ OPFS 版でも作るものが
違う**。ここが埋まるまで (c)(a) は着手しない。

## 実機で確かめること

Intent to Ship のスレッドが Android 版の既知の粗さを記録している。

- **save-as にファイル名のダイアログが出ない** — mmm は
  `showSaveFilePicker({ suggestedName })` に本文から導いた名前を渡すので直撃する
- MIME フィルタが効かない / 大きなフォルダで遅い

## 出典（2026-08-28 に確認）

- [WebKit standards-positions #28 — File System Access API (Local Filesystem)](https://github.com/WebKit/standards-positions/issues/28)
- [Mozilla standards-positions #154 — File System Access API](https://github.com/mozilla/standards-positions/issues/154)
- [File System API — MDN](https://developer.mozilla.org/en-US/docs/Web/API/File_System_API)
- [FileSystemFileHandle.createWritable() — MDN](https://developer.mozilla.org/en-US/docs/Web/API/FileSystemFileHandle/createWritable)
- [Window.showOpenFilePicker() — MDN](https://developer.mozilla.org/en-US/docs/Web/API/Window/showOpenFilePicker)
- [Intent to Ship: File System Access on Android and WebView](https://groups.google.com/a/chromium.org/g/blink-dev/c/x3IcFv2jY6c)
