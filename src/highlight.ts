// コードカードの色付け。
//
// 自前の字句解析は持たない。CodeMirror の言語一覧（@codemirror/language-data、
// 143 言語）をそのまま借りる。各言語は動的 import なので、**実際に文書に出て
// きた言語だけ**が後から読み込まれる — 最初のバンドルには入らない。
//
// 読み込みは非同期なので、初回は色の付かない状態で出し、読み終わったら
// 描き直す。画像の読み込み（app/disk/images.mbt）と同じ手口。

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
 * 開きフェンスの行を読む。**対象は文書ではなく入力欄の中身**（コードカードを
 * その場で直しているときのバッファ）なので、コアには聞けない — 打っている
 * 途中の断片であって、まだ文書ではないため。規則だけはコア
 * の読み（mizchi/markdown のフェンス）と同じにしてある: 行頭の空白は 3 つまで、
 * フェンスは 3 本以上、バッククォートなら情報文字列にバッククォートを含めない。
 */
function fenceOpen(line: string): { marker: string; info: string } | null {
  const m = /^ {0,3}(`{3,}|~{3,})(.*)$/.exec(line);
  if (!m) return null;
  if (m[1][0] === "`" && m[2].includes("`")) return null;
  return { marker: m[1], info: m[2].trim() };
}

/** その行が `marker` を閉じるか（同じ文字で同じ長さ以上、後ろは空白だけ）。 */
function closesFence(line: string, marker: string): boolean {
  const tail = line.trim();
  return tail.length >= marker.length && [...tail].every((c) => c === marker[0]);
}

/**
 * フェンスごと（```lang … ```）の色付け。編集欄は開き・閉じも含めて扱うので、
 * 囲いの行はそのまま地の文にし、中身だけを言語で読む。
 * フェンスの体を成していなければ、全部地の文にする。
 */
export function tokenizeBlock(text: string): Token[][] {
  const lines = text.split("\n");
  const plain = (t: string): Token[] => [{ text: t, cls: "" }];
  const open = fenceOpen(lines[0] ?? "");
  if (!open || lines.length < 2) return lines.map(plain);
  const last = lines.length - 1;
  const closed = closesFence(lines[last], open.marker);
  const body = lines.slice(1, closed ? last : lines.length);
  const inner = body.length > 0 ? tokenize(body, open.info) : [];
  return [plain(lines[0]), ...inner, ...(closed ? [plain(lines[last])] : [])];
}
