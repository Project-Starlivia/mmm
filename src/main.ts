// 束ねる場所。文書の真実は md ペインの文字列で、マップはその写し。
// サイクルは 1 本 — 打鍵 → core.survey(text, edits) → layout → render。読みは
// 決して書かない。選択はここに値として在り、地図はそれを塗るだけ。
// ここに居るのは、そのサイクルと、保存とファイル I/O、帯のメニュー。
//
// **操作の入口は `apply` 1 本。** 無いのは消す・並べ替え・ドラッグ・カード
// （後の段で戻す。git に在る）。

// style.css は index.html の <link> で読む（FOUC を避けるため head 側）
import * as core from "./coreApi.ts";
import { caretIds, type Range } from "./caret.ts";
import { MdEditor } from "./editor.ts";
import { Mindmap, type MapHost } from "./mindmap.ts";
import { NONE, type Selection } from "./map/select.ts";
import { handles } from "./app/handles.ts";
import { io, type Doc } from "./app/io.ts";
import { initAssets } from "./app/assets.ts";
import { imageFolder, normalizePath } from "./app/head.ts";
import { initExport } from "./app/export.ts";
import { initPanes } from "./app/panes.ts";
import { deriveName } from "./app/name.ts";
import { initTheme } from "./app/theme.ts";
import { sweep } from "./app/persist.ts";
import { ask, askText, askYesNo } from "./app/ask.ts";
import { blocked, failed } from "./app/notice.ts";
import { fromHash, hasImages, LINK_WARN_LENGTH, toHash } from "./app/share.ts";
import { initShortcuts } from "./app/shortcuts.ts";
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

/** リポジトリの行き先。ここ 1 か所 */
const REPO = "https://github.com/Project-Starlivia/mmm";

/** 改名する相手そのものがディスクに無い（保存したらもう改名する必要が無いので、駅にならない） */
const NOTHING_TO_RENAME = "Save the .md first — nothing on disk to rename yet";

/** その環境が改名を持たない。どのブラウザが、とは言わない（名指しは移り変わる） */
const NO_RENAME_HERE = "This browser can't rename files";

/** File System Access API が無いブラウザで、Files のできない行と
 *  ショートカットの両方がこの理由を言う。英語の文言はここ 1 か所だけ */
const NO_FILE_ACCESS = "This browser cannot open or save files";

/** 新しいタブで開く。`⋯` の外部リンクが通る唯一の道 */
function openExternal(url: string): void {
  window.open(url, "_blank", "noopener");
}

const mdPane = el("md-pane", HTMLElement);
const mapPane = el("map-pane", HTMLElement);
const btnFile = el("btn-file", HTMLButtonElement);
const btnMore = el("btn-more", HTMLButtonElement);
const elFilename = el("filename", HTMLElement);
const elDirty = el("dirty", HTMLElement);
const elLogo = el("logo", SVGSVGElement);

// ---------- app state ----------

/** いまの本文と、core がそれを読んだ木。打鍵のたびに組で差し替える */
let text = "";
let doc: core.View = { frontmatter: null, trees: [] };
/** いまの地番。カーソルの輪・md 側の薄塗り・選択の持ち越しが読む */
let spots = new Map<number, core.Spot>();
/** 何を選んでいるか。地図はこれを塗るだけで、自分では持たない */
let selection: Selection = NONE;

/** 持ち越す目印と、それが anchor だったか。幽霊（当たらなかった目印）も同じ形で運ぶ */
interface Carried {
  mark: core.Mark;
  anchor: boolean;
}

/**
 * 幽霊 — 前のサイクルで当たらなかった目印。捨てずに持ち越す（`## n## a` の
 * 途中のサイクルで捨てると、Enter で戻れない）。地図で選び直したら消える
 */
let ghosts: Carried[] = [];
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
  const raw = imageFolder(doc.frontmatter);
  return raw === null ? null : normalizePath(raw);
};

// ---------- サイクル ----------

/**
 * 本文が変わった。**ここが読みのサイクルの唯一の入口** — 打鍵も、開くも、
 * 新規も、リンクで開くも、全部ここを通って同じ順で映る。
 *
 * 選択は id でなく目印（前の地番）で持ち越す。id は読みのサイクルを越えて
 * 持たないので、core に「この目印はいまどれか」を訊く（`follow`）。
 */
function sync(next: string, edits: core.Edit[]): void {
  const wasEmpty = doc.trees.length === 0;
  // 目印と、それが anchor か。Implicit は行が無いので捨てる
  const carried: Carried[] = [];
  for (const id of selection.ids) {
    const s = spots.get(id);
    if (s && s.label !== null) {
      carried.push({ mark: { from: s.from, label: s.label }, anchor: id === selection.anchor });
    }
  }
  for (const g of ghosts) carried.push(g);
  const r = core.survey(next, edits, carried.map((c) => c.mark));
  text = next;
  doc = r.view;
  spots = r.spots;
  const ids: number[] = [];
  const kept: Carried[] = [];
  let anchor: number | null = null;
  r.trails.forEach((t, i) => {
    if (!t) return;
    if (t.id === null) {
      kept.push({ mark: t.mark, anchor: carried[i].anchor });
      return;
    }
    ids.push(t.id);
    if (carried[i].anchor) anchor = t.id;
  });
  ids.sort((a, b) => a - b);
  selection = { ids, anchor: anchor ?? (ids.length ? ids[ids.length - 1] : null) };
  ghosts = kept;
  map.render();
  editor.highlight(selectedRanges());
  // 白紙の言い出し。**出る理由は 1 つ**（まだ木が無い）で、マップ側も
  // render() の中で同じことを見ている
  editor.showHint(doc.trees.length === 0);
  updateDirty();
  showName();
  exportApi.refresh();
  // 何も無いところに最初の木が生まれた瞬間だけ、真ん中へ寄せる
  if (wasEmpty && doc.trees.length > 0) map.fitView();
}

/** 選んでいるノードの md 側の範囲（子孫込み） */
const selectedRanges = (): Range[] =>
  selection.ids.flatMap((id) => {
    const s = spots.get(id);
    return s ? [{ from: s.from, to: s.to }] : [];
  });

/** 地図で選び直した。幽霊は要らなくなる */
function setSelection(sel: Selection, reveal: boolean): void {
  selection = sel;
  ghosts = [];
  map.refreshSelection();
  editor.highlight(selectedRanges());
  if (reveal && sel.anchor !== null) {
    const s = spots.get(sel.anchor);
    if (s) editor.reveal(s.from);
  }
}

/**
 * 操作を md に映す。**操作の入口はここ 1 本** — 地図は md に触らない。
 * 操作 1 回 = CodeMirror の 1 トランザクションで、undo は CodeMirror のもの。
 * 操作の直後は core の focus が選択を決める（新しいノードには目印が無い）。
 * できない操作は core が空の編集列で言う。いまは雑に、しらせを出すだけ
 */
function apply(op: core.Op, edit: boolean): void {
  const r = core.edit(text, op);
  // core は断りを「編集なし・focus なし」で言う。編集が無くても focus が在るのは、
  // 何も変わらなかった操作（同じ名前への Rename など）で、しらせは出さない
  if (r.focus === null && r.edits.length === 0) {
    failed("Couldn't do that here");
    return;
  }
  if (r.edits.length > 0) editor.apply(r.edits); // → sync
  if (r.focus === null) return;
  // 同じノードに留まる操作（ラベルを打つ）で md を寄せ直さない
  setSelection({ ids: [r.focus], anchor: r.focus }, r.focus !== selection.anchor);
  if (edit) map.beginEdit(r.focus, null);
}

/** md のカーソルが動いた。掛かるノードに輪を出す（地図は動かさない） */
function onCaret(ranges: Range[]): void {
  map.showCaret(caretIds(doc, spots, ranges));
}

const editor = new MdEditor(mdPane, sync, onCaret);

const host: MapHost = {
  doc: () => doc,
  imageUrl: (path) => assets.imageUrl(path),
  imageHint: () => (assets.readable() ? null : "click to connect"),
  connectAssets: () =>
    void (async () => {
      if (await ensurePlace()) await assets.connect();
    })(),
  selection: () => selection,
  setSelection,
  apply,
};
const map = new Mindmap(mapPane, host);

/**
 * 未保存の印。**判定はここ 1 つ**で、帯の `●` とタブの favicon の両方が
 * 同じ答えを見る（別々に数えると、片方だけ古い状態のまま残る）。
 */
function updateDirty(): void {
  const dirty = text !== savedText;
  elDirty.hidden = !dirty;
  theme.setDirty(dirty);
}

/** いまの文書の名前。保存済みならそのファイル名、まだなら本文から導く */
const docName = (): string => savedName ?? `${deriveName(doc)}.md`;

/**
 * 名乗りを出し直す。本文を打つそばからタイトルが変わる。
 * タブは名前を持つ文書のときだけ名乗る（`filename.md - mmm`）。
 */
function showName(): void {
  const name = savedName ?? (doc.trees.length ? docName() : null);
  const title = name === null ? "mmm" : `${name} - mmm`;
  // 打鍵のたびに呼ばれるので、変わっていないなら DOM に触らない
  if (document.title !== title) document.title = title;
  const shown = docName();
  if (elFilename.textContent !== shown) elFilename.textContent = shown;
  // **押せるときだけ押せる顔をする。** 理由は Files の Rename の行と同じものを使う
  const why = !io.canRename() ? NO_RENAME_HERE : savedName === null ? NOTHING_TO_RENAME : "";
  elFilename.classList.toggle("off", why !== "");
  elFilename.title = why === "" ? "Rename — click" : why;
  if (why === "") elFilename.setAttribute("tabindex", "0");
  else elFilename.removeAttribute("tabindex");
}

/** 文書を丸ごと入れ替える。名乗りも、寄せも、ここから */
function loadText(next: string, name: string | null): void {
  docGen++;
  savedName = name;
  assets.clear(); // image paths are relative to the (new) md
  editor.setText(next); // → sync
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
  if (savedName === null || !hasImages(text)) return;
  // 許可を確かめるあいだに別の文書へ移っていたら、もうこの文書の話ではない
  const gen = docGen;
  if (await assets.connected()) return;
  if (gen !== docGen) return;
  const where = declaredFolder() ?? "./";
  const go = await ask({
    title: "Connect the image folder?",
    note: `Images here point to ${where}.`,
    ok: "Connect…",
    cancel: "Not now",
  });
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
  const typed = await askText("New file name", savedName, "Rename");
  if (typed === null) return;
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
      const saved = await io.saveAs(docName(), text);
      if (!saved) return; // キャンセル
      savedName = saved.name; // ここで初めて名前が決まる
      showName();
      // **写しは別の文書。** 握りは「この md から見たあのフォルダ」という対
      // でしか意味を持たないので、md が別の場所へ移った時点で対ごと無効
      assets.clear();
      void refreshRecent();
      void offerConnect();
    } else {
      await io.save(text);
    }
    savedText = text;
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
  if (hasImages(text)) notes.push("Images won't travel");
  if ((await linkOf(text)).length > LINK_WARN_LENGTH) notes.push("Long link — may be cut");
  return notes;
}

/** いまの本文へのリンクをクリップボードへ。写せたことは押した行の絵が言う */
async function copyLink(): Promise<boolean> {
  try {
    await navigator.clipboard.writeText(await linkOf(text));
    return true;
  } catch (err) {
    console.error("copy link failed:", err);
    failed("Couldn't copy the link");
    return false;
  }
}

async function confirmDiscard(): Promise<boolean> {
  if (text === savedText) return true;
  return askYesNo("Discard unsaved changes?", "Discard");
}

// ---------- 画像（ローカルファースト） ----------
// 実装は app/assets.ts。ここは「いまのファイル」と描き直しを繋ぐだけ

const assets = initAssets({
  failed,
  refresh: () => map.render(),
  declared: () => declaredFolder(),
});

/**
 * フォルダを指す一手の**手前の駅**。保存されていなければ、その場で保存まで案内する。
 * **壁ではなく駅。** 行程を先に見せてそのまま通す — 通ればそのまま指せ、断れば何も起きない。
 */
async function ensurePlace(): Promise<boolean> {
  if (savedName !== null) return true;
  const go = await askYesNo(
    "Images need a place on disk. Save the .md, then pick a folder.",
    "Save the .md…",
  );
  if (!go) return false;
  await saveFile(true);
  return savedName !== null;
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

// 文書に何かする道は Files にまとめる。**画像フォルダもここ** —
// 「この .md の画像がどこに居るか」は文書ぜんぶの設定で、新規 / 開く / 保存と
// 同じ高さのもの。塊は 2 つ（.md と、その画像フォルダ）で、見出しが状態を
// 言い、続く行がそれに対してできること。**絵が付くのは、押せるものだけ。**
openOnClick(btnFile, () => {
  const canOpen = io.canOpen();
  const canSave = io.canSaveAs();
  return [
    { caption: savedName ?? "not saved yet" },
    { label: "New", key: "Mod+Alt+N", mark: "file-plus", run: () => void newFile() },
    {
      label: "Open",
      key: "Mod+O",
      mark: "folder-open",
      run: () => void openFile(),
      disabled: !canOpen && NO_FILE_ACCESS,
    },
    {
      // 覚えている文書。**選ぶのは人**（起動時に勝手に開き直すのはやめた）
      label: "Recent",
      mark: "clock",
      items: recent.map((file) => ({ label: file.name, run: () => openKnown(file) })),
      disabled: recent.length === 0 && "Nothing opened yet",
    },
    {
      label: "Save",
      key: "Mod+S",
      mark: "save",
      run: () => void saveFile(),
      disabled: !canSave && NO_FILE_ACCESS,
    },
    // 「as」は Save と同じ操作の別名なので、絵は主の行にだけ付ける
    {
      label: "Save as",
      key: "Mod+Shift+S",
      run: () => void saveFile(true),
      disabled: !canSave && NO_FILE_ACCESS,
    },
    {
      label: "Rename",
      mark: "pencil",
      run: () => void renameFile(),
      disabled: !io.canRename() ? NO_RENAME_HERE : savedName === null && NOTHING_TO_RENAME,
    },
    { caption: folderCaption() },
    {
      // **保存していないことでは沈めない。** 押した先で保存まで案内する（駅）。
      // 沈むのは、この環境がフォルダを選べないときだけ
      label: "Choose folder",
      mark: "folder",
      run: () =>
        void (async () => {
          if (await ensurePlace()) await assets.chooseFolder();
        })(),
      disabled: !assets.canChooseFolder() && NO_FILE_ACCESS,
    },
  ];
});

// 低頻度だが消したくないものの受け皿。3 つの塊 — 戻す / 見た目 / 外に開く
openOnClick(btnMore, () => [
  { label: "Undo", key: "Mod+Z", mark: "undo-2", run: () => editor.undo() },
  { label: "Redo", key: "Mod+Shift+Z", mark: "redo-2", run: () => editor.redo() },
  "sep",
  { label: "Accent color", mark: "palette", run: () => theme.pickColor() },
  {
    // 絵は「押すと何になるか」（切り替えた先）を言う。字と同じ向き
    label: theme.isLight() ? "Dark theme" : "Light theme",
    mark: theme.isLight() ? "moon" : "sun",
    run: () => theme.toggle(),
  },
  "sep",
  // 但し書きは待たずに開いて、届いたら埋まる（測るのに gzip が要る）
  { label: "Copy link", mark: "link", note: linkNote(), done: copyLink },
  "sep",
  {
    label: "Shortcuts",
    mark: "keyboard",
    run: () => openExternal(`${REPO}/blob/main/docs/shortcuts.md`),
  },
  { label: "GitHub", mark: "mark-github", run: () => openExternal(REPO) },
]);

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
  if (text === savedText) return;
  event.preventDefault();
  event.returnValue = "";
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
  empty: () => doc.trees.length === 0,
  button: el("btn-export", HTMLButtonElement),
  wayButton: el("btn-export-way", HTMLButtonElement),
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
  export: () => exportApi.run(),
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
    if (docGen === bootGen && text === "") loadText(shared, null);
  });
}
// フェンスの言語は後から読み込まれる。届いたら色を載せ直す
onLanguageReady(() => map.render());

editor.focus();
