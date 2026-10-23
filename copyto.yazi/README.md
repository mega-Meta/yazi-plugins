# copyto.yazi

A powerful Yazi plugin to copy or move selected/hovered files to any directory globally using **FZF** with automatic conflict resolution.

## 🚀 Features
- **Global Search**: Search and pick directories starting from your `~/` home directory dynamically.
- **Interactive UI**: Powered by `fzf` and `fd` for ultra-fast, smooth fuzzy-finding.
- **Conflict Resolution**: Beautiful interactive popup menu to choose **Overwrite**, **Rename (auto suffix `_複本`)**, or **Skip** when file conflict happens.
- **Directory Support**: Fully supports transferring individual files, multi-selected files, and whole folders.

## 📋 Prerequisites
Ensure you have `fzf` and `fd` installed on your system.

## 🛠️ Installation

Add the plugin via Yazi's package manager:

```bash
ya pkg add mega-Meta/copyto.yazi
```

## ⚙️ Configuration

Add the following shortcuts to your `~/.config/yazi/keymap.toml`:

```toml
[[manager.keymap]]
on   = [ "c", "t" ]
run  = "plugin copyto --args='copy'"
desc = "FZF 挑選目錄並【複製】檔案or目錄"

[[manager.keymap]]
on   = [ "m", "t" ]
run  = "plugin copyto --args='move'"
desc = "FZF 挑選目錄並【移動】檔案or目錄"
```

## 📄 License
MIT
