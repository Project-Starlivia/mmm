// 落とされたファイルの振り分け。`.md` はその文書を開き、画像はノードの上に
// 落ちたときだけ受け取る — どこに付いたか分からない貼り方はしない。
//
// ここが知っているのは「何が落ちたか」までで、開く / 置くの中身は呼び出し側。

const IMAGE = /\.(png|jpe?g|gif|webp|svg|avif|bmp)$/i;
const MARKDOWN = /\.(md|markdown|txt)$/i;

/** ドロップされたもののうち、ファイルのハンドルとして取れたもの */
async function droppedFiles(
  data: DataTransfer,
): Promise<FileSystemFileHandle[]> {
  const files: FileSystemFileHandle[] = [];
  for (const item of data.items) {
    if (item.kind !== "file" || !item.getAsFileSystemHandle) continue;
    const handle = await item.getAsFileSystemHandle();
    if (handle?.kind === "file") files.push(handle as FileSystemFileHandle);
  }
  return files;
}

export function initDrop(deps: {
  /** `.md` が落ちた */
  openMarkdown: (file: FileSystemFileHandle) => Promise<void>;
  /** 画像がノードの上に落ちた（ノードの外なら呼ばれない） */
  addImages: (files: FileSystemFileHandle[], node: number) => Promise<void>;
  /** その座標にあるノード（無ければ -1） */
  nodeAt: (clientX: number, clientY: number) => number;
  warn: (msg: string) => void;
}): void {
  window.addEventListener("dragover", (event) => {
    const items = [...(event.dataTransfer?.items ?? [])];
    if (items.some((item) => item.kind === "file")) event.preventDefault();
  });

  window.addEventListener("drop", (event) => {
    event.preventDefault();
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
      if (images.length === 0) return;
      const node = deps.nodeAt(event.clientX, event.clientY);
      if (node === -1) {
        deps.warn("画像はノードの上に落としてください");
        return;
      }
      await deps.addImages(images, node);
    })().catch((error) => {
      console.error("drop failed:", error);
      deps.warn("ドロップしたファイルを開けませんでした");
    });
  });
}
