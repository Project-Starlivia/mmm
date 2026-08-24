// Orchestrator: single document model lives in the MoonBit core; both panes
// mirror it (spec 4.2). Selection, focus, persistence and file I/O live
// here, along with the glue that pure decision logic elsewhere (app/paste,
// app/name...) doesn't own: clipboard-paste dispatch, drag & drop, and the
// global keyboard shortcuts.

// style.css は index.html の <link> で読む（FOUC を避けるため head 側）
import {
  core,
  type DocView,
  type EditOp,
  type NodeInfo,
  type Snapshot,
} from "./coreApi";
import { MdEditor } from "./editor";
import { MindMap, type MapHost } from "./mindmap";
import { io, type Doc } from "./app/io";
import { initAssets } from "./app/assets";
import { initExport } from "./app/export";
import { initPanes } from "./app/panes";
import { deriveName } from "./app/name";
import { initTheme } from "./app/theme";
import { sweep } from "./app/persist";
import { decidePaste } from "./app/paste";
import { onLanguageReady } from "./map/highlight";
import { type CardRef, cardRows, contentEndOf } from "./map/cards";
import { moveCard, removeCard } from "./map/cardEdit";

const $ = <T extends HTMLElement>(id: string): T => {
  const el = document.getElementById(id);
  if (!el) throw new Error(`missing element #${id}`);
  return el as T;
};

const mdPane = $("md-pane");
const mapPane = $("map-pane");
const btnNew = $<HTMLButtonElement>("btn-new");
const btnOpen = $<HTMLButtonElement>("btn-open");
const btnSave = $<HTMLButtonElement>("btn-save");
const btnUndo = $<HTMLButtonElement>("btn-undo");
const btnRedo = $<HTMLButtonElement>("btn-redo");
const elFilename = $("filename");
const elDirty = $("dirty");
const elLogo = $("logo");

// ---------- app state ----------

/** いまの文書（テキスト・ノード・フェンスの組）。スナップショットごと差し替える */
let doc: DocView = { text: "", nodes: [], fences: [] };
let byId = new Map<number, NodeInfo>();
let selection = new Set<number>();
let anchorId = -1;
/**
 * 選ばれているカード。ノードの選択とは**どちらか一方だけ**が空でない。
 * 片方を選ぶともう片方は外れる — 選ばれているものが 2 種類あると、
 * Delete や Alt+↑↓ が何に効くのか決まらない。
 */
let picked: CardRef | null = null;
let sessionN = 0;
/** loadText を呼ぶたびに進む世代番号。起動時の前回ファイル読み込みが、
 * その間に New/Open/Drop で別の(空の)文書を開いていた場合まで
 * 上書きしてしまわないためのガード。 */
let docGen = 0;
let savedText = "";
/**
 * 保存済みのファイル名。まだ保存していない文書では null で、名前は本文の
 * 見出しから導出する（app/name.ts）。「無題」という状態は持たない。
 * 実ファイルは File System Access API のハンドルが指す。
 */
let savedName: string | null = null;


// ---------- sync ----------

type Origin = "cm" | "map" | "core" | "load";

function applySnap(snap: Snapshot, origin: Origin): void {
  doc = { text: core.getText(), nodes: snap.nodes, fences: snap.fences };
  byId = new Map(doc.nodes.map((n) => [n.id, n]));
  if (origin !== "cm" && origin !== "load") editor.applySets(snap.editSets);
  // prune selection to surviving nodes
  let selChanged = false;
  for (const id of [...selection]) {
    if (!byId.has(id)) {
      selection.delete(id);
      selChanged = true;
    }
  }
  if (anchorId !== -1 && !byId.has(anchorId)) {
    anchorId = selection.size ? [...selection][selection.size - 1] : -1;
    selChanged = true;
  }
  // カードも同じく刈る。指したままだと、キーはカードの枝に吸われ続けて
  // 矢印も Delete も無反応になる（cardOf は範囲外を null で返すだけで、
  // 選択そのものは落とさない）。cardRows は安くないので、選んでいるときだけ
  if (picked !== null && !cardOf(picked)) {
    picked = null;
    selChanged = true;
  }
  // structural edits from elsewhere invalidate the typing-merge chain
  if (origin !== "cm") editKind = "";
  map.render();
  if (selChanged) syncSelectionViews(false);
  btnUndo.disabled = !snap.canUndo;
  btnRedo.disabled = !snap.canRedo;
  updateDirty();
  showName();
}

function updateDirty(): void {
  elDirty.hidden = core.getText() === savedText;
}

/** いまの文書の名前。保存済みならそのファイル名、まだなら本文から導く */
function docName(): string {
  return savedName ?? `${deriveName(doc.nodes)}.md`;
}

/**
 * 名乗りを出し直す。本文を打つそばからタイトルが変わる。
 * タブは名前を持つ文書のときだけ名乗る（`filename.md - mmm`）。
 * まっさらな文書に `empty.md` と名乗らせても何も伝わらない。
 */
function showName(): void {
  const name = savedName ?? (doc.nodes.length ? docName() : null);
  document.title = name === null ? "mmm" : `${name} - mmm`;
  // ファイル名欄は flash 中だけ別のことを言っている。終わったら戻る
  if (flashTimer === -1) elFilename.textContent = docName();
}

/** CardRef からいまのカードを引く。範囲外なら null（選択は落とす）。 */
function cardOf(ref: CardRef | null) {
  if (!ref) return null;
  const rows = cardRows(doc, new Set<number>()).get(ref.node);
  return rows?.[ref.index] ?? null;
}

/** そのノードの本文の終わり（末尾へ落としたときの挿入位置）。
 * 式そのものは src/map/cards.ts が唯一の定義。 */
function contentEnd(id: number): number {
  return contentEndOf(doc.nodes, id) ?? doc.text.length;
}

/**
 * 選択の見た目を貼り直す。`repaint` はカードの選択が出入りしたとき —
 * カードの枠と × は render が**要素として**作るので、クラスを張り替えるだけの
 * 軽い経路（refreshSelection）では出ても消えてもくれない。
 */
function syncSelectionViews(reveal: boolean, repaint = false): void {
  if (repaint) map.render();
  else map.refreshSelection();
  const card = cardOf(picked);
  editor.highlight(
    card
      ? [{ from: card.from, to: card.to }]
      : [...selection]
          .map((id) => byId.get(id))
          .filter((n): n is NodeInfo => !!n)
          .map((n) => ({ from: n.hs, to: n.subEnd })),
  );
  if (reveal && anchorId !== -1) {
    const n = byId.get(anchorId);
    if (n) editor.reveal(n.hs);
  }
}

function setSelection(ids: number[], anchor: number, reveal = true): void {
  // 相互排他。ids が空でも落とす — clearSelection/Escape が空配列を渡すため、
  // ids.length で分岐すると空クリックのときだけ picked が居座ってしまう
  const hadCard = picked !== null;
  picked = null;
  selection = new Set(ids);
  anchorId = anchor;
  syncSelectionViews(reveal, hadCard);
}

/** Run a structural command; optionally focus / edit the resulting node. */
function runCmd(
  fn: () => Snapshot,
  opts: { edit?: { tag: string } } = {},
): void {
  const snap = fn();
  applySnap(snap, "map");
  if (snap.focus !== -1 && byId.has(snap.focus)) {
    setSelection([snap.focus], snap.focus);
    map.ensureVisible(snap.focus);
    if (opts.edit) map.beginEdit(snap.focus, opts.edit.tag);
  }
}

// ---------- markdown pane -> core ----------

let editTag = "";
let editKind = "";
let editPos = -1;

function onUserEdits(edits: EditOp[], userEvent: string): void {
  if (userEvent === "compose.end") {
    editKind = ""; // next edit (compose or not) starts a fresh undo entry
    return;
  }
  let tag = "";
  if (userEvent === "input.type.compose") {
    // IME: every composition update replaces the previous candidate text;
    // keep ONE tag for the whole composition so undo treats it as one edit
    if (editKind !== "compose") {
      editTag = `t${++sessionN}`;
      editKind = "compose";
    }
    tag = editTag;
  } else if (edits.length === 1) {
    const e = edits[0];
    const pureInsert = e.from === e.to && e.insert.length > 0;
    const pureDelete = e.insert === "" && e.to > e.from;
    if (userEvent === "input.type" && pureInsert) {
      if (editKind === "type" && e.from === editPos) {
        tag = editTag;
      } else {
        tag = `t${++sessionN}`;
      }
      editKind = "type";
      editTag = tag;
      editPos = e.from + e.insert.length;
    } else if (userEvent === "delete.backward" && pureDelete) {
      if (editKind === "del" && e.to === editPos) {
        tag = editTag;
      } else {
        tag = `t${++sessionN}`;
      }
      editKind = "del";
      editTag = tag;
      editPos = e.from;
    } else {
      editKind = "";
    }
  } else {
    editKind = "";
    tag = `t${++sessionN}`; // multi-cursor transaction: one undo entry
  }
  let delta = 0;
  let snap: Snapshot | null = null;
  for (const e of edits) {
    snap = core.replaceText(e.from + delta, e.to + delta, e.insert, tag);
    delta += e.insert.length - (e.to - e.from);
  }
  if (snap) applySnap(snap, "cm");
}

// ---------- mindmap host ----------

const host: MapHost = {
  doc: () => doc,
  chooseImageFolder: () => void assets.chooseFolder(),
  replaceText(from, to, text) {
    applySnap(core.replaceText(from, to, text, `c${++sessionN}`), "map");
  },
  selection: () => selection,
  anchor: () => anchorId,
  setSelection: (ids, anchor, reveal) => setSelection(ids, anchor, reveal),
  clearSelection: () => setSelection([], -1, false),
  pickedCard: () => picked,
  pickCard(ref) {
    picked = ref;
    if (ref) {
      selection = new Set();
      anchorId = -1;
    }
    syncSelectionViews(false, true);
  },
  deleteCard(ref) {
    const row = cardOf(ref);
    if (!row) return;
    picked = null;
    const e = removeCard(core.getText(), row.from, row.to);
    applySnap(core.replaceText(e.from, e.to, e.insert, `x${++sessionN}`), "map");
  },
  reorderCard(ref, dir) {
    const rows = cardRows(doc, new Set<number>()).get(ref.node);
    const row = rows?.[ref.index];
    const next = rows?.[ref.index + dir];
    if (!rows || !row || !next) return; // 端では何もしない
    // 下へ動かすときは相手の後ろ、上へ動かすときは相手の頭へ入れる。
    // next.to は次の行の直後（次の改行の手前、または改行の無い文書末）を
    // 指す — next.to + 1 だと改行の無い文書末で文書長を超えてしまう。
    // moveCard 側は between を書き戻すだけなので、+1 せずとも行は割れない
    const at = dir === 1 ? next.to : next.from;
    const e = moveCard(core.getText(), row.from, row.to, at);
    if (!e) return;
    picked = { node: ref.node, index: ref.index + dir };
    applySnap(core.replaceText(e.from, e.to, e.insert, `m${++sessionN}`), "map");
  },
  moveCardTo(ref, node, index) {
    const text = core.getText();
    const all = cardRows(doc, new Set<number>());
    const row = all.get(ref.node)?.[ref.index];
    if (!row) return false;
    const target = all.get(node) ?? [];
    // 落とし先の行頭。末尾なら、そのノードの本文の終わりへ
    const dst = target[index];
    const at = dst ? dst.from : contentEnd(node);
    const e = moveCard(text, row.from, row.to, at);
    if (!e) return false;
    // 着地した後の実際の index。同じノードの中で下へ動かすときだけ、
    // 自分を抜いた分 1 つ前へ詰まる（Alt+↓ の reorderCard と同じ考え方）。
    // ここで動いた先を picked に付け直すので、ドラッグで動かしたカードも
    // Alt+↓ と同じく選択が付いてくる — 続けて Alt+↓ を押しても同じ
    // カードが動く
    const landing =
      node === ref.node && index > ref.index ? index - 1 : dst ? index : target.length;
    picked = { node, index: landing };
    applySnap(core.replaceText(e.from, e.to, e.insert, `d${++sessionN}`), "map");
    return true;
  },

  addChild(id) {
    if (!byId.has(id)) return;
    const tag = `s${++sessionN}`;
    runCmd(() => core.addChild(id, tag), { edit: { tag } });
  },
  addSibling(id) {
    if (!byId.has(id)) return;
    const tag = `s${++sessionN}`;
    runCmd(() => core.addSibling(id, tag), { edit: { tag } });
  },
  addSiblingBefore(id) {
    if (!byId.has(id)) return;
    const tag = `s${++sessionN}`;
    runCmd(() => core.addSiblingBefore(id, tag), { edit: { tag } });
  },
  addParent(id) {
    if (!byId.has(id)) return;
    const tag = `s${++sessionN}`;
    runCmd(() => core.addParent(id, tag), { edit: { tag } });
  },
  addRoot() {
    const tag = `s${++sessionN}`;
    runCmd(() => core.addRoot(tag), { edit: { tag } });
  },
  rename(id, label, tag) {
    applySnap(core.renameNode(id, label, tag), "map");
    // md ペイン側のハイライトは選択の範囲で描いている。ラベルの長さが
    // 変わると範囲がずれるので、貼り直す
    syncSelectionViews(false);
  },
  commitEdit() {
    if (!map.isEditingLabel()) return;
    const id = map.editingId;
    map.endEdit();
    if (byId.has(id)) setSelection([id], id);
  },
  deleteSelection() {
    if (selection.size === 0) return;
    const snap = core.deleteNodes([...selection]);
    applySnap(snap, "map");
    if (snap.focus !== -1 && byId.has(snap.focus)) {
      setSelection([snap.focus], snap.focus);
      // 他のコマンドは runCmd 経由でここまでやる。削除だけ落ちていたので、
      // 画面外のノードを消すと選択が画面外に置き去りになっていた
      map.ensureVisible(snap.focus);
    } else {
      setSelection([], -1, false);
    }
  },
  indentSelection() {
    if (selection.size === 0) return;
    applySnap(core.indentNodes([...selection]), "map");
    syncSelectionViews(false);
  },
  outdentSelection() {
    if (selection.size === 0) return;
    applySnap(core.outdentNodes([...selection]), "map");
    syncSelectionViews(false);
  },
  reorder(id, dir) {
    runCmd(() => core.reorderNode(id, dir));
  },
  toggleHidden(id) {
    runCmd(() => core.toggleHidden(id));
  },
  move(ids, target, pos) {
    // pos 3 = A→B の線に落とした: ids が B の親になるよう割り込む
    runCmd(() =>
      pos === 3
        ? core.moveAsParent(ids, target)
        : core.moveNodes(ids, target, pos),
    );
  },
  copySelection(cut) {
    if (selection.size === 0) return;
    const text = core.selectionText([...selection]);
    void navigator.clipboard.writeText(text).catch(() => {});
    if (cut) host.deleteSelection();
  },
  paste() {
    // paste as CHILD of the focused node (mmm.md 課題); into an empty
    // document the clip is inserted verbatim
    if (anchorId === -1 && doc.nodes.length > 0) return;
    void (async () => {
      // an image on the clipboard wins over text (mmm.md そのに: 画像配置)
      //
      // try で囲うのは**クリップボードを読むところだけ**。画像を置く処理まで
      // 囲うと、フォルダ選択の失敗が「クリップボードが読めなかった」と
      // 同じ扱いになり、黙ってテキスト経路へ落ちてしまう
      let img: Blob | null = null;
      try {
        if (anchorId !== -1 && "read" in navigator.clipboard) {
          for (const item of await navigator.clipboard.read()) {
            const t = item.types.find((x) => x.startsWith("image/"));
            if (t) {
              img = await item.getType(t);
              break;
            }
          }
        }
      } catch {
        /* clipboard.read unavailable/denied → try the text path */
      }
      if (img) {
        await pasteImage(img);
        return;
      }
      const clip = await navigator.clipboard.readText();
      const n0 = anchorId !== -1 ? (byId.get(anchorId) ?? null) : null;
      if (anchorId !== -1 && !n0) return;
      // 何を貼るか(URL/子ノード/子ツリー)の判定は app/paste.ts の純粋関数。
      // ここは clipboard の I/O と、結果を core へ適用する側だけを持つ
      const action = decidePaste(
        clip,
        n0 ? { depth: n0.depth } : null,
        doc.nodes.length > 0,
      );
      switch (action.kind) {
        case "noop":
          return;
        case "link":
          insertContentLine(anchorId, action.url);
          return;
        case "rootTree": {
          // 空の文書: 先頭行をルート、残りをその子として立てる
          const t0 = core.getText();
          const pre = t0 === "" ? "" : t0.endsWith("\n") ? "\n" : "\n\n";
          applySnap(
            core.replaceText(t0.length, t0.length, pre + action.body + "\n", ""),
            "map",
          );
          return;
        }
        case "children":
          insertBlock(n0!.subEnd, action.body);
          return;
        case "block": {
          const at = anchorId === -1 ? core.getText().length : n0!.subEnd;
          insertBlock(at, action.body);
          return;
        }
      }
    })().catch(() => {});
  },
  imageUrl: (path) => assets.imageUrl(path),
  editRequested(id) {
    if (!byId.has(id)) return;
    setSelection([id], id);
    const tag = `s${++sessionN}`;
    map.beginEdit(id, tag);
  },
  undo: () => doUndo(),
  redo: () => doRedo(),
};

// ---------- boot panes ----------

const editor = new MdEditor(mdPane, onUserEdits);
const map = new MindMap(mapPane, host);

// ---------- 改行の正規化 (F-010) ----------
//
// アプリの中では常に LF に統一する。CodeMirror は読み込んだ文書の改行を
// 内部で LF に正規化し、コアは受け取ったバイト列をそのまま持つ。両者に
// 別々の改行を渡すと、CodeMirror が出す LF 基準のオフセットがコア側でずれ、
// **打鍵が見当違いの位置に書き込まれて表示と保存内容が乖離する**。
// 読み込み時に LF へ揃え、保存も UTF-8 / LF で書く。

function loadText(text: string, name: string | null): void {
  docGen++;
  savedName = name;
  assets.clear(); // image paths are relative to the (new) md
  picked = null;
  setSelection([], -1, false);
  const snap = core.initDoc(text);
  editor.setText(text);
  applySnap(snap, "load"); // 名乗りもここで出る
  map.fitView();
}

// ---------- undo / redo ----------

function doUndo(): void {
  applySnap(core.undo(), "core");
  syncSelectionViews(false);
}
function doRedo(): void {
  applySnap(core.redo(), "core");
  syncSelectionViews(false);
}
btnUndo.addEventListener("click", doUndo);
btnRedo.addEventListener("click", doRedo);

// ---------- file I/O ----------

/** 開いた文書を UI に載せる。 */
function applyDoc(doc: Doc): void {
  savedText = doc.text;
  loadText(doc.text, doc.name);
}

async function openFile(): Promise<void> {
  try {
    if (!(await confirmDiscard())) return;
    const doc = await io.openDialog();
    if (doc) applyDoc(doc);
  } catch (err) {
    console.error("open failed:", err);
    flashFilename("読み込み失敗");
  }
}

/**
 * 保存。`asNew`（別名で保存）と、まだ名前の無い文書はダイアログを出す。
 * ダイアログの初期値はいまの名前 — 保存済みならそのファイル名、まだなら
 * 本文から導いたもの（app/name.ts）。
 */
async function saveFile(asNew = false): Promise<void> {
  const text = core.getText();
  try {
    if (asNew || savedName === null) {
      const doc = await io.saveAs(docName(), text);
      if (!doc) return; // キャンセル
      savedName = doc.name; // ここで初めて名前が決まる
      showName();
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
    // 自分でキャンセルしたときは null が返るのでここには来ない。
    console.error("save failed:", err);
    flashFilename(typeof err === "string" ? err : "保存失敗");
  }
}

let flashTimer = -1;
function flashFilename(msg: string, isError = true): void {
  elFilename.textContent = `${docName()} \u2014 ${msg}`;
  elFilename.classList.toggle("error", isError);
  if (flashTimer !== -1) window.clearTimeout(flashTimer);
  flashTimer = window.setTimeout(() => {
    flashTimer = -1;
    elFilename.classList.remove("error");
    showName();
  }, 4000);
}

/**
 * 新しい文書。いまの文書は捨て、ファイルハンドルも手放す
 * （残すと、未保存の新規文書に貼った画像が前の文書の隣に置かれる）。
 */
async function newFile(): Promise<void> {
  try {
    if (!(await confirmDiscard())) return;
    await io.close();
    savedText = "";
    loadText("", null);
    mapPane.focus();
  } catch (err) {
    console.error("new file failed:", err);
    flashFilename("新規作成に失敗しました");
  }
}

async function confirmDiscard(): Promise<boolean> {
  if (core.getText() === savedText) return true;
  return window.confirm("未保存の変更があります。破棄して続行しますか？");
}

// ---------- images (mmm.md そのに: 画像配置 — local-first) ----------
// 実装は app/assets.ts。ここは「いまのファイル」と描き直しを繋ぐだけ

const assets = initAssets({
  hasFile: () => savedName !== null,
  warn: (m) => flashFilename(m),
  refresh: () => map.render(),
});

/**
 * `body` を独立した段落として `at` へ挿し込む。前後に必要なだけ空行を足し
 * (直前が改行 0/1/2 個かで prefix を出し分け、直後が文書末でなければ改行
 * 1 個を足す)、1 つの Snapshot として適用する。
 */
function insertBlock(at: number, body: string, tag = ""): void {
  const text = core.getText();
  let prefix = "";
  if (at > 0 && text[at - 1] !== "\n") prefix = "\n\n";
  else if (at >= 2 && text[at - 2] !== "\n") prefix = "\n";
  const suffix = at !== text.length ? "\n" : "";
  applySnap(core.replaceText(at, at, prefix + body + "\n" + suffix, tag), "map");
}

/** Append a line at the END of a node's own attached content (before its
 * first child heading), as one undo entry. */
function insertContentLine(id: number, line: string, tag = ""): void {
  if (!byId.has(id)) return;
  insertBlock(contentEnd(id), line, tag);
}

async function pasteImage(blob: Blob): Promise<void> {
  const targetId = anchorId;
  if (!byId.has(targetId)) return;
  const rel = await assets.saveToDisk(blob);
  if (rel !== null && byId.has(targetId)) {
    insertContentLine(targetId, `![](${rel})`);
  }
}

btnNew.addEventListener("click", () => void newFile());
btnOpen.addEventListener("click", () => void openFile());
btnSave.addEventListener("click", () => void saveFile());
elFilename.addEventListener("click", () => {
  void (async () => {
    if (!(await confirmDiscard())) return;
    const doc = await io.restoreDoc();
    if (doc) applyDoc(doc);
  })().catch(() => flashFilename("ファイルの許可を取得できませんでした"));
});

window.addEventListener("beforeunload", (event) => {
  if (core.getText() === savedText) return;
  event.preventDefault();
  event.returnValue = "";
});

// ---------- drag & drop ----------

const IMG_RE = /\.(png|jpe?g|gif|webp|svg|avif|bmp)$/i;
const MD_RE = /\.(md|markdown|txt)$/i;

async function droppedHandles(data: DataTransfer): Promise<FileSystemFileHandle[]> {
  const files: FileSystemFileHandle[] = [];
  for (const item of data.items) {
    if (item.kind !== "file" || !item.getAsFileSystemHandle) continue;
    const handle = await item.getAsFileSystemHandle();
    if (handle?.kind === "file") files.push(handle as FileSystemFileHandle);
  }
  return files;
}

window.addEventListener("dragover", (event) => {
  if ([...event.dataTransfer?.items ?? []].some((item) => item.kind === "file")) {
    event.preventDefault();
  }
});

window.addEventListener("drop", (event) => {
  event.preventDefault();
  const data = event.dataTransfer;
  if (!data) return;
  void (async () => {
    const handles = await droppedHandles(data);
    const md = handles.find((file) => MD_RE.test(file.name));
    if (md) {
      if (!(await confirmDiscard())) return;
      applyDoc(await io.openHandle(md));
      return;
    }
    const images = handles.filter((file) => IMG_RE.test(file.name));
    if (images.length === 0) return;
    const id = map.nodeAt(event.clientX, event.clientY);
    if (!byId.has(id)) {
      flashFilename("画像はノードの上に落としてください");
      return;
    }
    const tag = `d${++sessionN}`;
    for (const handle of images) {
      const rel = await assets.saveToDisk(await handle.getFile());
      if (rel !== null && byId.has(id)) insertContentLine(id, `![](${rel})`, tag);
    }
  })().catch((error) => {
    console.error("drop failed:", error);
    flashFilename("ドロップしたファイルを開けませんでした");
  });
});

// ---------- global shortcuts ----------

window.addEventListener(
  "keydown",
  (e) => {
    if (e.isComposing || e.keyCode === 229) return;
    const mod = e.ctrlKey || e.metaKey;
    if (!mod) return;
    const key = e.key.toLowerCase();
    if (key === "s") {
      e.preventDefault();
      void saveFile(e.shiftKey); // Shift = 別名で保存
    } else if (key === "n" && e.altKey) {
      // `Mod+N` はブラウザの「新規ウィンドウ」に吸われてページまで来ない
      e.preventDefault();
      void newFile();
    } else if (key === "o") {
      e.preventDefault();
      void openFile();
    } else if (key === "/") {
      e.preventDefault();
      togglePane();
    } else if (key === "z" || key === "y") {
      // 入力欄（ラベル / カード）が開いている間は、その欄のネイティブな
      // undo に任せる。文書の undo を割り込ませると、開いたままの入力欄が
      // 指す範囲だけが古くなり、確定で別の場所を上書きしてしまう
      if (map.isEditing()) return;
      e.preventDefault();
      e.stopPropagation();
      if (key === "y" || e.shiftKey) doRedo();
      else doUndo();
    }
  },
  { capture: true },
);

// ---------- pane / splitter / export / theme（実装は app/ 配下） ----------

const { togglePane, togglePaneVis } = initPanes({
  mdPane,
  mapPane,
  panesEl: $("panes"),
  splitter: $("splitter"),
  mdButton: $<HTMLButtonElement>("btn-view-md"),
  mapButton: $<HTMLButtonElement>("btn-view-map"),
  focusEditor: () => editor.focus(),
});

// ペインの表示/非表示は Alt+数字（左から 1, 2）。
// 矢印は使えない — Ctrl+←→ はテキスト欄の単語移動で、書いている最中に一番使う。
// Ctrl+数字（タブ切替）・Ctrl+J（ダウンロード）・Ctrl+Shift+R（再読込）は
// ブラウザの予約。Alt+数字はどちらにも触らず、JIS でも物理位置が動かない。
window.addEventListener("keydown", (e) => {
  if (e.isComposing || e.keyCode === 229) return;
  if (!e.altKey || e.ctrlKey || e.metaKey) return;
  const pane = { "1": "md", "2": "map" }[e.key] as "md" | "map" | undefined;
  if (!pane) return;
  e.preventDefault();
  togglePaneVis(pane);
});
initExport({
  map,
  name: () => docName(),
  notify: (msg, isError = true) => flashFilename(msg, isError),
});
initTheme({
  logo: elLogo,
  themeButton: $<HTMLButtonElement>("btn-theme"),
  setEditorTheme: (dark) => editor.setTheme(dark),
});

// ---------- boot ----------

// 本文の控えは持たない。IndexedDB に置くのはファイルハンドルだけで、
// 起動時もディスク上の実体を読み直す。
{
  sweep(); // 役目を終えた localStorage のキーを捨てる
  loadText("", null); // 空 = まだ何も無い。dirty も立たない
  const bootGen = docGen;
  void io
    .startupDoc()
    .then((doc) => {
      // 読み終わるまでに打ち始めていたら、それを消してまで開かない。
      // 同じ理由で、その間に New/Open/Drop で別の文書を開いていた場合も
      // （それが空文書でも）上書きしない — その操作は必ず loadText を通るので
      // docGen が進んでいるはず
      if (doc && docGen === bootGen && core.getText() === "") applyDoc(doc);
    })
    .catch(() => {
      flashFilename("前回のファイルを開けませんでした");
    });
}
// フェンスの言語は後から読み込まれる。届いたら色を載せ直す
onLanguageReady(() => map.render());

mapPane.focus();
