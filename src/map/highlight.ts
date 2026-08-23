// コードカードの色付け。
//
// 自前の字句解析は持たない。CodeMirror が MD ペインのフェンス用に既に
// 積んでいるパーサ（js / ts / css / html）をそのまま借りる — 同じ文書の
// 同じコードを 2 通りの規則で読むと、色が食い違ったときに理由が説明できない。
//
// 知らない言語は色を付けない（推測で間違った色を出すより、付けないほうがよい）。

import { classHighlighter, highlightCode } from "@lezer/highlight";
import {
  javascriptLanguage,
  jsxLanguage,
  tsxLanguage,
  typescriptLanguage,
} from "@codemirror/lang-javascript";
import { cssLanguage } from "@codemirror/lang-css";
import { htmlLanguage } from "@codemirror/lang-html";
import type { LRLanguage } from "@codemirror/language";

/** 1 つぶんの塊。`cls` が空なら色の付かない地の文。 */
export interface Token {
  text: string;
  cls: string;
}

const LANGUAGES: Record<string, LRLanguage> = {
  js: javascriptLanguage,
  javascript: javascriptLanguage,
  mjs: javascriptLanguage,
  cjs: javascriptLanguage,
  json: javascriptLanguage,
  jsx: jsxLanguage,
  ts: typescriptLanguage,
  typescript: typescriptLanguage,
  tsx: tsxLanguage,
  css: cssLanguage,
  html: htmlLanguage,
  htm: htmlLanguage,
  svg: htmlLanguage,
  xml: htmlLanguage,
};

/**
 * フェンスの情報文字列から言語を取る。`js copy` のように後ろに語が続く
 * 書き方（GitHub などの行番号・コピー指定）があるので、最初の語だけ見る。
 */
export function langOf(info: string): LRLanguage | null {
  const first = info.trim().split(/[\s,]+/)[0]?.toLowerCase() ?? "";
  return LANGUAGES[first] ?? null;
}

/**
 * 行ごとの塊に分ける。複数行にまたがる文字列やコメントを正しく読むため、
 * 行を繋いだ全体を一度に解析してから行へ割り直す。
 */
export function tokenize(lines: string[], info: string): Token[][] {
  const language = langOf(info);
  const plain = (): Token[][] => lines.map((text) => [{ text, cls: "" }]);
  if (!language) return plain();
  try {
    const code = lines.join("\n");
    const out: Token[][] = [[]];
    highlightCode(
      code,
      language.parser.parse(code),
      classHighlighter,
      (text, cls) => out[out.length - 1].push({ text, cls }),
      () => out.push([]),
    );
    // 解析が行数を変えることは無いはずだが、崩れたら地の文へ倒す
    return out.length === lines.length ? out : plain();
  } catch {
    return plain();
  }
}

/**
 * 表示できる幅に合わせて塊を切り詰める。`clipped` は同じ行を素の文字列として
 * 切った結果で、末尾の `…` を含む。塊の側もそこに合わせて短くする。
 */
export function clipTokens(tokens: Token[], clipped: string): Token[] {
  const ellipsis = clipped.endsWith("…");
  const budget = ellipsis ? clipped.length - 1 : clipped.length;
  const out: Token[] = [];
  let used = 0;
  for (const token of tokens) {
    if (used >= budget) break;
    const text = token.text.slice(0, budget - used);
    if (text !== "") out.push({ ...token, text });
    used += text.length;
  }
  if (ellipsis) out.push({ text: "…", cls: "" });
  return out;
}
