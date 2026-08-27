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
// くる。紙の上で読める 5 色と、3 段の太さだけを出す。

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
/** 消しゴムは同じ太さでは細すぎて使えない */
const ERASER_SCALE = 4;

/**
 * 出せるインク。**紙の上で読める色だけ**を並べる — 選べるものを絞ること
 * そのものが道具の言い分で、「何色でもどうぞ」は言い分が無いのと同じ。
 * 先頭が既定。
 */
const PALETTE = ["#111111", "#d92d20", "#1570ef", "#0f9d58", "#e07000"] as const;

/** 線の太さ。細・中・太の 3 段だけ */
const WIDTHS = [2, 4, 8] as const;
/** 既定は真ん中 */
const DEFAULT_NIB = 1;

/**
 * 描くもの。**消しゴムは紙の色の 6 番目のインク**でしかない（下の
 * `pointerdown` は実際、色と太さを差し替えているだけ）。同じ並びの中に
 * 置けば「消しながら色を選ぶ」のような、意味の無い組み合わせが最初から
 * 作れない — 別の切り替えとして持つと、そこは自分で塞ぐことになる。
 */
type Ink = { kind: "pen"; color: string } | { kind: "eraser" };

const INKS: readonly Ink[] = [
  ...PALETTE.map((color): Ink => ({ kind: "pen", color })),
  { kind: "eraser" },
];

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
  onPick: (value: T) => void,
): HTMLButtonElement[] {
  const buttons = values.map((value, i) => {
    const b = face(value);
    b.classList.toggle("on", i === chosen);
    b.addEventListener("click", () => {
      for (const other of buttons) other.classList.remove("on");
      b.classList.add("on");
      onPick(value);
    });
    return b;
  });
  return buttons;
}

/**
 * インク 1 つぶんの見た目。色は丸、**消しゴムだけは字** — 紙の色の丸は
 * 明るいテーマで器と同じ色になり、消えてしまう。
 */
function inkFace(value: Ink): HTMLButtonElement {
  if (value.kind === "eraser") {
    const b = button("Eraser");
    b.className = "draw-eraser";
    return b;
  }
  const b = document.createElement("button");
  b.type = "button";
  b.className = "draw-ink";
  // 色そのものは道具の持ち物。CSS には形だけを置く
  b.style.setProperty("--ink-swatch", value.color);
  b.title = value.color;
  return b;
}

/**
 * 太さ 1 つぶんの見た目。**その太さの点そのもの**を出す
 * （字で "2px" と書くより、出てくる線の太さが直に分かる）。
 */
function nibFace(value: number): HTMLButtonElement {
  const b = document.createElement("button");
  b.type = "button";
  b.className = "draw-nib";
  b.style.setProperty("--nib", `${value}px`);
  b.title = `${value}px`;
  return b;
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
    const overlay = document.createElement("div");
    overlay.className = "popup-overlay";
    // Esc / Mod+Enter は overlay の keydown で拾う。フォーカスが外へ逃げると
    // 二度と拾えなくなるので、overlay 自身をフォーカス可能にしておく
    overlay.tabIndex = -1;

    const panel = document.createElement("div");
    panel.className = "popup";
    const title = document.createElement("div");
    title.className = "popup-title";
    title.textContent = "Draw";

    // ---- 道具立て ----
    //
    // 並びは 3 つの塊 — **何で描くか**（インク）と**どのくらいで**（太さ）を
    // 左に置き、**やり直すもの**（Undo / Clear）だけを右へ離す。描くために
    // 選ぶものと、描いたものを取り消すものは種類が違う。
    let ink: Ink = INKS[0];
    let nib: number = WIDTHS[DEFAULT_NIB];

    const bar = document.createElement("div");
    bar.className = "draw-tools";

    const inks = document.createElement("div");
    inks.className = "draw-inks";
    inks.append(
      ...picker(INKS, inkFace, 0, (value) => {
        ink = value;
      }),
    );

    const nibs = document.createElement("div");
    nibs.className = "draw-nibs";
    nibs.append(
      ...picker(WIDTHS, nibFace, DEFAULT_NIB, (value) => {
        nib = value;
      }),
    );

    const undo = button("Undo");
    undo.title = "Mod+Z";
    const clear = button("Clear");
    const actions = document.createElement("div");
    actions.className = "group draw-actions";
    actions.append(undo, clear);

    bar.append(inks, nibs, actions);

    // ---- 紙 ----
    const dpr = Math.min(window.devicePixelRatio || 1, MAX_DPR);
    const canvas = document.createElement("canvas");
    canvas.className = "draw-paper";
    canvas.width = WIDTH * dpr;
    canvas.height = HEIGHT * dpr;
    // 出来上がる絵は常に WIDTH×HEIGHT。表示だけは窓に入る大きさまで縮む
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
        width: ink.kind === "eraser" ? nib * ERASER_SCALE : nib,
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

    // ---- 確定 / 破棄 ----
    const foot = document.createElement("div");
    foot.className = "popup-foot";
    const hint = document.createElement("span");
    hint.className = "popup-hint";
    hint.textContent = "Mod+Enter to insert / Esc to discard";
    const btnCancel = button("Cancel");
    const btnOk = button("Insert");
    btnOk.className = "primary";
    foot.append(hint, btnCancel, btnOk);

    let done = false;
    const close = (blob: Blob | null): void => {
      if (done) return; // toBlob を待つ間に Esc を押されても二重に閉じない
      done = true;
      overlay.remove();
      resolve(blob);
    };
    const commit = (): void => {
      // WebP が作れない環境では PNG へ落ちる（type が空になる）
      canvas.toBlob((blob) => close(blob), "image/webp", 0.92);
    };
    btnCancel.addEventListener("click", () => close(null));
    btnOk.addEventListener("click", commit);
    overlay.addEventListener("keydown", (e) => {
      e.stopPropagation(); // マップと全体のショートカットへ流さない
      if (e.key === "Escape") {
        e.preventDefault();
        close(null);
      } else if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) {
        e.preventDefault();
        commit();
      } else if ((e.key === "z" || e.key === "Z") && (e.ctrlKey || e.metaKey)) {
        e.preventDefault();
        undoOne();
      }
    });

    panel.append(title, bar, canvas, foot);
    overlay.append(panel);
    document.body.append(overlay);
    overlay.focus();
  });
}
