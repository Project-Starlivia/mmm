// コードカードの色付け。
//
// 自前の字句解析は持たない。CodeMirror の言語一覧（@codemirror/language-data、
// 143 言語）をそのまま借りる。各言語は動的 import なので、**実際に文書に出て
// きた言語だけ**が後から読み込まれる — 最初のバンドルには入らない。
//
// 読み込みは非同期なので、初回は色の付かない状態で出し、読み終わったら
// 描き直す。画像の読み込み（app/assets.ts）と同じ手口。

import { classHighlighter, highlightCode } from "@lezer/highlight";
import { LanguageDescription, type Language } from "@codemirror/language";
import { languages } from "@codemirror/language-data";

/** 1 つぶんの塊。`cls` が空なら色の付かない地の文。 */
export interface Token {
  text: string;
  cls: string;
}

/** 言語一覧。MD ペインのフェンスにも同じものを渡す（表を 2 つ持たない）。 */
export { languages };

/** 名前 → 読み込み済みの言語。null は「この名前に当たる言語は無い / 失敗」。 */
const ready = new Map<string, Language | null>();
let epoch = 0;
let onReady: (() => void) | null = null;

/**
 * 言語が読み終わったときに呼ばれる。描き直しを繋ぐために使う。
 * 読み込みは非同期なので、これが無いと最初に出た色なしのままになる。
 */
export function onLanguageReady(fn: () => void): void {
  onReady = fn;
}

/**
 * 読み込みの世代。カードの署名に混ぜて、言語が増えたときに
 * コードカードを作り直させる（署名が同じだと中身が据え置かれる）。
 */
export function languageEpoch(): number {
  return epoch;
}

/**
 * フェンスの情報文字列から言語名を取る。`js copy` のように後ろに語が続く
 * 書き方（GitHub などの行番号・コピー指定）があるので、最初の語だけ見る。
 */
function nameOf(info: string): string {
  return info.trim().split(/[\s,]+/)[0]?.toLowerCase() ?? "";
}

/** 読み込み済みならその言語。まだなら null を返しつつ、裏で読み込む。 */
function languageFor(info: string): Language | null {
  const name = nameOf(info);
  if (name === "") return null;
  const hit = ready.get(name);
  if (hit !== undefined) return hit;
  // 読み込み中も「まだ無い」として扱う。二重に読みにいかせない印でもある
  ready.set(name, null);
  const desc = LanguageDescription.matchLanguageName(languages, name, true);
  if (!desc) return null;
  void desc
    .load()
    .then((support) => {
      ready.set(name, support.language);
      epoch++;
      onReady?.();
    })
    .catch(() => {
      /* 読めなければ色を付けないだけ */
    });
  return null;
}

/**
 * 行ごとの塊に分ける。複数行にまたがる文字列やコメントを正しく読むため、
 * 行を繋いだ全体を一度に解析してから行へ割り直す。
 */
export function tokenize(lines: string[], info: string): Token[][] {
  const plain = (): Token[][] => lines.map((text) => [{ text, cls: "" }]);
  const language = languageFor(info);
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
 * フェンスごと（```lang … ```）の色付け。編集欄は開き・閉じも含めて扱うので、
 * 囲いの行はそのまま地の文にし、中身だけを言語で読む。
 * フェンスの体を成していなければ、全部地の文にする。
 */
export function tokenizeBlock(text: string): Token[][] {
  const lines = text.split("\n");
  const open = /^\s*(`{3,}|~{3,})\s*(\S*)\s*$/.exec(lines[0] ?? "");
  if (!open || lines.length < 2) return lines.map((t) => [{ text: t, cls: "" }]);
  // 閉じは開きと同じ文字で同じ長さ以上（CommonMark）。正規表現を組み立てず
  // 数えるだけにする — 記号を含む式は読みにくく、壊れても気づきにくい
  const marker = open[1][0];
  const last = lines.length - 1;
  const tail = lines[last].trim();
  const closed =
    tail.length >= open[1].length &&
    [...tail].every((c) => c === marker);
  const body = lines.slice(1, closed ? last : lines.length);
  const inner = body.length > 0 ? tokenize(body, open[2]) : [];
  const plain = (t: string): Token[] => [{ text: t, cls: "" }];
  return [
    plain(lines[0]),
    ...inner,
    ...(closed ? [plain(lines[last])] : []),
  ];
}

/**
 * 囲いそのもの（開き・閉じのバッククォート）が動く編集か。
 * **言語名は守らない** — そこはフェンスの一部だが、直せることが
 * その場で編集する理由の半分なので、意図して開けてある。
 */
export function touchesFence(text: string, from: number, to: number): boolean {
  const lines = text.split("\n");
  const open = /^(`{3,}|~{3,})/.exec(lines[0] ?? "");
  if (!open) return false;
  const marker = open[1][0];
  const spans: [number, number][] = [[0, open[1].length]];
  if (lines.length > 1) {
    const tail = lines[lines.length - 1];
    const trimmed = tail.trim();
    if (
      trimmed.length >= open[1].length &&
      [...trimmed].every((c) => c === marker)
    ) {
      // 手前の改行ごと守る（消されると閉じが前の行にくっつく）
      spans.push([text.length - tail.length - 1, text.length]);
    }
  }
  return spans.some(([a, b]) =>
    from === to ? a <= from && from < b : from < b && to > a,
  );
}
