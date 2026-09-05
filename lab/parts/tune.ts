// 源と濃さ。style.css の色の源（地・字・強調）と、灰の混ぜ具合（`*-mix`）を
// その場で動かして、一覧ぜんぶに効かせる。出た値は CSS の形で見せるので、
// 決まったら style.css へ写す — **ここは書き戻さない**（源は style.css）。
//
// dark と light は別々の源を持つので、組も 2 つ。書き込み先は `<style>` 1 枚で、
// `:root { … }` と `.light { … }` を丸ごと出し直す。

import type { Theme } from "../../src/app/theme.ts";

/** 源。3 色 */
const COLORS = ["bg", "ink", "accent"] as const;
/** 濃さ。地と字（浮くものは地と `--lift`）の混ぜ具合 */
const MIXES = ["panel", "node-bg", "ink-dim", "line", "node-border", "node-border-strong", "edge", "dot", "ring"] as const;

type Values = { color: Record<(typeof COLORS)[number], string>; mix: Record<(typeof MIXES)[number], number> };

/** いま効いている値を、そのテーマの要素から読む（style.css の宣言そのまま） */
function current(theme: Theme): Values {
  const el = document.createElement("div");
  if (theme === "light") el.className = "light";
  document.body.append(el);
  const cs = getComputedStyle(el);
  const read = (name: string): string => cs.getPropertyValue(name).trim();
  const v: Values = { color: { bg: "", ink: "", accent: "" }, mix: { panel: 0, "node-bg": 0, "ink-dim": 0, line: 0, "node-border": 0, "node-border-strong": 0, edge: 0, dot: 0, ring: 0 } };
  for (const c of COLORS) v.color[c] = read(`--${c}`);
  for (const m of MIXES) v.mix[m] = parseFloat(read(`--${m}-mix`));
  el.remove();
  return v;
}

/** 計算済みの色を hex に。color-mix の結果は `color(srgb r g b)` で返る */
function hex(computed: string): string {
  const m = /color\(srgb ([\d.]+) ([\d.]+) ([\d.]+)/.exec(computed) ?? /rgba?\((\d+), (\d+), (\d+)/.exec(computed);
  if (!m) return computed;
  const unit = computed.startsWith("color(");
  const to = (x: string): string =>
    Math.round(unit ? Number(x) * 255 : Number(x))
      .toString(16)
      .padStart(2, "0");
  return `#${to(m[1] ?? "0")}${to(m[2] ?? "0")}${to(m[3] ?? "0")}`;
}

const css = (theme: Theme, v: Values): string => {
  const lines = [
    ...COLORS.map((c) => `  --${c}: ${v.color[c]};`),
    ...MIXES.map((m) => `  --${m}-mix: ${v.mix[m]}%;`),
  ];
  return `${theme === "light" ? ".light" : ":root"} {\n${lines.join("\n")}\n}`;
};

/** 源と濃さの調整を `host` に組み、動かすたびに一覧へ効かせる */
export function mountTune(host: HTMLElement): void {
  const sheet = document.createElement("style");
  document.head.append(sheet);
  const out = document.createElement("textarea");
  out.readOnly = true;
  out.rows = 14;
  out.style.cssText = "width:100%;font:11px var(--mono);background:var(--bg);color:var(--ink);border:1px solid var(--line);border-radius:6px;padding:8px;box-sizing:border-box";

  const values: Record<Theme, Values> = { dark: current("dark"), light: current("light") };
  /** 出来た色の hex を書き直すもの。効かせた後に全部呼ぶ */
  const shows: (() => void)[] = [];
  const apply = (): void => {
    sheet.textContent = `${css("dark", values.dark)}\n${css("light", values.light)}`;
    out.value = sheet.textContent;
    for (const show of shows) show();
  };

  const group = (theme: Theme): HTMLElement => {
    const box = document.createElement("fieldset");
    // 組そのものをそのテーマの中に置く。見本の色が var() でそのまま出る
    box.className = theme === "light" ? "light" : "";
    box.style.cssText =
      "border:1px solid var(--line);border-radius:6px;padding:8px 12px;min-width:0;flex:1;background:var(--bg);color:var(--ink)";
    const legend = document.createElement("legend");
    legend.textContent = theme;
    legend.style.cssText = "font-size:12px;color:var(--ink-dim);padding:0 4px";
    box.append(legend);
    const v = values[theme];
    /** 1 行。`token` はその行で出来る色（`--panel` など）。見本と hex を右に置く */
    const row = (name: string, input: HTMLInputElement, show: () => string, token: string): void => {
      const line = document.createElement("label");
      line.style.cssText = "display:flex;align-items:center;gap:8px;font-size:12px;margin:4px 0";
      const key = document.createElement("span");
      key.style.cssText = "width:11em;color:var(--ink-dim)";
      key.textContent = name;
      const val = document.createElement("span");
      val.style.cssText = "width:4em;font-family:var(--mono);font-size:11px";
      val.textContent = show();
      const swatch = document.createElement("span");
      swatch.style.cssText = `width:22px;height:16px;border-radius:4px;border:1px solid var(--line);background:var(${token})`;
      const made = document.createElement("span");
      made.style.cssText = "width:5em;font-family:var(--mono);font-size:11px;color:var(--ink-dim)";
      shows.push(() => {
        made.textContent = hex(getComputedStyle(swatch).backgroundColor);
      });
      input.addEventListener("input", () => {
        val.textContent = show();
        apply();
      });
      line.append(key, input, val, swatch, made);
      box.append(line);
    };
    for (const c of COLORS) {
      const input = document.createElement("input");
      input.type = "color";
      input.value = v.color[c];
      input.addEventListener("input", () => {
        v.color[c] = input.value;
      });
      row(c, input, () => v.color[c], `--${c}`);
    }
    for (const m of MIXES) {
      const input = document.createElement("input");
      input.type = "range";
      input.min = "0";
      input.max = "100";
      input.step = "1";
      input.value = String(v.mix[m]);
      input.style.flex = "1";
      input.addEventListener("input", () => {
        v.mix[m] = Number(input.value);
      });
      row(`${m}-mix`, input, () => `${v.mix[m]}%`, `--${m}`);
    }
    return box;
  };

  const groups = document.createElement("div");
  groups.style.cssText = "display:flex;gap:12px;margin-bottom:8px";
  groups.append(group("dark"), group("light"));
  host.append(groups, out);
  apply();
}
