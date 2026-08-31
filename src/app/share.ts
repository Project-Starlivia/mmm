// 本文を URL フラグメントへ載せる／そこから戻す。
//
// クエリではなくフラグメント（`#md=...`）に置く — フラグメントはブラウザから
// 外へ一切出ない。サーバのアクセスログにも、外部リンクを踏んだ先の
// Referer にも本文が漏れない（クエリはどちらにも漏れる）。
//
// 圧縮は `CompressionStream('gzip')`。mmm は元から Chromium 限定と
// 言い切っているので、追加のライブラリは要らない。

const PREFIX = "md=";

/**
 * この長さを超えたら「一部のアプリでは切られるかも」と伝える文字数。
 * 拒否はしない — 相手側の実際の上限は mmm には分からないので、勝手に決めない。
 */
export const LINK_WARN_LENGTH = 8000;

async function pipe(
  bytes: Uint8Array<ArrayBuffer>,
  stream: CompressionStream | DecompressionStream,
): Promise<Uint8Array<ArrayBuffer>> {
  const input = new Blob([bytes]).stream().pipeThrough(stream);
  return new Uint8Array(await new Response(input).arrayBuffer());
}

function toBase64Url(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function fromBase64Url(value: string): Uint8Array<ArrayBuffer> | null {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/");
  const padLen = (4 - (padded.length % 4)) % 4;
  try {
    const bin = atob(padded + "=".repeat(padLen));
    const bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    return bytes;
  } catch {
    return null;
  }
}

/** 本文を載せたフラグメント（`#md=...`）。URL の組み立ては呼び出し側。 */
export async function toHash(text: string): Promise<string> {
  const gzipped = await pipe(new TextEncoder().encode(text), new CompressionStream("gzip"));
  return `#${PREFIX}${toBase64Url(gzipped)}`;
}

/** 画像を貼った行があるか。`![...](...)` — 画像は旅をしないので、
 *  Copy link の行に**押す前の但し書き**として出すのに使う。 */
export function hasImages(text: string): boolean {
  return /!\[[^\]]*\]\([^)]*\)/.test(text);
}

/** `location.hash` から本文を取り出す。リンクでなければ null。 */
export async function fromHash(hash: string): Promise<string | null> {
  if (!hash.startsWith(`#${PREFIX}`)) return null;
  const bytes = fromBase64Url(hash.slice(1 + PREFIX.length));
  if (!bytes) return null;
  try {
    const plain = await pipe(bytes, new DecompressionStream("gzip"));
    return new TextDecoder().decode(plain);
  } catch {
    return null;
  }
}
