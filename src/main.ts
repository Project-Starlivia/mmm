// 束ねる場所。文書そのものは MoonBit コアが 1 つだけ持ち、2 枚のペインは
// どちらもその写し。ここに居るのは、選択・フォーカス・保存とファイル I/O、
// そして純粋な判断（app/paste, app/name…）が引き受けない繋ぎ —
// クリップボードの振り分け、ドラッグ&ドロップ、全体のショートカット。

// style.css は index.html の <link> で読む（FOUC を避けるため head 側）
import {
  core,
  type DocView,
  type EditOp,
  type NodeInfo,
  type Snapshot,
} from "./coreApi.ts";
import { MdEditor } from "./editor.ts";
import { MindMap, type MapHost } from "./mindmap.ts";
import { io, type Doc } from "./app/io.ts";
import { initAssets } from "./app/assets.ts";
import { exportWays, initExport } from "./app/export.ts";
import { initPanes } from "./app/panes.ts";
import { deriveName } from "./app/name.ts";
import { initTheme } from "./app/theme.ts";
import { LS_ADDS, load, store, sweep } from "./app/persist.ts";
import { decidePaste } from "./app/paste.ts";
import { initDrop } from "./app/dnd.ts";
import { initForm } from "./app/form.ts";
import { showDrawing } from "./app/draw.ts";
import { initShortcuts } from "./app/shortcuts.ts";
import { onLanguageReady } from "./map/highlight.ts";
import { openOnClick } from "./map/menu.ts";
import { RadialMenu } from "./map/radialMenu.ts";
import {
  type CardRef,
  cardRowsOf,
  contentEndOf,
  linkLine,
} from "./map/cards.ts";
import { insertBlock, moveLine, removeLine } from "./edits.ts";

/**
 * index.html の要素を、**その型であることを実際に確かめて**引く。
 * `as` で名乗るだけだと、タグを替えたときに誰も気づけない — `<button>` を
 * `<span>` にしたら `disabled` が黙って効かなくなるし、`<svg id="logo">` を
 * `HTMLElement` と名乗るのは**そもそも嘘**だった（SVG は HTML ではない）。
 *
 * DOM を id で引くのはこのファイルだけ。他のモジュールは受け取る。
 */
function el<T extends Element>(id: string, kind: abstract new () => T): T {
  const found = document.getElementById(id);
  if (found instanceof kind) return found;
  throw new Error(`#${id} が ${kind.name} ではない`);
}

/** ヘルプの行き先。ここ 1 か所 */
const REPO = "https://github.com/Project-Starlivia/mmm";

const mdPane = el("md-pane", HTMLElement);
const mapPane = el("map-pane", HTMLElement);
const btnFile = el("btn-file", HTMLButtonElement);
const btnMore = el("btn-more", HTMLButtonElement);
const elFilename = el("filename", HTMLElement);
const elDirty = el("dirty", HTMLElement);
const elLogo = el("logo", SVGSVGElement);

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
/**
 * お絵描きが開いているか。開いている間は全体の `Mod+Z` を止める
 * （その中の取り消しに譲る）。門を 2 つ作らないよう、入力欄と同じ
 * `isEditing` の判定に合流させる。
 */
let drawingOpen = false;


// ---------- sync ----------

/**
 * そのスナップショットを誰が起こしたか。振る舞いが変わるのは 3 通りだけ。
 * - `cm`   … MD ペインの打鍵。CodeMirror には既に入っているので送り返さない
 * - `load` … 文書まるごとの入れ替え。setText が済んでいる
 * - `core` … それ以外（マップの操作・undo/redo）。MD ペインへ差分を送る
 */
type Origin = "cm" | "load" | "core";

function applySnap(snap: Snapshot, origin: Origin): void {
  // 何も無いところに最初の 1 つが生まれた瞬間だけ、真ん中へ寄せる。
  // `ensureVisible` は「見えるところまで」しか動かさないので、まっさらな
  // 画面では端に置かれたように見える
  const wasEmpty = doc.nodes.length === 0;
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
  // render がクラスまで塗り終えているので、ここで塗り直さない
  if (selChanged) syncSelectionViews(false, true);
  updateDirty();
  showName();
  form.show(snap.listFrom);
  if (wasEmpty && doc.nodes.length > 0) map.fitView();
}

function updateDirty(): void {
  elDirty.hidden = doc.text === savedText;
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
  const title = name === null ? "mmm" : `${name} - mmm`;
  // 打鍵のたびに呼ばれるので、変わっていないなら DOM に触らない
  if (document.title !== title) document.title = title;
  // ファイル名欄は flash 中だけ別のことを言っている。終わったら戻る
  if (flashTimer !== -1) return;
  const shown = docName();
  if (elFilename.textContent !== shown) elFilename.textContent = shown;
}

/** CardRef からいまのカードを引く。範囲外なら null（選択は落とす）。 */
function cardOf(ref: CardRef | null) {
  return ref ? (cardRowsOf(doc, ref.node)[ref.index] ?? null) : null;
}

/** そのノードの本文の終わり（末尾へ落としたときの挿入位置）。
 * 式そのものは src/map/cards.ts が唯一の定義。 */
function contentEnd(id: number): number {
  return contentEndOf(doc.nodes, id) ?? doc.text.length;
}

/**
 * 選択の見た目を貼り直す。`painted` は「地図側は直前に描き終えている」印
 * （applySnap の中だけ）。それ以外は地図にも塗り直しを頼む。
 */
function syncSelectionViews(reveal: boolean, painted = false): void {
  if (!painted) map.refreshSelection();
  const card = cardOf(picked);
  editor.highlight(
    card
      ? [{ from: card.from, to: card.to }]
      : [...selection]
          .map((id) => byId.get(id))
          .filter((n): n is NodeInfo => !!n)
          .map((n) => ({ from: n.from, to: n.to })),
  );
  if (reveal && anchorId !== -1) {
    const n = byId.get(anchorId);
    if (n) editor.reveal(n.from);
  }
}

function setSelection(ids: number[], anchor: number, reveal = true): void {
  // 相互排他。ids が空でも落とす — clearSelection/Escape が空配列を渡すため、
  // ids.length で分岐すると空クリックのときだけ picked が居座ってしまう
  picked = null;
  selection = new Set(ids);
  anchorId = anchor;
  syncSelectionViews(reveal);
}

/**
 * undo の粒度を分ける印。**tag が違えば必ず別の undo になる**ので、
 * 番号が違うだけで足りる（用途ごとに接頭辞を変えていた頃、番号が既に
 * 一意なので接頭辞は何も区別していなかった）。
 * 同じ tag を続けて渡すと 1 つの undo にまとまる（打鍵の連結）。
 */
let tagN = 0;
const nextTag = (): string => `t${++tagN}`;

/** ノードを作るコマンドは、どれも「作って、そのまま編集に入る」。 */
function addNode(fn: (tag: string) => Snapshot): void {
  const tag = nextTag();
  runCmd(() => fn(tag), { edit: { tag } });
}

/** 構造を変えるコマンドを走らせ、結果のノードへ選択を移す（必要なら編集へ）。 */
function runCmd(
  fn: () => Snapshot,
  opts: { edit?: { tag: string } } = {},
): void {
  const snap = fn();
  applySnap(snap, "core");
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
      editTag = nextTag();
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
        tag = nextTag();
      }
      editKind = "type";
      editTag = tag;
      editPos = e.from + e.insert.length;
    } else if (userEvent === "delete.backward" && pureDelete) {
      if (editKind === "del" && e.to === editPos) {
        tag = editTag;
      } else {
        tag = nextTag();
      }
      editKind = "del";
      editTag = tag;
      editPos = e.from;
    } else {
      editKind = "";
    }
  } else {
    editKind = "";
    tag = nextTag(); // multi-cursor transaction: one undo entry
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
  addDrawing(id) {
    if (!byId.has(id) || drawingOpen) return;
    drawingOpen = true;
    void showDrawing()
      .then((blob) => (blob === null ? undefined : attachImage(id, blob)))
      .catch((error: unknown) => {
        console.error("drawing failed:", error);
        flashFilename("Could not add the drawing");
      })
      .finally(() => {
        drawingOpen = false;
        mapPane.focus();
      });
  },
  addLink(id) {
    if (!byId.has(id)) return;
    void (async () => {
      const made = linkLine(await navigator.clipboard.readText());
      if (made === null) {
        flashFilename("Copy a link first");
        return;
      }
      insertContentLine(id, made.line, nextTag());
      // 足したカードはその本文の最後の 1 枚。そこを、題の上で開く
      const index = cardRowsOf(doc, id).length - 1;
      if (index >= 0) map.editCard({ node: id, index }, made.from, made.to);
    })().catch((error: unknown) => {
      console.error("link failed:", error);
      flashFilename("Could not read the clipboard");
    });
  },
  replaceText(from, to, text) {
    applySnap(core.replaceText(from, to, text, nextTag()), "core");
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
    syncSelectionViews(false);
  },
  deleteCard(ref) {
    const row = cardOf(ref);
    if (!row) return;
    picked = null;
    const e = removeLine(doc.text, row.from, row.to);
    applySnap(core.replaceText(e.from, e.to, e.insert, nextTag()), "core");
  },
  reorderCard(ref, dir) {
    const rows = cardRowsOf(doc, ref.node);
    const row = rows[ref.index];
    const next = rows[ref.index + dir];
    if (!row || !next) return; // 端では何もしない
    // 下へ動かすときは相手の後ろ、上へ動かすときは相手の頭へ入れる。
    // next.to は次の行の直後（次の改行の手前、または改行の無い文書末）を
    // 指す — next.to + 1 だと改行の無い文書末で文書長を超えてしまう。
    // moveCard 側は between を書き戻すだけなので、+1 せずとも行は割れない
    const at = dir === 1 ? next.to : next.from;
    const e = moveLine(doc.text, row.from, row.to, at);
    if (!e) return;
    picked = { node: ref.node, index: ref.index + dir };
    applySnap(core.replaceText(e.from, e.to, e.insert, nextTag()), "core");
  },
  moveCardTo(ref, node, index) {
    const row = cardRowsOf(doc, ref.node)[ref.index];
    if (!row) return false;
    const target = node === ref.node ? cardRowsOf(doc, ref.node) : cardRowsOf(doc, node);
    // 落とし先の行頭。末尾なら、そのノードの本文の終わりへ
    const dst = target[index];
    const at = dst ? dst.from : contentEnd(node);
    const e = moveLine(doc.text, row.from, row.to, at);
    if (!e) return false;
    // 着地した後の実際の index。同じノードの中で下へ動かすときだけ、
    // 自分を抜いた分 1 つ前へ詰まる（Alt+↓ の reorderCard と同じ考え方）。
    // ここで動いた先を picked に付け直すので、ドラッグで動かしたカードも
    // Alt+↓ と同じく選択が付いてくる — 続けて Alt+↓ を押しても同じ
    // カードが動く
    const landing =
      node === ref.node && index > ref.index ? index - 1 : dst ? index : target.length;
    picked = { node, index: landing };
    applySnap(core.replaceText(e.from, e.to, e.insert, nextTag()), "core");
    return true;
  },

  addChild(id) {
    if (byId.has(id)) addNode((tag) => core.addChild(id, tag));
  },
  addSibling(id) {
    if (byId.has(id)) addNode((tag) => core.addSibling(id, tag));
  },
  addSiblingBefore(id) {
    if (byId.has(id)) addNode((tag) => core.addSiblingBefore(id, tag));
  },
  addParent(id) {
    if (byId.has(id)) addNode((tag) => core.addParent(id, tag));
  },
  addRoot() {
    addNode((tag) => core.addRoot(tag));
  },
  rename(id, label, tag) {
    applySnap(core.renameNode(id, label, tag), "core");
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
    applySnap(snap, "core");
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
    applySnap(core.indentNodes([...selection]), "core");
    syncSelectionViews(false);
  },
  outdentSelection() {
    if (selection.size === 0) return;
    applySnap(core.outdentNodes([...selection]), "core");
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
  // 右クリックに出す「この枝の出し方」。ヘッダと同じ並びで、対象だけが違う
  exportWays: () => exportWays(exportDeps, false),
  paste() {
    // 貼り付け先は選んでいるノードの**子**。空の文書へはそのまま入れる
    if (anchorId === -1 && doc.nodes.length > 0) return;
    void (async () => {
      // クリップボードに画像があれば、テキストより優先する
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
        await attachImage(anchorId, img);
        return;
      }
      const clip = await navigator.clipboard.readText();
      // 選んでいるノード。選んでいるのに引けなかったら（消えた直後など）
      // 何もしない — 宛先が決まらない貼り方はしない
      const anchorNode = anchorId === -1 ? null : (byId.get(anchorId) ?? null);
      if (anchorId !== -1 && !anchorNode) return;
      // 何を貼るか(URL/子ノード/子ツリー)の判定は app/paste.ts の純粋関数。
      // ここは clipboard の I/O と、結果を core へ適用する側だけを持つ
      const action = decidePaste(
        clip,
        anchorNode ? { depth: anchorNode.depth } : null,
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
            "core",
          );
          return;
        }
        case "children":
          // decidePaste が children を返すのは anchor があるときだけ
          if (anchorNode) insertParagraph(anchorNode.to, action.body);
          return;
        case "block":
          insertParagraph(
            anchorNode ? anchorNode.to : doc.text.length,
            action.body,
          );
          return;
      }
    })().catch(() => {});
  },
  imageUrl: (path) => assets.imageUrl(path),
  editRequested(id) {
    if (!byId.has(id)) return;
    setSelection([id], id);
    map.beginEdit(id, nextTag());
  },
  undo: () => doUndo(),
  redo: () => doRedo(),
};

// ---------- boot panes ----------

const editor = new MdEditor(mdPane, onUserEdits);
const map = new MindMap(mapPane, host);

/**
 * 木の書き方（H / n+ / L）。押すとモードを変えて文書ぜんぶを書き直す。
 * 1 回の undo で戻る（モード自体は undo で戻らないが、読みはモードを
 * 知らないので、テキストが戻ればマップも戻る）。
 */
const form = initForm({
  pane: mdPane,
  apply: (b) => {
    core.setListFrom(b);
    applySnap(core.reformat(nextTag()), "core");
  },
});

/** 書き出しに要るもの。ヘッダ（全体）も右クリック（枝）も同じこれを使う */
const exportDeps = {
  map,
  name: () => docName(),
  notify: (msg: string, isError = true) => flashFilename(msg, isError),
};

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
    flashFilename("Could not open the file");
  }
}

/**
 * いま開いているファイル**そのもの**の名前を変える（同じフォルダの中での
 * 改名）。保存していなければ相手がディスクに無いので、Files のその行は
 * 無効になっている。本文の見出しから導く名前とは別の話。
 */
async function renameFile(): Promise<void> {
  if (savedName === null) return;
  const typed = window.prompt("New file name", savedName);
  if (typed === null) return;
  const name = typed.trim();
  if (name === "" || name === savedName) return;
  try {
    const next = await io.rename(name);
    if (next === null) return;
    savedName = next;
    showName();
  } catch (error) {
    flashFilename(
      error instanceof Error && error.message === "no-rename"
        ? "Renaming needs a Chromium browser"
        : "Could not rename the file",
    );
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
    flashFilename(typeof err === "string" ? err : "Could not save");
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
    flashFilename("Could not create a new file");
  }
}

async function confirmDiscard(): Promise<boolean> {
  if (core.getText() === savedText) return true;
  return window.confirm("You have unsaved changes. Discard them and continue?");
}

// ---------- 画像（ローカルファースト） ----------
// 実装は app/assets.ts。ここは「いまのファイル」と描き直しを繋ぐだけ

const assets = initAssets({
  hasFile: () => savedName !== null,
  warn: (m) => flashFilename(m),
  refresh: () => map.render(),
});

/** `body` を独立した段落として `at` へ挿し込む（式は src/edits.ts）。 */
function insertParagraph(at: number, body: string, tag = ""): void {
  const e = insertBlock(doc.text, at, body);
  applySnap(core.replaceText(e.from, e.to, e.insert, tag), "core");
}

/**
 * そのノードの本文の末尾へ 1 行を追加する（画像・URL・お絵描き・
 * `Shift+L` が通る唯一の道）。字下げも含めた形はコアが決める —
 * **リストの形のノードへ、列 0 のまま書いてはいけない**。列 0 のまま
 * 書くと、外の Markdown パーサはそこでリストを閉じ、続く兄弟が迷子になる
 * （実際に踏んだ）。
 */
function insertContentLine(id: number, line: string, tag = ""): void {
  if (!byId.has(id)) return;
  applySnap(core.insertContent(id, line, tag), "core");
}

/**
 * 画像をディスクへ置いて、そのノードの本文の末尾に `![]()` を足す。
 * **貼り付け・ドロップ・お絵描きが通る唯一の道** — WebP への変換も名前の
 * 確認も画像フォルダの結び付けも、`assets.saveToDisk` が 1 か所で持つ。
 */
async function attachImage(id: number, blob: Blob, tag = ""): Promise<void> {
  if (!byId.has(id)) return;
  const rel = await assets.saveToDisk(blob);
  // 置いているあいだに消えていることがある
  if (rel !== null && byId.has(id)) insertContentLine(id, `![](${rel})`, tag);
}

// 文書に何かする道は Files にまとめる。**画像フォルダもここ** —
// 「この .md の画像がどこに居るか」は文書ぜんぶの設定で、新規 / 開く / 保存と
// 同じ高さのもの。
//
// 見出し（caption）は「続く行たちが何に効くか」を言う。保存していない文書に
// 名前を変える相手は無いので、そのときは見出しがそう言い、行は無効になる。
openOnClick(btnFile, () => [
  { label: "New", key: "Mod+Alt+N", run: () => void newFile() },
  { label: "Open", key: "Mod+O", run: () => void openFile() },
  { caption: savedName ?? "not saved yet" },
  { label: "Rename", run: () => void renameFile(), disabled: savedName === null },
  { label: "Save", key: "Mod+S", run: () => void saveFile() },
  { label: "Save as", key: "Mod+Shift+S", run: () => void saveFile(true) },
  { caption: assets.folderName() ?? "none" },
  { label: "Images Folder", run: () => void assets.chooseFolder() },
]);

// 低頻度だが消したくないものの受け皿。Undo/Redo にボタンは無く（キーが
// 本道）、ここが押せる保険になる
openOnClick(btnMore, () => [
  { label: "Undo", key: "Mod+Z", run: doUndo },
  { label: "Redo", key: "Mod+Shift+Z", run: doRedo },
  "sep",
  { label: theme.isLight() ? "Dark theme" : "Light theme", run: () => theme.toggle() },
  // 見た目の好み同士なのでテーマの隣。**押せばどうなるか**を名乗る（テーマと同じ流儀）
  { label: addsOn ? "Hide add buttons" : "Show add buttons", run: () => setAdds(!addsOn) },
  "sep",
  { label: "Help", run: () => window.open(REPO, "_blank", "noopener") },
]);
elFilename.addEventListener("click", () => {
  void (async () => {
    if (!(await confirmDiscard())) return;
    const doc = await io.restoreDoc();
    if (doc) applyDoc(doc);
  })().catch(() => flashFilename("Could not get permission for the file"));
});

window.addEventListener("beforeunload", (event) => {
  if (core.getText() === savedText) return;
  event.preventDefault();
  event.returnValue = "";
});

// ---------- ドラッグ & ドロップ（振り分けは app/dnd.ts） ----------

initDrop({
  nodeAt: (x, y) => map.nodeAt(x, y),
  warn: (msg) => flashFilename(msg),
  async openMarkdown(file) {
    if (!(await confirmDiscard())) return;
    applyDoc(await io.openHandle(file));
  },
  async addImages(files, node) {
    // 複数落としても 1 回の undo で戻せるよう、同じ tag に揃える
    const tag = nextTag();
    for (const file of files) await attachImage(node, await file.getFile(), tag);
  },
});

// ---------- ペイン / スプリッタ / 書き出し / テーマ / キー（実装は app/ 配下） ----------

const { togglePane, togglePaneVis } = initPanes({
  mdPane,
  mapPane,
  panesEl: el("panes", HTMLElement),
  splitter: el("splitter", HTMLElement),
  focusEditor: () => editor.focus(),
});

const exportApi = initExport({
  ...exportDeps,
  button: el("btn-export", HTMLButtonElement),
  wayButton: el("btn-export-way", HTMLButtonElement),
});
const radialMenu = new RadialMenu();
const theme = initTheme({
  logo: elLogo,
  setEditorTheme: (dark) => editor.setTheme(dark),
});

// **物理キーボードの有無は Web からは分からない。**代わりに「主たるポインタが
// 指か」を見る。Surface はキーボードを外すと OS が主ポインタを指へ切り替える
// ので、この 1 本で狙いどおりに振れる。近似であることは承知の上で、外れても
// 人が押して直せる形にしてある（`⋯` の 1 行）。
//
// `any-pointer` ではなく `pointer` を使う: マウスも刺さっている機械で
// 「指もある」だけを理由に出しっぱなしにはしない。
const TOUCH_FIRST = "(pointer: coarse) and (hover: none)";

// localStorage の中身は何でもありうる。名乗らせずに確かめる
const savedAdds = load(LS_ADDS);
let addsOn =
  savedAdds === "on"
    ? true
    : savedAdds === "off"
      ? false
      : (window.matchMedia?.(TOUCH_FIRST).matches ?? false);

const setAdds = (on: boolean): void => {
  addsOn = on;
  store(LS_ADDS, on ? "on" : "off");
  map.setAddButtons(on);
};
map.setAddButtons(addsOn);

initShortcuts({
  save: (asNew) => void saveFile(asNew),
  open: () => void openFile(),
  create: () => void newFile(),
  togglePane,
  togglePaneVis,
  undo: doUndo,
  redo: doRedo,
  export: (pickWay) => (pickWay ? radialMenu.show(exportApi.ways()) : exportApi.run()),
  isEditing: () => map.isEditing() || drawingOpen,
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
      flashFilename("Could not reopen the last file");
    });
}
// フェンスの言語は後から読み込まれる。届いたら色を載せ直す
onLanguageReady(() => map.render());

mapPane.focus();
