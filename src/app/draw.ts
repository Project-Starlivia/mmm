// その場で描いて、画像として貼る。
//
// mmm の中に描く道は他に無い（外の道具で描いて貼ることはできるが、それは
// mmm を離れる）。**保存の道は増やさない** — 描いたものは貼り付けや
// ドロップとまったく同じ `assets.saveToDisk` を通るので、WebP への変換も
// 名前の確認も画像フォルダの結び付けも、そこ 1 か所が持ち続ける。
//
// キャンバスは**描いた順の並びの写像**として持つ。取り消しは末尾を落として
// 描き直すだけ — 1 枚ずつ画像を控える形だと、720×440 の 2 倍解像度で
// 1 手あたり 5MB になる。文書の undo が編集の集合を並べて再生するのと
// 同じ考え方。
//
// **道具は選ばせるのではなく、絞って並べる。** OS のカラーピッカーと生の
// スライダーは「何でも選べます」としか言っておらず、選ぶ手間だけを渡して
// くる。紙の上で読める色と、3 段の太さだけを出す。

import { icon } from "../icons.ts";
import { accent } from "./theme.ts";

/** 世界ではなくキャンバスの中の座標（CSS ピクセル） */
interface Pt {
  x: number;
  y: number;
}

/** 描いた順に積む手。取り消しはこの並びの末尾を落とす */
type Stroke =
  | { kind: "line"; points: Pt[]; color: string; width: number }
  | { kind: "clear" };

const WIDTH = 720;
const HEIGHT = 440;
/** 紙の色。消しゴムはこの色で描く（出来上がりは透過を持たない WebP） */
const PAPER = "#ffffff";
/** 拡大しても粗くならない範囲。上げすぎると重くなるだけ */
const MAX_DPR = 2;

/**
 * 出せる色。**紙の上で読める色だけ**を並べる — 選べるものを絞ること
 * そのものが道具の言い分で、「何色でもどうぞ」は言い分が無いのと同じ。
 * 先頭が既定。
 */
const PALETTE = ["#111111", "#d92d20", "#1570ef", "#0f9d58", "#e07000"] as const;

/**
 * 太さは細・中・太の 3 段。**その段が何 px になるかはインクが決める** —
 * 消しゴムはペンと同じ太さでは細すぎて使えない。掛け算を隠さず表で持ち、
 * ボタンの点も選んだインクに合わせて太る（見えている点が、出てくる太さ）。
 */
const PEN_NIBS = [2, 4, 8] as const;
const ERASER_NIBS = [8, 16, 24] as const;
/** 既定は真ん中 */
const DEFAULT_STEP = 1;

/**
 * 描くもの。**消しゴムは紙の色のインク**でしかない（下の `pointerdown` は
 * 実際、色と太さを差し替えているだけ）。同じ並びの中に置けば「消しながら
 * 色を選ぶ」のような、意味の無い組み合わせが最初から作れない — 別の
 * 切り替えとして持つと、そこは自分で塞ぐことになる。
 */
type Ink = { kind: "pen"; color: string } | { kind: "eraser" };

const nibsOf = (ink: Ink): readonly number[] =>
  ink.kind === "eraser" ? ERASER_NIBS : PEN_NIBS;

function button(label: string): HTMLButtonElement {
  const b = document.createElement("button");
  b.type = "button";
  b.textContent = label;
  return b;
}

/**
 * 小さな集合から 1 つだけ選ぶ並び。**インクも太さも同じ形**なので器は 1 つ。
 * 選ばれているものに `on` が付き、選び直せば前の印は外れる。
 */
function picker<T>(
  values: readonly T[],
  face: (value: T) => HTMLButtonElement,
  chosen: number,
  onPick: (value: T, index: number) => void,
): HTMLButtonElement[] {
  const buttons = values.map((value, i) => {
    const b = face(value);
    b.classList.toggle("on", i === chosen);
    b.addEventListener("click", () => {
      for (const other of buttons) other.classList.remove("on");
      b.classList.add("on");
      onPick(value, i);
    });
    return b;
  });
  return buttons;
}

/**
 * インク 1 つぶんの見た目。**どれも同じ大きさの丸** — 消しゴムは色を持てない
 * ので、中に絵を入れる（紙の色で塗った丸は、明るいテーマで器と同じ色になって
 * 消える）。
 */
function inkFace(value: Ink): HTMLButtonElement {
  const b = document.createElement("button");
  b.type = "button";
  if (value.kind === "eraser") {
    b.className = "ink eraser";
    b.title = "Eraser";
    b.setAttribute("aria-label", "Eraser");
    b.append(icon("eraser"));
    return b;
  }
  b.className = "ink";
  // 色そのものは道具の持ち物。CSS には形だけを置く
  b.style.setProperty("--swatch", value.color);
  b.title = value.color;
  b.setAttribute("aria-label", `Color ${value.color}`);
  return b;
}

/**
 * 太さ 1 つぶんの見た目。**その太さの点そのもの**を出す
 * （字で "2px" と書くより、出てくる線の太さが直に分かる）。
 * 実際の大きさは選んでいるインクで変わるので、`--nib` は後から入れる。
 */
function nibFace(): HTMLButtonElement {
  const b = document.createElement("button");
  b.type = "button";
  b.className = "nib";
  return b;
}

/** 描く道具と紙。`.draw` の中身そのもので、窓（`showDrawing`）はこれを載せる */
export interface Board {
  el: HTMLDivElement;
  /** 最後の一手を戻す（Mod+Z） */
  undo: () => void;
  /** いまの絵。WebP が作れない環境では PNG へ落ちる（type が空になる） */
  picture: () => Promise<Blob | null>;
}

/**
 * 道具と紙を組む。**置くのは呼ぶ側** — アプリは窓に載せ、並べて見る道具は
 * そのまま置く。
 */
export function drawBoard(): Board {
  const body = document.createElement("div");
  body.className = "draw";

  // ---- 道具立て ----
  //
  // 並びは 3 つの塊 — **何で描くか**（インク）と**どのくらいで**（太さ）を
  // 左に置き、**やり直すもの**（Undo / Clear）だけを右へ離す。描くために
  // 選ぶものと、描いたものを取り消すものは種類が違う。
  //
  // 筆の並びは**窓を開くたびに組む** — アクセントカラーはその間に変わりうる。
  // アクセントカラーも 1 本の筆にする（綴りは持たず、ロゴと同じ `--accent` を
  // 読む。読めなければその筆を出さない）。並びの**末尾**に置くのは、既定に
  // すると淡いアクセントカラーのときに紙の上で消えるため — 選べば使えるが、
  // 黙って選ばれてはいない
  const brush = accent();
  const palette = brush === null ? PALETTE : [...PALETTE, brush];
  const inkList: readonly Ink[] = [
    ...palette.map((color): Ink => ({ kind: "pen", color })),
    { kind: "eraser" },
  ];

  let ink: Ink = inkList[0];
  let step = DEFAULT_STEP;

  const bar = document.createElement("div");
  bar.className = "tools";

  const nibButtons = picker(PEN_NIBS, nibFace, DEFAULT_STEP, (_, i) => {
    step = i;
  });
  /** ボタンの点を、いま選んでいるインクの太さに合わせる */
  const syncNibs = (): void => {
    const table = nibsOf(ink);
    nibButtons.forEach((b, i) => {
      b.style.setProperty("--nib", `${table[i]}px`);
      b.title = `${table[i]}px`;
      b.setAttribute("aria-label", `${table[i]}px`);
    });
  };

  const inks = document.createElement("div");
  inks.className = "inks";
  inks.append(
    ...picker(inkList, inkFace, 0, (value) => {
      ink = value;
      syncNibs();
    }),
  );

  const nibs = document.createElement("div");
  nibs.className = "nibs";
  nibs.append(...nibButtons);
  syncNibs();

  const undo = button("Undo");
  undo.title = "Mod+Z";
  const clear = button("Clear");
  const actions = document.createElement("div");
  actions.className = "group";
  actions.append(undo, clear);

  bar.append(inks, nibs, actions);

  // ---- 紙 ----
  const dpr = Math.min(window.devicePixelRatio || 1, MAX_DPR);
  const canvas = document.createElement("canvas");
  canvas.className = "paper";
  canvas.width = WIDTH * dpr;
  canvas.height = HEIGHT * dpr;
  // 絵の比は常に WIDTH:HEIGHT（画素は dpr 倍）。表示だけは窓に入る大きさまで縮む
  // （CSS の max-width。高さは canvas 自身の比から決まる）
  canvas.style.width = `${WIDTH}px`;
  const ctx = canvas.getContext("2d");
  if (!ctx) throw new Error("お絵描きの 2d コンテキストを作れない");
  ctx.scale(dpr, dpr);
  ctx.lineCap = "round";
  ctx.lineJoin = "round";

  const strokes: Stroke[] = [];

  /** 1 手ぶんを紙に載せる */
  const paint = (s: Stroke): void => {
    if (s.kind === "clear") {
      ctx.fillStyle = PAPER;
      ctx.fillRect(0, 0, WIDTH, HEIGHT);
      return;
    }
    ctx.strokeStyle = s.color;
    ctx.lineWidth = s.width;
    ctx.beginPath();
    // 1 点だけの手（点を打っただけ）も見えるように、同じ点へ引く
    const [head, ...rest] = s.points;
    ctx.moveTo(head.x, head.y);
    if (rest.length === 0) ctx.lineTo(head.x, head.y);
    for (const p of rest) ctx.lineTo(p.x, p.y);
    ctx.stroke();
  };

  /** 並びの通りに引き直す（取り消しと、消しゴムの後始末） */
  const repaint = (): void => {
    ctx.fillStyle = PAPER;
    ctx.fillRect(0, 0, WIDTH, HEIGHT);
    for (const s of strokes) paint(s);
  };
  repaint();

  // ---- 描く ----
  let drawing: Extract<Stroke, { kind: "line" }> | null = null;
  /** 画面の点を紙の座標へ。**表示が縮んでいても紙の上では同じ場所**に
   *  描けるよう、実際に表示されている大きさで割り戻す */
  const at = (e: PointerEvent): Pt => {
    const r = canvas.getBoundingClientRect();
    return {
      x: ((e.clientX - r.left) * WIDTH) / r.width,
      y: ((e.clientY - r.top) * HEIGHT) / r.height,
    };
  };
  canvas.addEventListener("pointerdown", (e) => {
    // 押した瞬間にフォーカスが body へ逃げると Esc / Mod+Enter が死ぬ
    e.preventDefault();
    canvas.setPointerCapture(e.pointerId);
    drawing = {
      kind: "line",
      points: [at(e)],
      color: ink.kind === "eraser" ? PAPER : ink.color,
      width: nibsOf(ink)[step],
    };
    strokes.push(drawing);
    paint(drawing);
  });
  canvas.addEventListener("pointermove", (e) => {
    if (!drawing) return;
    const p = at(e);
    // 引き足すのは最後の一区間だけ。全部引き直すのは取り消しのときでよい
    const last = drawing.points[drawing.points.length - 1];
    drawing.points.push(p);
    ctx.strokeStyle = drawing.color;
    ctx.lineWidth = drawing.width;
    ctx.beginPath();
    ctx.moveTo(last.x, last.y);
    ctx.lineTo(p.x, p.y);
    ctx.stroke();
  });
  const stop = (): void => {
    drawing = null;
  };
  canvas.addEventListener("pointerup", stop);
  canvas.addEventListener("pointercancel", stop);

  // ---- やり直す ----
  const undoOne = (): void => {
    if (strokes.length === 0) return;
    strokes.pop();
    repaint();
  };
  undo.addEventListener("click", undoOne);
  clear.addEventListener("click", () => {
    // クリアも手のひとつ。取り消しで戻せる
    strokes.push({ kind: "clear" });
    repaint();
  });

  body.append(bar, canvas);
  return {
    el: body,
    undo: undoOne,
    picture: () => new Promise((resolve) => canvas.toBlob(resolve, "image/webp", 0.92)),
  };
}

/** 窓に載せる form。題・道具と紙・足元のボタン。`insert` には絵の約束を渡す */
export function drawForm(on: { cancel(): void; insert(picture: Promise<Blob | null>): void }): {
  form: HTMLFormElement;
  undo(): void;
  insert(): void;
} {
  const form = document.createElement("form");
  form.method = "dialog";
  const title = document.createElement("p");
  title.className = "title";
  title.textContent = "Draw";
  const note = document.createElement("p");
  note.className = "note";
  note.textContent = "Mod+Enter to insert, Esc to discard";
  const board = drawBoard();

  // 断りは左、進むは右（たずねと同じ並び）。進む側だけが色を持つ
  const row = document.createElement("div");
  row.className = "row";
  const cancel = button("Cancel");
  const go = button("Insert");
  go.className = "go";
  row.append(cancel, go);
  const insert = (): void => on.insert(board.picture());
  cancel.addEventListener("click", () => on.cancel());
  go.addEventListener("click", insert);

  form.append(title, note, board.el, row);
  return { form, undo: board.undo, insert };
}

/**
 * 描いてもらって、その絵を返す。キャンセルなら null。
 *
 * 確定は `Mod+Enter` か確定ボタン、破棄は `Esc` かキャンセルボタン。
 * **マップの入力欄と違って破棄がある** — あちらは既に文書に在るものを直す
 * ので「確定のみ」でよいが、こちらは確定するまで文書に何も無く、
 * 引き返せないと逃げ場が無い。
 */
export function showDrawing(): Promise<Blob | null> {
  return new Promise((resolve) => {
    // 器はたずね（app/ask.ts）と同じ `<dialog class="ask">`。焦点の閉じ込め・
    // Esc・後ろの幕はブラウザが持つので、ここでは書かない
    const dlg = document.createElement("dialog");
    dlg.className = "ask";
    // 閉じ方は `<dialog>` の 1 つ — Esc も Cancel も `close()` で、進んだとき
    // だけ `"ok"` を添える。絵を待つ間に Esc を押されても close は
    // 1 度しか起きないので、二重に返らない
    let picture: Blob | null = null;
    const { form, undo, insert } = drawForm({
      cancel: () => dlg.close(),
      insert: (p) =>
        void p.then((blob) => {
          picture = blob;
          dlg.close("ok");
        }),
    });
    // Esc は dialog が持つ。全体のショートカット（app/shortcuts.ts）は窓の中では
    // 黙るので、ここで拾うのは窓だけのキー
    dlg.addEventListener("keydown", (e) => {
      if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) {
        e.preventDefault();
        insert();
      } else if ((e.key === "z" || e.key === "Z") && (e.ctrlKey || e.metaKey)) {
        e.preventDefault();
        undo();
      }
    });
    dlg.addEventListener("close", () => {
      dlg.remove();
      resolve(dlg.returnValue === "ok" ? picture : null);
    });
    dlg.append(form);
    document.body.append(dlg);
    dlg.showModal();
  });
}
