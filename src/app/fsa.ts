// File System Access API の、lib.dom に無い分の型。ブラウザ（Chromium）が持っている
// 形をそのまま書く。**実装は無い** — 型を補うだけの module（`export {}`）で、
// tsconfig の include に居るので import しなくても効く。

declare global {
  interface FileSystemHandlePermissionDescriptor {
    mode?: "read" | "readwrite";
  }

  interface FileSystemHandle {
    queryPermission(descriptor?: FileSystemHandlePermissionDescriptor): Promise<PermissionState>;
    requestPermission(descriptor?: FileSystemHandlePermissionDescriptor): Promise<PermissionState>;
    /** 同じフォルダの中での改名。Chromium だけが持つので任意 */
    move?: (name: string) => Promise<void>;
  }

  interface Window {
    showDirectoryPicker?: (options?: { startIn?: FileSystemHandle; mode?: "read" | "readwrite" }) => Promise<FileSystemDirectoryHandle>;
  }

  interface DataTransferItem {
    getAsFileSystemHandle?: () => Promise<FileSystemHandle | null>;
  }
}

export {};
