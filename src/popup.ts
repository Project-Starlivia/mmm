// Modal popups that append content to a node (mmm.md そのに: コードブロック
// ・画像用のポップアップ). Commit = Mod+Enter (or the button), cancel = Esc.
// Each popup resolves null on cancel; the caller inserts the result into the
// node's attached content.

type Collect<T> = () => T | null;

/** Build a modal shell; `build` fills the body and returns the collector
 * run on commit (returning null keeps the popup open, e.g. empty input). */
function shell<T>(
  title: string,
  build: (body: HTMLDivElement, commit: () => void) => Collect<T>,
  labels?: { ok?: string; cancel?: string; hint?: string },
): Promise<T | null> {
  return new Promise((resolve) => {
    const overlay = document.createElement("div");
    overlay.className = "popup-overlay";
    // Esc / Mod+Enter は overlay の keydown で拾う。フォーカスが外へ逃げると
    // 二度と拾えなくなるので、overlay 自身をフォーカス可能にしておく
    overlay.tabIndex = -1;
    const panel = document.createElement("div");
    panel.className = "popup";
    const head = document.createElement("div");
    head.className = "popup-title";
    head.textContent = title;
    const body = document.createElement("div");
    body.className = "popup-body";
    const foot = document.createElement("div");
    foot.className = "popup-foot";
    const hintEl = document.createElement("span");
    hintEl.className = "popup-hint";
    hintEl.textContent = labels?.hint ?? "Mod+Enter で確定 / Esc でキャンセル";
    const btnCancel = document.createElement("button");
    btnCancel.textContent = labels?.cancel ?? "キャンセル";
    const btnOk = document.createElement("button");
    btnOk.className = "primary";
    btnOk.textContent = labels?.ok ?? "確定";
    foot.append(hintEl, btnCancel, btnOk);
    panel.append(head, body, foot);
    overlay.append(panel);

    const close = (val: T | null): void => {
      overlay.remove();
      resolve(val);
    };
    const commit = (): void => {
      const val = collect();
      if (val !== null) close(val);
    };
    btnCancel.addEventListener("click", () => close(null));
    btnOk.addEventListener("click", commit);
    overlay.addEventListener("keydown", (e) => {
      e.stopPropagation(); // keep map/global shortcuts out
      if (e.key === "Escape") {
        e.preventDefault();
        close(null);
      } else if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) {
        e.preventDefault();
        commit();
      }
    });

    const collect = build(body, commit);
    document.body.append(overlay);
    // build() が入力欄に focus() していなければ、overlay が受け皿になる
    if (!overlay.contains(document.activeElement)) overlay.focus();
  });
}

function field(label: string, el: HTMLElement): HTMLLabelElement {
  const wrap = document.createElement("label");
  wrap.className = "popup-field";
  const span = document.createElement("span");
  span.textContent = label;
  wrap.append(span, el);
  return wrap;
}

// ---------- code ----------

export function showCodePopup(): Promise<{ lang: string; code: string } | null> {
  return shell("コードブロックを追加", (body) => {
    const lang = document.createElement("input");
    lang.type = "text";
    lang.placeholder = "言語 (例: ts, py — 省略可)";
    lang.spellcheck = false;
    const code = document.createElement("textarea");
    code.rows = 12;
    code.spellcheck = false;
    code.placeholder = "コード";
    // Tab inserts two spaces instead of leaving the field
    code.addEventListener("keydown", (e) => {
      if (e.key === "Tab" && !e.ctrlKey && !e.metaKey && !e.altKey) {
        e.preventDefault();
        const s = code.selectionStart;
        code.setRangeText("  ", s, code.selectionEnd, "end");
      }
    });
    body.append(field("言語", lang), field("コード", code));
    queueMicrotask(() => code.focus());
    return () => {
      const text = code.value.replace(/\s+$/, "");
      if (text === "") {
        code.focus();
        return null;
      }
      return { lang: lang.value.trim(), code: text };
    };
  });
}

// ---------- link ----------

export function showLinkPopup(): Promise<{ url: string; title: string } | null> {
  return shell("リンクを追加", (body, commit) => {
    const url = document.createElement("input");
    url.type = "text";
    url.placeholder = "https://…";
    url.spellcheck = false;
    const title = document.createElement("input");
    title.type = "text";
    title.placeholder = "タイトル (省略時はドメイン名)";
    for (const el of [url, title]) {
      el.addEventListener("keydown", (e) => {
        if (e.key === "Enter" && !e.ctrlKey && !e.metaKey) {
          e.preventDefault();
          commit();
        }
      });
    }
    body.append(field("URL", url), field("タイトル", title));
    queueMicrotask(() => url.focus());
    return () => {
      let u = url.value.trim();
      if (u === "") {
        url.focus();
        return null;
      }
      if (!/^https?:\/\//i.test(u)) u = `https://${u}`;
      try {
        new URL(u);
      } catch {
        url.focus();
        url.select();
        return null;
      }
      return { url: u, title: title.value.trim() };
    };
  });
}

// ---------- 一行入力（window.prompt の代替） ----------

/**
 * 一行のテキスト入力。`window.prompt` は Tauri の WebView で効かない
 * （ダイアログを出さず既定値を返す）ので、その置き換え。
 * Enter / Mod+Enter / 確定ボタンで確定、Esc / キャンセルで null。
 *
 * `opts.suffix` は入力欄の右に添える固定文字（拡張子など）。`opts.selectFrom`
 * は初期選択の開始位置（先頭の `./` を残して名前だけ選ぶ、など）。
 */
export function showPromptPopup(
  title: string,
  label: string,
  value: string,
  opts?: { suffix?: string; selectFrom?: number },
): Promise<string | null> {
  return shell<string>(title, (body, commit) => {
    const input = document.createElement("input");
    input.type = "text";
    input.value = value;
    input.spellcheck = false;
    input.addEventListener("keydown", (e) => {
      if (e.key === "Enter" && !e.ctrlKey && !e.metaKey) {
        e.preventDefault();
        commit();
      }
    });

    // suffix があれば入力欄の右に固定文字を添える（`[./name] .webp`）
    let control: HTMLElement = input;
    if (opts?.suffix) {
      const row = document.createElement("div");
      row.className = "popup-suffixed";
      const suf = document.createElement("span");
      suf.className = "popup-suffix";
      suf.textContent = opts.suffix;
      row.append(input, suf);
      control = row;
    }
    body.append(field(label, control));

    queueMicrotask(() => {
      input.focus();
      input.setSelectionRange(opts?.selectFrom ?? 0, input.value.length);
    });
    return () => {
      if (input.value.trim() === "") {
        input.focus();
        return null; // 空は確定させず開いたまま
      }
      return input.value;
    };
  });
}

// ---------- drawing ----------

const DRAW_W = 720;
const DRAW_H = 440;
const PAPER = "#ffffff"; // キャンバスの紙色（消しゴムの色でもある）

export function showDrawPopup(): Promise<Blob | null> {
  return shell<Blob>("お絵描き", (body) => {
    const bar = document.createElement("div");
    bar.className = "popup-toolbar";
    const color = document.createElement("input");
    color.type = "color";
    color.value = "#111111";
    const width = document.createElement("input");
    width.type = "range";
    width.min = "1";
    width.max = "16";
    width.value = "3";
    const eraser = document.createElement("button");
    eraser.textContent = "消しゴム";
    const clear = document.createElement("button");
    clear.textContent = "クリア";
    bar.append(color, width, eraser, clear);

    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    const canvas = document.createElement("canvas");
    canvas.className = "popup-canvas";
    canvas.width = DRAW_W * dpr;
    canvas.height = DRAW_H * dpr;
    canvas.style.width = `${DRAW_W}px`;
    canvas.style.height = `${DRAW_H}px`;
    const ctx = canvas.getContext("2d")!;
    ctx.scale(dpr, dpr);
    ctx.fillStyle = PAPER;
    ctx.fillRect(0, 0, DRAW_W, DRAW_H);
    ctx.lineCap = "round";
    ctx.lineJoin = "round";

    let erasing = false;
    eraser.addEventListener("click", () => {
      erasing = !erasing;
      eraser.classList.toggle("primary", erasing);
    });
    clear.addEventListener("click", () => {
      ctx.fillStyle = PAPER;
      ctx.fillRect(0, 0, DRAW_W, DRAW_H);
    });

    let last: { x: number; y: number } | null = null;
    const pos = (e: PointerEvent): { x: number; y: number } => {
      const r = canvas.getBoundingClientRect();
      return { x: e.clientX - r.left, y: e.clientY - r.top };
    };
    canvas.addEventListener("pointerdown", (e) => {
      // クリックでフォーカスが body に逃げると Esc / Mod+Enter が死ぬ
      e.preventDefault();
      canvas.setPointerCapture(e.pointerId);
      last = pos(e);
    });
    canvas.addEventListener("pointermove", (e) => {
      if (!last) return;
      const p = pos(e);
      ctx.strokeStyle = erasing ? PAPER : color.value;
      ctx.lineWidth = erasing ? Number(width.value) * 4 : Number(width.value);
      ctx.beginPath();
      ctx.moveTo(last.x, last.y);
      ctx.lineTo(p.x, p.y);
      ctx.stroke();
      last = p;
    });
    const stop = (): void => {
      last = null;
    };
    canvas.addEventListener("pointerup", stop);
    canvas.addEventListener("pointercancel", stop);

    body.append(bar, canvas);
    // toBlob is async but collect must be sync: use a data URL instead
    // (the canvas is small; this is fine)
    return () => {
      let dataUrl = canvas.toDataURL("image/webp", 0.92);
      if (!dataUrl.startsWith("data:image/webp")) {
        dataUrl = canvas.toDataURL("image/png");
      }
      const [meta, b64] = dataUrl.split(",");
      const mime = /data:([^;]+)/.exec(meta)?.[1] ?? "image/png";
      const bin = atob(b64);
      const bytes = new Uint8Array(bin.length);
      for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
      return new Blob([bytes], { type: mime });
    };
  });
}
