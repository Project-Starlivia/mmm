// 落とされたファイルの振り分け。`.md` はその文書を開き、画像はノードの上に
// 落ちたときだけ受け取る — どこに付いたか分からない貼り方はしない。
//
// ここが知っているのは「何が落ちたか」までで、開く / 置くの中身は呼び出し側。

const IMAGE = /\.(png|jpe?g|gif|webp|svg|avif|bmp)$/i;
const MARKDOWN = /\.(md|markdown|txt)$/i;

/** ドロップされたもののうち、ファイルのハンドルとして取れたもの */
async function droppedFiles(data: DataTransfer): Promise<FileSystemFileHandle[]> {
  // 取り出しは**待つ前に全部**始める。最初の await で drop の出来事が終わり、
  // 以後 items は空に見える（2 枚目からが消える）
  const pending: Promise<FileSystemHandle | null>[] = [];
  for (const item of data.items) {
    if (item.kind === "file" && item.getAsFileSystemHandle) pending.push(item.getAsFileSystemHandle());
  }
  // `kind === "file"` では TS は絞り込めない（union ではなく上位型なので）。実物を確かめる
  return (await Promise.all(pending)).filter((h): h is FileSystemFileHandle => h instanceof FileSystemFileHandle);
}

export function initDrop(deps: {
  /** `.md` が落ちた */
  openMarkdown: (file: FileSystemFileHandle) => Promise<void>;
  /** 画像がノードの上に落ちた（ノードの外なら呼ばれない） */
  addImages: (files: FileSystemFileHandle[], node: number) => Promise<void>;
  /** 着地点を予告する。`null` で消す。落ちる先のノード（無ければ null）を返す */
  markDrop: (at: { x: number; y: number } | null) => number | null;
  failed: (msg: string) => void;
}): void {
  // **ドラッグしている間ずっと答えが見えている。** 落ちる先が決まっていれば
  // その行に線を引き、置けないところではブラウザのカーソルがそう言う。
  // 落としてから「ノードの上へ」と言い直す必要がそもそも無くなる。
  //
  // ドラッグ中に読めるのは**種類（MIME）まで**で、名前も中身も `drop` まで
  // 伏せられている。だが絵かどうかはそれで足りる — 絵だけを掴んでいるなら
  // 行き先はノードの上に限られ、外では受けないと言い切れる。
  // 1 つでも絵でないもの（`.md`）が混ざるなら、どこへ落としても開くので受ける。
  window.addEventListener("dragover", (event) => {
    const data = event.dataTransfer;
    const items = [...(data?.items ?? [])].filter((item) => item.kind === "file");
    if (items.length === 0) return;
    const onNode = deps.markDrop({ x: event.clientX, y: event.clientY }) !== null;
    const onlyImages = items.every((item) => item.type.startsWith("image/"));
    if (onlyImages && !onNode) {
      // **受けないと言う。** `preventDefault` を呼ばなければブラウザが既定の
      // 扱いに戻し、カーソルが拒否の形になって drop も来ない
      if (data) data.dropEffect = "none";
      return;
    }
    event.preventDefault(); // これを言わないと drop が来ない
    if (data) data.dropEffect = "copy";
  });

  // 窓から出ていったら予告は消す（戻ってくれば dragover がまた点ける）
  window.addEventListener("dragleave", (event) => {
    if (event.relatedTarget === null) deps.markDrop(null);
  });

  window.addEventListener("drop", (event) => {
    event.preventDefault();
    // 行き先はこの点で決まる。読んでから予告を畳む
    const node = deps.markDrop({ x: event.clientX, y: event.clientY });
    deps.markDrop(null);
    const data = event.dataTransfer;
    if (!data) return;
    void (async () => {
      const files = await droppedFiles(data);
      const md = files.find((f) => MARKDOWN.test(f.name));
      if (md) {
        await deps.openMarkdown(md);
        return;
      }
      const images = files.filter((f) => IMAGE.test(f.name));
      // ノードの外へ落ちた絵は、そもそもここまで来ない（dragover が受けて
      // いない）。来るのは `.md` に混ざって落ちた分だけなので、黙って置かない
      if (images.length === 0 || node === null) return;
      await deps.addImages(images, node);
    })().catch((error) => {
      console.error("drop failed:", error);
      deps.failed("Couldn't open the dropped file");
    });
  });
}
