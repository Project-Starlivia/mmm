// 束ねる場所。文書の真実は md ペインの文字列で、マップはその写し。
// 文書から導けるもの（core の木・地図の選択の位置・持ち主・選択）は EditorState の
// field（state.ts）に居て、1 トランザクションが 1 サイクル — `onUpdate` に 1 回届く。
// ここには文書から導く値を置かない（持つのはファイルの状態だけ）。読みは決して書かない。
// ここに居るのは、そのサイクルと、保存とファイル I/O、帯のメニュー。
//
// **操作の入口は 2 つ。** `apply`（持ち主の操作。focus を選ぶ）と `write`（それ以外の
// 書き込み。選択に触らない）。選択を書くのは持ち主の操作だけ（design.md）。

// style.css は index.html の <link> で読む（FOUC を避けるため head 側）
import type { EditorState } from "@codemirror/state";
import * as core from "./coreApi.ts";
import type { Anchors, Holder } from "./caret.ts";
import * as st from "./state.ts";
import { MdEditor } from "./editor.ts";
import { Mindmap, type MapHost } from "./mindmap.ts";
import { type Choice, NOTHING, cardOf, nodesOf } from "./map/select.ts";
import { handles } from "./app/handles.ts";
import { io, type Doc } from "./app/io.ts";
import { initAssets } from "./app/assets.ts";
import { imageFolder, normalizePath, retarget, setImageFolder } from "./app/head.ts";
import { initExport } from "./app/export.ts";
import { initPanes } from "./app/panes.ts";
import { deriveName } from "./app/name.ts";
import { initTheme } from "./app/theme.ts";
import { LS_GRAB, load, store, sweep } from "./app/persist.ts";
import { ask } from "./app/ask.ts";
import { ASKS } from "./app/asks.ts";
import { NOTHING_TO_RENAME, NO_FILE_ACCESS, NO_RENAME_HERE, filesMenu } from "./app/files.ts";
import { moreMenu } from "./app/more.ts";
import { blocked, failed } from "./app/notice.ts";
import { fromHash, hasImages, LINK_WARN_LENGTH, toHash } from "./app/share.ts";
import { initShortcuts } from "./app/shortcuts.ts";
import { copyText } from "./app/copy.ts";
import { initDrop } from "./app/dnd.ts";
import { showDrawing } from "./app/draw.ts";
import { onLanguageReady } from "./map/highlight.ts";
import { openOnClick } from "./map/menu.ts";

/**
 * index.html の要素を、**その型であることを実際に確かめて**引く。
 * `as` で名乗るだけだと、タグを替えたときに誰も気づけない。
 * DOM を id で引くのはこのファイルだけ。他のモジュールは受け取る。
 */
function el<T extends Element>(id: string, kind: abstract new () => T): T {
  const found = document.getElementById(id);
  if (found instanceof kind) return found;
  throw new Error(`#${id} が ${kind.name} ではない`);
}

/** 新しいタブで開く。`⋯` の外部リンクが通る唯一の道 */
function openExternal(url: string): void {
  window.open(url, "_blank", "noopener");
}

const mdPane = el("md-pane", HTMLElement);
const mapPane = el("map-pane", HTMLElement);
const elFiles = el("files", HTMLButtonElement);
const elMore = el("more", HTMLButtonElement);
const elFilename = el("filename", HTMLElement);
const elDirty = el("dirty", HTMLElement);
const elLogo = el("logo", SVGSVGElement);

// ---------- app state ----------

/** 読み口。値は全部 EditorState の field に居る */
const state = (): EditorState => editor.state;
const text = (): string => editor.text();
const doc = (): core.View => state().field(st.tree).view;
const spots = (): Map<number, core.Spot> => state().field(st.tree).spots;
const choice = (): Choice => state().field(st.choice);
const selection = (): core.Selection => nodesOf(choice());
const picked = (): number | null => cardOf(choice());
const holder = (): Holder => state().field(st.holder);
/** 選択（id）をいまの木の地番で位置に。CodeMirror へ渡すのはこの形 */
const anchorsFor = (c: Choice): Anchors => st.anchorsFor(state().field(st.tree), c);

/**
 * loadText を呼ぶたびに進む世代番号。
 *
 * **文書を跨いだ非同期は、必ずこれを見てから物を言う。** 待っているあいだに
 * New/Open で別の文書へ移っていることがあり、そのまま続けると
 * **もう開いていない文書の話**をすることになる。
 */
let docGen = 0;
let savedText = "";
/**
 * 保存済みのファイル名。まだ保存していない文書では null で、名前は本文の
 * 見出しから導出する（app/name.ts）。「無題」という状態は持たない。
 */
let savedName: string | null = null;

/** 頭が言っている画像フォルダ（正規化済み）。無ければ null */
const declaredFolder = (): string | null => {
  const raw = imageFolder(doc().frontmatter);
  return raw === null ? null : normalizePath(raw);
};

// ---------- サイクル ----------

/**
 * 1 トランザクション = 1 サイクル。木が変わっていれば描き直し、そうでなければ塗り直し。
 * **ここが読みのサイクルの唯一の出口** — 打鍵も、開くも、操作も、選び直しも、
 * フォーカスの移動も、全部ここへ 1 回届く。prev が null なら文書を丸ごと入れ替えた
 */
function onUpdate(s: EditorState, prev: EditorState | null): void {
  const t = s.field(st.tree);
  if (prev === null || prev.field(st.tree) !== t) {
    map.render();
    // 白紙の言い出し。**出る理由は 1 つ**（まだ木が無い）で、マップ側も render() の中で同じことを見ている
    editor.showHint(t.view.roots.length === 0);
    updateDirty();
    showName();
    exportApi.refresh();
    // 何も無いところに最初の木が生まれた瞬間だけ、真ん中へ寄せる
    const wasEmpty = prev === null || prev.field(st.tree).view.roots.length === 0;
    if (wasEmpty && t.view.roots.length > 0) map.fitView();
  } else {
    map.refreshSelection();
  }
}

/** 地図で選び直した。id を位置に写して CodeMirror に置く（md 側の薄塗りは field が引き直す）。
 *  reveal は md 側を anchor の頭へスクロールするか */
function choose(next: Choice, reveal: boolean): void {
  editor.select(anchorsFor(next));
  const anchor = nodesOf(next).anchor;
  if (reveal && anchor !== null) {
    const s = spots().get(anchor);
    if (s) editor.reveal(s.from);
  }
}

const setSelection = (sel: core.Selection, reveal: boolean): void => choose({ kind: "nodes", sel }, reveal);

const setPicked = (id: number | null): void => choose(id === null ? NOTHING : { kind: "card", id }, false);

/**
 * 持ち主の操作を md に映す。**選択を書く入口はここ 1 本** — 地図は md に触らない。
 * 操作 1 回 = CodeMirror への 1 回の dispatch（編集列 + focus の effect）で、undo は
 * CodeMirror のもの。focus は anchors が後の木で位置に写す（state.ts）。
 * できない操作は core が空の編集列で言う。いまは雑に、しらせを出すだけ。
 *
 * focus はノードとも中身とも限らない。ノードで `edit` ならその場編集を開く。
 * 呼び出し側が続けられるよう focus を返す（Link / Code が使う）
 */
function apply(op: core.Op, edit: boolean): number | null {
  const r = core.edit(text(), op);
  // core は断りを「編集なし・focus なし」で言う。編集が無くても focus が在るのは、
  // 何も変わらなかった操作（同じ名前への Rename など）で、しらせは出さない
  if (r.focus === null && r.edits.length === 0) {
    failed("Couldn't do that here");
    return null;
  }
  const before = selection().anchor;
  editor.apply([r.edits], r.focus);
  if (r.focus === null) return null;
  // 別のノードへ移ったときだけ md を寄せる（同じノードに留まる操作で手元を揺らさない）。
  // 寄せは編集とは別の、スクロールだけのトランザクション — undo の 1 手には入らない
  if (r.focus !== before) {
    const s = spots().get(r.focus);
    if (s) editor.reveal(s.from);
  }
  // 畳まれて埋もれたノードには箱が無く、その場編集を開けない
  if (edit && core.isNode(doc(), r.focus) && !map.beginEdit(r.focus, null)) {
    failed("Couldn't start editing — the node is folded");
  }
  return r.focus;
}

/**
 * それ以外の書き込みを md に映す（ファイルの投下・お絵描き・画像の貼り付け）。
 * **選択には触らない** — 地図にフォーカスが無くても起きる操作なので、持ち主が決めた
 * 選択を横から書き換えない（design.md「選択を書くのは持ち主の操作だけ」）
 */
function write(op: core.Op): void {
  const r = core.edit(text(), op);
  if (r.edits.length === 0) {
    if (r.focus === null) failed("Couldn't do that here");
    return;
  }
  editor.apply([r.edits]);
}

const editor = new MdEditor(mdPane, onUpdate);

const host: MapHost = {
  survey: () => state().field(st.tree),
  imageUrl: (path) => assets.imageUrl(path),
  imageHint: () => (assets.readable() ? null : "click to connect"),
  connectAssets: () =>
    void (async () => {
      if (await ensurePlace()) await assets.connect();
    })(),
  holder,
  selection,
  setSelection,
  picked,
  setPicked,
  blockText: (id) => {
    const s = spots().get(id);
    return s ? text().slice(s.from, s.to) : "";
  },
  apply,
  paste,
  copy,
  draw,
};
const map = new Mindmap(mapPane, host);

// ---------- 持ち主 ----------
//
// 選択は持っている側（フォーカスが最後に入ったペイン）が決める。md → map は、その
// 瞬間のカーソルのノードを位置にして引き継ぐ。map → md は捨てる（md のカーソルは
// 動かさない）。窓・メニュー・帯へ抜けても変わらない — 2 つのペインの focusin だけを見る
mdPane.addEventListener("focusin", () => {
  if (holder() !== "md") editor.hold("md", null);
});
mapPane.addEventListener("focusin", () => {
  if (holder() !== "map") editor.hold("map", anchorsFor(choice()));
});

/**
 * 未保存の印。**判定はここ 1 つ**で、帯の `●` とタブの favicon の両方が
 * 同じ答えを見る（別々に数えると、片方だけ古い状態のまま残る）。
 */
function updateDirty(): void {
  const dirty = text() !== savedText;
  elDirty.hidden = !dirty;
  theme.setDirty(dirty);
}

/** いまの文書の名前。保存済みならそのファイル名、まだなら本文から導く */
const docName = (): string => savedName ?? `${deriveName(doc())}.md`;

/**
 * 名乗りを出し直す。本文を打つそばからタイトルが変わる。
 * タブは名前を持つ文書のときだけ名乗る（`filename.md - mmm`）。
 */
function showName(): void {
  const name = savedName ?? (doc().roots.length ? docName() : null);
  const title = name === null ? "mmm" : `${name} - mmm`;
  // 打鍵のたびに呼ばれるので、変わっていないなら DOM に触らない
  if (document.title !== title) document.title = title;
  const shown = docName();
  if (elFilename.textContent !== shown) elFilename.textContent = shown;
  // **押せるときだけ押せる顔をする。** 理由は Files の Rename の行と同じものを使う
  const why = !io.canRename() ? NO_RENAME_HERE : savedName === null ? NOTHING_TO_RENAME : "";
  elFilename.title = why === "" ? "Rename — click" : why;
  // 押せなさは `aria-disabled` の 1 つで言う（見た目も読み上げも同じ源）
  if (why === "") {
    elFilename.removeAttribute("aria-disabled");
    elFilename.setAttribute("tabindex", "0");
  } else {
    elFilename.setAttribute("aria-disabled", "true");
    elFilename.removeAttribute("tabindex");
  }
}

/** 文書を丸ごと入れ替える。名乗りも、寄せも、ここから */
function loadText(next: string, name: string | null): void {
  docGen++;
  savedName = name;
  assets.clear(); // image paths are relative to the (new) md
  editor.setText(next); // → onUpdate
  map.fitView();
  // 文書が入れ替わった。**Recent の並びもここで引き直す**
  void refreshRecent();
}

// ---------- file I/O ----------

/** 開いた文書を UI に載せる */
function applyDoc(opened: Doc): void {
  savedText = opened.text;
  loadText(opened.text, opened.name);
  void offerConnect();
}

/**
 * 開いた文書に画像が居るのに、そのフォルダを握っていない。**繋ぎ直しを誘う。**
 *
 * 出るのは画像が居るときだけ — 繋ぐものが無い文書に聞く意味は無い。
 * 断っても道は閉じない（Files の Choose folder が入口として残る）。
 * ブラウザはクリックの直後にしかピッカーを開けないので、**箱のボタンが
 * その 1 回**になる。自動で繋ぎに行くことはできない。
 */
async function offerConnect(): Promise<void> {
  if (savedName === null || !hasImages(text())) return;
  // 許可を確かめるあいだに別の文書へ移っていたら、もうこの文書の話ではない
  const gen = docGen;
  if (await assets.connected()) return;
  if (gen !== docGen) return;
  const where = declaredFolder() ?? "./";
  const go = await ask(ASKS.connect(where));
  // 箱を読んでいるあいだに移っていることもある。**繋ぐ直前にもう一度見る**
  if (go !== null && gen === docGen) await assets.connect();
}

async function openFile(): Promise<void> {
  // ショートカットから来ると、押せない理由を言う行が無い — 同じ理由をここでも言う
  if (!io.canOpen()) {
    failed(NO_FILE_ACCESS);
    return;
  }
  try {
    if (!(await confirmDiscard())) return;
    const opened = await io.openDialog();
    if (opened) applyDoc(opened);
  } catch (err) {
    console.error("open failed:", err);
    failed("Couldn't open the file");
  }
}

/** いま開いているファイル**そのもの**の名前を変える。本文の見出しから導く名前とは別の話 */
async function renameFile(): Promise<void> {
  if (savedName === null) return;
  const typed = (await ask(ASKS.rename(savedName)))?.[0];
  if (typed === undefined) return;
  const name = typed.trim();
  if (name === "" || name === savedName) return;
  try {
    const next = await io.rename(name);
    if (next === null) return;
    savedName = next;
    showName();
  } catch {
    failed("Couldn't rename the file");
  }
}

/**
 * 保存。`asNew`（別名で保存）と、まだ名前の無い文書はダイアログを出す。
 * ダイアログの初期値はいまの名前 — 保存済みならそのファイル名、まだなら本文から導いたもの。
 */
async function saveFile(asNew = false): Promise<void> {
  try {
    if (asNew || savedName === null) {
      if (!io.canSaveAs()) {
        failed(NO_FILE_ACCESS);
        return;
      }
      const saved = await io.saveAs(docName(), text());
      if (!saved) return; // キャンセル
      savedName = saved.name; // ここで初めて名前が決まる
      showName();
      // **写しは別の文書。** 握りは「この md から見たあのフォルダ」という対
      // でしか意味を持たないので、md が別の場所へ移った時点で対ごと無効
      assets.clear();
      void refreshRecent();
      void offerConnect();
    } else {
      await io.save(text());
    }
    savedText = text();
    updateDirty();
  } catch (err) {
    // パスを見失っていたら別名保存へ（通常はここに来ない）
    if (err instanceof Error && err.message === "no-file") {
      void saveFile(true);
      return;
    }
    console.error("save failed:", err);
    failed("Couldn't save");
  }
}

/** 新しい文書。いまの文書は捨て、ファイルハンドルも手放す */
async function newFile(): Promise<void> {
  try {
    if (!(await confirmDiscard())) return;
    await io.close();
    savedText = "";
    loadText("", null);
    editor.focus();
  } catch (err) {
    console.error("new file failed:", err);
    failed("Couldn't create a new file");
  }
}

/** 本文へのリンクの綴り。作るのも測るのもこの 1 か所 */
const linkOf = async (body: string): Promise<string> =>
  `${location.origin}${location.pathname}${await toHash(body)}`;

/**
 * リンクにまつわる**押す前の但し書き**。無ければ空。
 * 長さは gzip してからでないと分からないので、開くたびに本当に測る（1ms 弱）。
 */
async function linkNote(): Promise<string[]> {
  const notes: string[] = [];
  if (hasImages(text())) notes.push("Images won't travel");
  if ((await linkOf(text())).length > LINK_WARN_LENGTH) notes.push("Long link — may be cut");
  return notes;
}

/** いまの本文へのリンクをクリップボードへ。写せたことは押した行の絵が言う */
async function copyLink(): Promise<boolean> {
  try {
    await navigator.clipboard.writeText(await linkOf(text()));
    return true;
  } catch (err) {
    console.error("copy link failed:", err);
    failed("Couldn't copy the link");
    return false;
  }
}

async function confirmDiscard(): Promise<boolean> {
  if (text() === savedText) return true;
  return (await ask(ASKS.discard)) !== null;
}

// ---------- 画像（ローカルファースト） ----------
// 実装は app/assets.ts。ここは「いまのファイル」と描き直しを繋ぐだけ

const assets = initAssets({
  failed,
  refresh: () => map.render(),
  declared: () => declaredFolder(),
  declare: (value) => {
    // 頭を書いただけでは本文は古い場所を指したまま。**宣言と本文は同じ 1 つの
    // 引っ越し**なので、続けて映して 1 手（1 回の Undo）に畳む。初めての宣言
    // （prev が無い）では本文は触らない — どこから動かすのか分からない
    const next = normalizePath(value);
    if (next === null) return; // 読めない綴り（空・絶対パス・URL）は欄が先に止めている
    const prev = declaredFolder();
    const sets: core.Edit[][] = [[setImageFolder(text(), doc().frontmatter, next)]];
    let md = core.splice(text(), sets[0]);
    if (prev !== null) {
      for (const op of retarget(doc(), prev, next)) {
        const r = core.edit(md, op);
        sets.push(r.edits);
        md = core.splice(md, r.edits);
      }
    }
    editor.apply(sets);
  },
});

/**
 * フォルダを指す一手の**手前の駅**。保存されていなければ、その場で保存まで案内する。
 * **壁ではなく駅。** 行程を先に見せてそのまま通す — 通ればそのまま指せ、断れば何も起きない。
 */
async function ensurePlace(): Promise<boolean> {
  if (savedName !== null) return true;
  if ((await ask(ASKS.place)) === null) return false;
  await saveFile(true);
  return savedName !== null;
}

/**
 * 画像をディスクへ置いて、そのノードの中身として足す（Image のブロック）。
 * **貼り付け・ドロップ・お絵描きが通る唯一の道** — WebP への変換も名前の
 * 確認も画像フォルダの結び付けも、`assets.saveToDisk` が 1 か所で持つ。
 */
async function attachImage(id: number, blob: Blob): Promise<void> {
  const gen = docGen;
  if (!(await ensurePlace())) return;
  const rel = await assets.saveToDisk(blob);
  // 置いているあいだに文書が入れ替わった（世代）／ノードが消えている（id）ことがある
  if (rel === null || gen !== docGen || !core.isNode(doc(), id)) return;
  write({
    kind: "addBlock",
    at: { kind: "in", node: id },
    content: { kind: "image", alt: "", src: rel, title: "" },
  });
}

/** お絵描きの窓が開いているか。二重に開かせない */
let drawingOpen = false;

/** Shift+D。窓を開いて描いてもらい、確定した絵を保存して足す */
function draw(id: number): void {
  if (drawingOpen) return;
  drawingOpen = true;
  void showDrawing()
    .then((blob) => (blob === null ? undefined : attachImage(id, blob)))
    .catch((error: unknown) => {
      console.error("drawing failed:", error);
      failed("Couldn't add the drawing");
    })
    .finally(() => {
      drawingOpen = false;
      mapPane.focus();
    });
}

/**
 * 選んでいるものをクリップボードへ写す（Mod+C / Mod+X）。カードを選んでいれば
 * その原文、でなければ選択の部分木（`copyText`）。書けたかを返す — Cut は
 * 書けてから消す（mindmap.ts の act）
 */
async function copy(): Promise<boolean> {
  const card = picked();
  const clip = card !== null ? host.blockText(card) : copyText(text(), doc(), spots(), selection().ids);
  if (clip === "") return false;
  try {
    await navigator.clipboard.writeText(clip);
    return true;
  } catch (err) {
    console.error("copy failed:", err);
    failed("Couldn't copy");
    return false;
  }
}

/**
 * クリップボードを貼る（Mod+V）。画像はテキストより優先し、選んでいる
 * ノード（anchor）へ足す。字は raw のまま `Graft` へ — 何を貼るか（見出し・項目は
 * 形だけ運んで綴りは貼り先に従う、段落は行ごとに子、それ以外の中身はカード）は
 * core が読んで決める。TS は `#` も URL も見ない。
 * 決めは docs/superpowers/specs/2026-09-06-paste-design.md
 */
function paste(): void {
  const anchor = selection().anchor;
  const gen = docGen;
  void (async () => {
    // クリップボードに画像があれば、テキストより優先する。
    // try で囲うのは**クリップボードを読むところだけ** — 画像を置く処理まで
    // 囲うと、フォルダ選択の失敗が「クリップボードが読めなかった」と
    // 同じ扱いになり、黙ってテキストの道へ落ちてしまう
    let img: Blob | null = null;
    try {
      if ("read" in navigator.clipboard) {
        for (const item of await navigator.clipboard.read()) {
          const t = item.types.find((x) => x.startsWith("image/"));
          if (t) {
            img = await item.getType(t);
            break;
          }
        }
      }
    } catch {
      /* clipboard.read が無い／断られた → 字の道へ */
    }
    if (gen !== docGen) return;
    if (img !== null) {
      if (anchor === null) {
        failed("Select a node to paste an image into");
        return;
      }
      await attachImage(anchor, img);
      return;
    }
    const clip = await navigator.clipboard.readText();
    if (gen !== docGen) return;
    // 空はしくじりではなく「何も無い」なので黙る
    if (clip.trim() === "") return;
    apply({ kind: "graft", at: { kind: "in", node: anchor ?? core.DOC_ID, side: null }, md: clip }, false);
  })().catch((error: unknown) => {
    console.error("paste failed:", error);
    failed("Couldn't paste");
  });
}

/**
 * 画像フォルダの状態。**言葉は宣言と許可の 2 つだけ**（app/assets.ts の冒頭が
 * 名付けたもの）。許可が無いときは宣言のパスを出す — どこを指していて届いて
 * いないのかが見えないと、直しようがない。
 */
function folderCaption(): string {
  const name = assets.folderName();
  const declared = declaredFolder();
  if (name === null) return declared === null ? "no folder" : `${declared}, no access`;
  return declared !== null ? name : `${name}, not declared`;
}

// ---------- 帯のメニュー ----------

// 並びは app/files.ts と app/more.ts の表。ここは状態を写して、押されたら走らせる
openOnClick(elFiles, () =>
  filesMenu(
    {
      savedName,
      recent: recent.map((file) => file.name),
      canOpen: io.canOpen(),
      canSave: io.canSaveAs(),
      canRename: io.canRename(),
      canChooseFolder: assets.canChooseFolder(),
      folder: folderCaption(),
    },
    {
      newFile: () => void newFile(),
      open: () => void openFile(),
      openRecent: (i) => {
        const file = recent[i];
        if (file) openKnown(file);
      },
      save: () => void saveFile(),
      saveAs: () => void saveFile(true),
      rename: () => void renameFile(),
      chooseFolder: () =>
        void (async () => {
          if (await ensurePlace()) await assets.chooseFolder();
        })(),
    },
  ),
);

// 掴みやすさ。見た目の好みと同じく localStorage に持つ（"on" 以外は既定の見た目どおり）
let grab = load(LS_GRAB) === "on";
const setGrab = (on: boolean): void => {
  grab = on;
  map.setGrab(on);
  store(LS_GRAB, on ? "on" : "off");
};
map.setGrab(grab);

openOnClick(elMore, () =>
  moreMenu(
    { light: theme.isLight(), grab, linkNote: linkNote() },
    {
      undo: () => editor.undo(),
      redo: () => editor.redo(),
      pickColor: () => theme.pickColor(),
      toggleTheme: () => theme.toggle(),
      toggleGrab: () => setGrab(!grab),
      copyLink,
      open: openExternal,
    },
  ),
);

/**
 * 覚えている文書。**Files の `Recent` に並ぶのがこれ**。メニューは同期で
 * 組まれるのに、覚えているものは IndexedDB の向こうに在る。だから開く・
 * 保存するたびに引き直して手元に置く。いま開いているものは並びから外す。
 */
let recent: FileSystemFileHandle[] = [];

async function refreshRecent(): Promise<void> {
  const now = io.currentFile();
  const rows = await handles.list();
  const out: FileSystemFileHandle[] = [];
  for (const row of rows) {
    if (now && (await row.doc.isSameEntry(now))) continue;
    out.push(row.doc);
  }
  recent = out;
}

/** 覚えている文書を開く。**許可はここで取り直す** — 押されたことがその資格 */
function openKnown(file: FileSystemFileHandle): void {
  void (async () => {
    if (!(await confirmDiscard())) return;
    const opened = await io.openKnown(file);
    if (opened) applyDoc(opened);
  })().catch((error: unknown) => {
    console.error("open failed:", error);
    failed("Couldn't open the file");
  });
}

// **名前を押したら、名前を変える。** 押せなさは `renameFile` 自身が持つ
elFilename.addEventListener("click", () => void renameFile());
// <span role="button"> なので Enter / Space を自分で出す（app/theme.ts のロゴと同じ）
elFilename.addEventListener("keydown", (e) => {
  if (e.key !== "Enter" && e.key !== " ") return;
  e.preventDefault();
  void renameFile();
});

window.addEventListener("beforeunload", (event) => {
  if (text() === savedText) return;
  event.preventDefault();
  event.returnValue = "";
});

// ---------- ドラッグ & ドロップ（振り分けは app/dnd.ts） ----------

initDrop({
  markDrop: (at) => map.markFileDrop(at),
  failed,
  async openMarkdown(file) {
    if (!(await confirmDiscard())) return;
    applyDoc(await io.openHandle(file));
  },
  async addImages(files, node) {
    for (const file of files) await attachImage(node, await file.getFile());
  },
});

// ---------- ペイン / 書き出し / テーマ / キー（実装は app/ 配下） ----------

const { togglePane, togglePaneVis } = initPanes({
  mdPane,
  mapPane,
  panesEl: el("panes", HTMLElement),
  splitter: el("splitter", HTMLElement),
  focusEditor: () => editor.focus(),
});

const exportApi = initExport({
  map,
  name: docName,
  failed,
  blocked,
  empty: () => doc().roots.length === 0,
  button: el("export", HTMLButtonElement),
  wayButton: el("export-way", HTMLButtonElement),
});

const theme = initTheme({ logo: elLogo, setEditorTheme: (dark) => editor.setTheme(dark) });

initShortcuts({
  save: (asNew) => void saveFile(asNew),
  open: () => void openFile(),
  create: () => void newFile(),
  togglePane,
  togglePaneVis,
  undo: () => editor.undo(),
  redo: () => editor.redo(),
  export: (choose) => (choose ? exportApi.choose() : exportApi.run()),
});

// ---------- boot ----------

// 本文の控えは持たない。IndexedDB に置くのはハンドルだけで、
// **起動時に勝手に開き直すことはしない** — 立ち上げたら常に空から始まる。
{
  sweep(); // 役目を終えた localStorage のキーを捨てる
  loadText("", null); // 空 = まだ何も無い。dirty も立たない
  void refreshRecent();
  const bootGen = docGen;
  void fromHash(location.hash).then((shared) => {
    if (shared === null) return;
    // リンクで開いた。ハッシュはその場で消す — 文書の身元はあくまで
    // ファイルハンドル 1 つで、リンクは入口でしかない
    history.replaceState(null, "", location.pathname + location.search);
    if (docGen === bootGen && text() === "") loadText(shared, null);
  });
}
// フェンスの言語は後から読み込まれる。届いたら色を載せ直す
onLanguageReady(() => map.render());

editor.focus();
