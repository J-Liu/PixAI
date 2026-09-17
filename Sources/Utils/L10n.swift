// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation
import AppKit

/// Runtime UI localization for PixAI.
///
/// Three languages are supported: English (default), Simplified Chinese, and Traditional Chinese.
/// The active language lives in `AppConfig.uiLanguage` (`~/.pixai/config.json`,
/// key `uiLanguage`), editable from the Preferences window; changing it posts
/// `didChangeNotification` so menus and windows can refresh in place.
///
/// English strings are the dictionary keys (fallback), so only the zh / zh-Hant
/// translations need to be listed here. Unknown keys fall back to the English
/// text itself.
final class L10n {
    static let shared = L10n()

    /// Posted on the main thread when the active language changes.
    static let didChangeNotification = Notification.Name("L10n.didChange")

    private var languageCode: String = "en"
    private let lock = NSLock()

    private init() {
        languageCode = AppConfig.normalizeLanguage(AppConfig.shared.uiLanguage)
        NotificationCenter.default.addObserver(
            forName: AppConfig.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            let new = AppConfig.normalizeLanguage(AppConfig.shared.uiLanguage)
            self.lock.lock()
            let changed = new != self.languageCode
            if changed { self.languageCode = new }
            self.lock.unlock()
            if changed {
                NotificationCenter.default.post(name: L10n.didChangeNotification, object: nil)
            }
        }
    }

    var isChinese: Bool {
        lock.lock(); defer { lock.unlock() }
        return languageCode == "zh" || languageCode == "zh-Hant"
    }

    var isTraditionalChinese: Bool {
        lock.lock(); defer { lock.unlock() }
        return languageCode == "zh-Hant"
    }

    /// Translate an English UI string into the active language.
    func t(_ en: String) -> String {
        lock.lock()
        let code = languageCode
        lock.unlock()
        switch code {
        case "zh":
            return Self.zh[en] ?? en
        case "zh-Hant":
            return Self.zhHant[en] ?? en
        default:
            return en
        }
    }

    /// Translate with C-style %@ format arguments.
    func tf(_ en: String, _ args: CVarArg...) -> String {
        return String(format: t(en), locale: Locale(identifier: "en_US_POSIX"), arguments: args)
    }

    // MARK: - zh translations (English is the key / fallback)

    private static let zh: [String: String] = [
        // ── Menu bar titles ──────────────────────────────────────────
        "File": "文件",
        "Edit": "编辑",
        "View": "显示",
        "Window": "窗口",
        "Help": "帮助",

        // ── PixAI menu ───────────────────────────────────────────────
        "About PixAI": "关于 PixAI",
        "Check for Updates...": "检查更新...",
        "Preferences...": "偏好设置...",
        "Services": "服务",
        "Hide PixAI": "隐藏 PixAI",
        "Hide Others": "隐藏其他",
        "Show All": "全部显示",
        "Quit PixAI": "退出 PixAI",

        // ── File menu ────────────────────────────────────────────────
        "Open...": "打开...",
        "New Window": "新建窗口",
        "Save": "保存",
        "Save As...": "另存为...",
        "Rename...": "重命名...",
        "Delete": "删除",
        "Copy": "拷贝",
        "Paste": "粘贴",
        "Close Window": "关闭窗口",

        // ── View menu ────────────────────────────────────────────────
        "Zoom In": "放大",
        "Zoom Out": "缩小",
        "Fit / 100%": "适应窗口 / 100%",
        "Crop": "裁切",
        "Rotate Clockwise": "顺时针旋转",
        "Rotate Counterclockwise": "逆时针旋转",
        "Play/Pause": "播放/暂停",
        "Start/Stop Slideshow": "开始/停止幻灯片",
        "Enter Full Screen": "进入全屏",
        "Toggle Full Screen": "切换全屏",

        // ── Context menu navigation ──────────────────────────────
        "Previous Image": "上一张",
        "Next Image": "下一张",
        "First Image": "第一张",
        "Last Image": "最后一张",

        // ── AI menu ──────────────────────────────────────────────────
        "AI Super-Resolution": "AI 超分辨率",
        "AI Watermark Removal": "AI 去水印",
        "AI Quality Enhance": "AI 画质增强",
        "One-Click AI Auto-Enhance": "一键 AI 自动增强",

        // ── Window menu ──────────────────────────────────────────────
        "Minimize": "最小化",
        "Zoom": "缩放窗口",
        "Shortcuts": "快捷键",

        // ── Toolbar tooltips ─────────────────────────────────────────
        "Previous image": "上一张图片",
        "Next image": "下一张图片",
        "Rotate clockwise (R)": "顺时针旋转 (R)",
        "Rotate counterclockwise (Cmd+R)": "逆时针旋转 (⌘R)",
        "Zoom in": "放大",
        "Zoom out": "缩小",
        "Fit to window / 100%": "适应窗口 / 100%",
        "Play/Pause (Space)": "播放/暂停 (空格)",
        "AI quality enhance": "AI 画质增强",
        "AI dewatermark": "AI 去水印",
        "AI super-resolution": "AI 超分辨率",
        "One-click AI auto-enhance": "一键 AI 自动增强",
        "Save (overwrite)": "保存（覆盖）",
        "Delete (move to Trash)": "删除（移到废纸篓）",

        // ── Status bar / window messages ─────────────────────────────
        "Open or drag images here": "打开或拖入图片",
        "First image, wrapping to last": "已是第一张，循环到最后一张",
        "Last image, wrapping to first": "已是最后一张，循环到第一张",
        "Shown scaled down (huge image thumbnail)": "已缩放显示（超大图缩略）",
        "scaled": "已缩放",
        "Nothing to save": "没有可保存的更改",
        "Save failed": "保存失败",
        "Save failed: unsupported format": "保存失败：不支持的格式",
        "Saved": "已保存",
        "Saved as %@": "已另存为 %@",
        "Copied": "已复制",
        "Pasted": "已粘贴",
        "Delete Overlay": "删除贴图",
        "Save Changes?": "保存更改？",
        "You have unsaved changes. Do you want to save them?": "您有未保存的更改。是否保存？",
        "Don't Save": "不保存",
        "Save All": "全部保存",
        "Discard All": "全部丢弃",
        "Cancel": "取消",
        "AI upscaling…": "AI 超分中…",
        "AI dewatermarking…": "AI 去水印中…",
        "AI enhance failed": "AI 增强失败",
        "Cannot get image data": "无法获取图像数据",
        "AI upscale failed": "AI 超分失败",
        "AI dewatermark failed": "AI 去水印失败",
        "No watermark detected": "未检测到水印",
        "Real-ESRGAN model not downloaded — see Preferences ▸ AI Models": "Real-ESRGAN 模型未下载 — 请在 偏好设置 ▸ AI 模型 中下载",
        "U2Net model not downloaded — see Preferences ▸ AI Models": "U2Net 模型未下载 — 请在 偏好设置 ▸ AI 模型 中下载",
        "AI one-click enhance complete": "一键 AI 增强完成",
        "AI batch cancelled": "AI 批处理已取消",
        "This operation takes time, please wait": "此操作需要一些时间，请稍候",
        "AI One-Click Enhance": "一键 AI 增强",
        "Run AI dedup and dewatermark on the current image queue? Duplicate files will be moved to the Trash.": "是否在当前图片队列上执行 AI 去重和去水印？重复文件将被移到废纸篓。",
        "Run": "运行",
        "Continue?": "继续？",
        "More duplicate groups remain. Continue deduplicating?": "仍有重复组待处理。是否继续去重？",
        "Yes": "是",
        "No": "否",
        "Delete “%@”?": "删除“%@”？",
        "The file will be moved to the Trash.\nSize: %@": "文件将被移到废纸篓。\n大小：%@",
        "Don't ask again": "不再询问",
        "Moved to Trash": "已移到废纸篓",
        "Large image warning": "大图警告",
        "“%@” is %@, larger than 50 MB. Displaying it may use a lot of memory.": "“%@”为%@，超过 50 MB。显示它可能占用大量内存。",
        "OK": "好",
        "Playback ended": "播放结束",
        "Unsupported format": "不支持的格式",

        // ── Crop ─────────────────────────────────────────────────────
        "Cropping not supported": "不支持裁切",
        "Cropping GIF and animated images is not supported.": "不支持裁切 GIF 和动画图片。",
        "Crop Live Photo?": "裁切 Live Photo？",
        "Cropping converts this Live Photo into a regular still image.": "裁切后该 Live Photo 将变成普通静态图片。",
        "Save the cropped image": "保存裁切后的图片",

        // ── Rename ───────────────────────────────────────────────────
        "Rename image": "重命名图片",
        "Rename": "重命名",
        "Renamed to %@": "已重命名为 %@",
        "Rename failed: %@": "重命名失败：%@",

        // ── Startup model check dialog ───────────────────────────────
        "AI models are missing": "AI 模型缺失",
        "The following AI models are not downloaded (or are corrupted / deleted / moved):": "以下 AI 模型未下载（或已损坏/删除/移动）：",
        "Download now?": "立即下载？",
        "Later": "稍后",

        // ── Preferences window ───────────────────────────────────────
        "Preferences": "偏好设置",
        "General": "常规",
        "Advanced": "高级",
        "Quit app when the last window is closed": "关闭最后一个窗口时退出应用",
        "Ask for confirmation before deleting a file": "删除文件前询问确认",
        "Language": "语言",
        "Image transition duration (0–2 s, 0 = off):": "图片切换动画时长（0–2 秒，0=关闭）：",
        "Ask to download AI models at startup when missing": "启动时若 AI 模型缺失/损坏则询问下载",
        "Auto-play Live Photos when displayed": "显示时自动播放 Live Photo",
        "Mute Live Photo playback": "Live Photo 播放静音",

        // ── Open panel directory ────────────────────────────────────
        "Default directory:": "默认目录：",
        "Last open": "上次打开",
        "Choose...": "选择...",
        "Slideshow": "幻灯片",
        "Interval per slide (1–600 s):": "每张间隔（1–600 秒）：",
        "Slideshow interval (1–600 s):": "幻灯片间隔（1–600 秒）：",
        "Image Cache": "图片缓存",
        "Cached images (1–20):": "缓存图片数（1–20）：",
        "Auto AI super-resolve small images on load": "加载时自动 AI 超分小图",
        "Auto AI dewatermark on load": "加载时自动 AI 去水印",
        "Quality Enhance": "画质增强",
        "Super Resolution": "超分辨率",
        "Remove Watermark": "去水印",
        "One-click Enhance": "一键增强",
        "Enhancement Parameters": "增强参数",
        "Vibrance (0–1):": "饱和度（0–1）：",
        "Contrast (0.5–2.0, 1.0 = off):": "对比度（0.5–2.0，1.0 = 不变）：",
        "Sharpness (0–1):": "锐度（0–1）：",
        "Super Resolution (Real-ESRGAN 4x)": "超分辨率（Real-ESRGAN 4x）",
        "Watermark Removal (U2Net)": "去水印（U2Net）",
        "One-click Enhance Settings": "一键增强设置",
        "Missing models for": "缺少模型",
        "All models ready": "所有模型就绪",
        "Model not downloaded. Please download in One-click Enhance tab.": "模型未下载，请在「一键增强」页面下载。",
        "One-click enhance:": "一键增强模式：",
        "Download third-party models for AI features:": "下载第三方模型以使用 AI 功能：",
        "On": "开",
        "Both (dedup + dewatermark)": "两者都做（去重+去水印）",
        "Dedup only": "仅去重",
        "Watermark only": "仅去水印",
        "Ask to continue between duplicate groups": "重复组之间询问是否继续",
        "Confirm before cropping a Live Photo (result is a still image)": "裁切 Live Photo 前确认（结果将变为普通图片）",
        "Enable proxy for model downloads": "模型下载启用代理",
        "Type:": "类型：",
        "Host:": "地址：",
        "Port:": "端口：",
        "AI Models": "AI 模型",
        "Not downloaded": "未下载",
        "Downloading… %.0f%%": "下载中… %.0f%%",
        "Enabled": "已启用",
        "Ready (disabled)": "就绪（已禁用）",
        "Error: %@": "错误：%@",
        "Download": "下载",
        "Downloaded": "已下载",
        "Uninstall": "卸载",
        "Uninstall %@?": "卸载%@？",
        "The downloaded model files will be deleted. You can download them again later.": "下载的模型文件将被删除，之后可以重新下载。",
        "Logging": "日志",
        "Enable logging (default: off)": "启用日志（默认关闭）",
        "Log file:": "日志文件：",
        "Browse...": "浏览...",
        "Restore Defaults": "恢复默认",
        "Restore This Page Defaults": "恢复本页默认",

        // ── Shortcuts help window ────────────────────────────────────
        "Keyboard Shortcuts": "键盘快捷键",
        "Previous image (arrows / WASD / HJKL)": "上一张图片（方向键 / WASD / HJKL）",
        "Next image (arrows / WASD / HJKL)": "下一张图片（方向键 / WASD / HJKL）",
        "Rotate 90° clockwise": "顺时针旋转 90°",
        "Rotate 90° counterclockwise": "逆时针旋转 90°",
        "Play / Pause slideshow": "播放/暂停幻灯片",
        "Start / Stop slideshow": "开始/停止幻灯片",
        "Toggle full screen": "切换全屏",
        "Exit slideshow / full screen": "退出幻灯片/全屏",
        "Show this help": "显示本帮助",
        "Fit / 100% (double-click image)": "适应窗口 / 100%（双击图片）",
        "Zoom (mouse wheel / trackpad pinch)": "缩放（鼠标滚轮 / 触控板双指）",

        // ── Dedup comparison window ──────────────────────────────────
        "Choose which image to keep": "选择要保留的图片",
        "← KEEP (Enter)": "← 保留 (Enter)",
        "KEEP (Enter) →": "保留 (Enter) →",

        // ── Empty-state placeholder ──────────────────────────────────
        "Open Images": "打开图片",
        "Drag images here, or click here to open": "拖入图片，或点击此处打开",

        // ── AI state marks (title / status bar) ──────────────────────
        "AI Super-Resolved": "AI 已超分",
        "AI Watermark Removed": "AI 已去水印",
        "AI Enhanced": "AI 已增强",
    ]

    // MARK: - zh-Hant translations (Traditional Chinese)

    private static let zhHant: [String: String] = [
        // ── Menu bar titles ──────────────────────────────────────────
        "File": "檔案",
        "Edit": "編輯",
        "View": "顯示",
        "Window": "視窗",
        "Help": "說明",

        // ── PixAI menu ───────────────────────────────────────────────
        "About PixAI": "關於 PixAI",
        "Check for Updates...": "檢查更新...",
        "Preferences...": "偏好設定...",
        "Services": "服務",
        "Hide PixAI": "隱藏 PixAI",
        "Hide Others": "隱藏其他",
        "Show All": "全部顯示",
        "Quit PixAI": "結束 PixAI",

        // ── File menu ────────────────────────────────────────────────
        "Open...": "打開...",
        "New Window": "新增視窗",
        "Save": "儲存",
        "Save As...": "另存為...",
        "Rename...": "重新命名...",
        "Delete": "刪除",
        "Copy": "拷貝",
        "Paste": "貼上",
        "Close Window": "關閉視窗",

        // ── View menu ────────────────────────────────────────────────
        "Zoom In": "放大",
        "Zoom Out": "縮小",
        "Fit / 100%": "適應視窗 / 100%",
        "Crop": "裁切",
        "Rotate Clockwise": "順時針旋轉",
        "Rotate Counterclockwise": "逆時針旋轉",
        "Play/Pause": "播放/暫停",
        "Start/Stop Slideshow": "開始/停止幻燈片",
        "Enter Full Screen": "進入全螢幕",
        "Toggle Full Screen": "切換全螢幕",

        // ── Context menu navigation ──────────────────────────────
        "Previous Image": "上一張",
        "Next Image": "下一張",
        "First Image": "第一張",
        "Last Image": "最後一張",

        // ── AI menu ──────────────────────────────────────────────────
        "AI Super-Resolution": "AI 超解析度",
        "AI Watermark Removal": "AI 去浮水印",
        "AI Quality Enhance": "AI 畫質增強",
        "One-Click AI Auto-Enhance": "一鍵 AI 自動增強",

        // ── Window menu ──────────────────────────────────────────────
        "Minimize": "最小化",
        "Zoom": "縮放視窗",
        "Shortcuts": "快捷鍵",

        // ── Toolbar tooltips ─────────────────────────────────────────
        "Previous image": "上一張圖片",
        "Next image": "下一張圖片",
        "Rotate clockwise (R)": "順時針旋轉 (R)",
        "Rotate counterclockwise (Cmd+R)": "逆時針旋轉 (⌘R)",
        "Zoom in": "放大",
        "Zoom out": "縮小",
        "Fit to window / 100%": "適應視窗 / 100%",
        "Play/Pause (Space)": "播放/暫停 (空白鍵)",
        "AI quality enhance": "AI 畫質增強",
        "AI dewatermark": "AI 去浮水印",
        "AI super-resolution": "AI 超解析度",
        "One-click AI auto-enhance": "一鍵 AI 自動增強",
        "Save (overwrite)": "儲存（覆蓋）",
        "Delete (move to Trash)": "刪除（移到垃圾桶）",

        // ── Status bar / window messages ─────────────────────────────
        "Open or drag images here": "打開或拖入圖片",
        "First image, wrapping to last": "已是第一張，循環到最後一張",
        "Last image, wrapping to first": "已是最後一張，循環到第一張",
        "Shown scaled down (huge image thumbnail)": "已縮放顯示（超大圖縮圖）",
        "scaled": "已縮放",
        "Nothing to save": "沒有可儲存的變更",
        "Save failed": "儲存失敗",
        "Save failed: unsupported format": "儲存失敗：不支援的格式",
        "Saved": "已儲存",
        "Saved as %@": "已另存為 %@",
        "Copied": "已複製",
        "Pasted": "已貼上",
        "Delete Overlay": "刪除貼圖",
        "Save Changes?": "儲存變更？",
        "You have unsaved changes. Do you want to save them?": "您有未儲存的變更。是否儲存？",
        "Don't Save": "不儲存",
        "Save All": "全部儲存",
        "Discard All": "全部捨棄",
        "Cancel": "取消",
        "AI upscaling…": "AI 超分中…",
        "AI dewatermarking…": "AI 去浮水印中…",
        "AI enhance failed": "AI 增強失敗",
        "Cannot get image data": "無法取得影像資料",
        "AI upscale failed": "AI 超分失敗",
        "AI dewatermark failed": "AI 去浮水印失敗",
        "No watermark detected": "未偵測到浮水印",
        "Real-ESRGAN model not downloaded — see Preferences ▸ AI Models": "Real-ESRGAN 模型未下載 — 請在 偏好設定 ▸ AI 模型 中下載",
        "U2Net model not downloaded — see Preferences ▸ AI Models": "U2Net 模型未下載 — 請在 偏好設定 ▸ AI 模型 中下載",
        "AI one-click enhance complete": "一鍵 AI 增強完成",
        "AI batch cancelled": "AI 批次處理已取消",
        "This operation takes time, please wait": "此操作需要一些時間，請稍候",
        "AI One-Click Enhance": "一鍵 AI 增強",
        "Run AI dedup and dewatermark on the current image queue? Duplicate files will be moved to the Trash.": "是否在目前圖片佇列上執行 AI 去重和去浮水印？重複檔案將被移到垃圾桶。",
        "Run": "執行",
        "Continue?": "繼續？",
        "More duplicate groups remain. Continue deduplicating?": "仍有重複組待處理。是否繼續去重？",
        "Yes": "是",
        "No": "否",
        "Delete \u{201C}%@\u{201D}?": "刪除\u{201C}%@\u{201D}？",
        "The file will be moved to the Trash.\nSize: %@": "檔案將被移到垃圾桶。\n大小：%@",
        "Don't ask again": "不再詢問",
        "Moved to Trash": "已移到垃圾桶",
        "Large image warning": "大圖警告",
        "\u{201C}%@\u{201D} is %@, larger than 50 MB. Displaying it may use a lot of memory.": "\u{201C}%@\u{201D}為%@，超過 50 MB。顯示它可能佔用大量記憶體。",
        "OK": "好",
        "Playback ended": "播放結束",
        "Unsupported format": "不支援的格式",

        // ── Crop ─────────────────────────────────────────────────────
        "Cropping not supported": "不支援裁切",
        "Cropping GIF and animated images is not supported.": "不支援裁切 GIF 和動畫圖片。",
        "Crop Live Photo?": "裁切 Live Photo？",
        "Cropping converts this Live Photo into a regular still image.": "裁切後該 Live Photo 將變成普通靜態圖片。",
        "Save the cropped image": "儲存裁切後的圖片",

        // ── Rename ───────────────────────────────────────────────────
        "Rename image": "重新命名圖片",
        "Rename": "重新命名",
        "Renamed to %@": "已重新命名為 %@",
        "Rename failed: %@": "重新命名失敗：%@",

        // ── Startup model check dialog ───────────────────────────────
        "AI models are missing": "AI 模型缺失",
        "The following AI models are not downloaded (or are corrupted / deleted / moved):": "以下 AI 模型未下載（或已損壞/刪除/移動）：",
        "Download now?": "立即下載？",
        "Later": "稍後",

        // ── Preferences window ───────────────────────────────────────
        "Preferences": "偏好設定",
        "General": "一般",
        "Advanced": "進階",
        "Quit app when the last window is closed": "關閉最後一個視窗時結束應用程式",
        "Ask for confirmation before deleting a file": "刪除檔案前詢問確認",
        "Language": "語言",
        "Image transition duration (0–2 s, 0 = off):": "圖片切換動畫時長（0–2 秒，0=關閉）：",
        "Ask to download AI models at startup when missing": "啟動時若 AI 模型缺失/損壞則詢問下載",
        "Auto-play Live Photos when displayed": "顯示時自動播放 Live Photo",
        "Mute Live Photo playback": "Live Photo 播放靜音",

        // ── Open panel directory ────────────────────────────────────
        "Default directory:": "預設目錄：",
        "Last open": "上次開啟",
        "Choose...": "選擇...",
        "Slideshow": "幻燈片",
        "Interval per slide (1–600 s):": "每張間隔（1–600 秒）：",
        "Slideshow interval (1–600 s):": "幻燈片間隔（1–600 秒）：",
        "Image Cache": "圖片快取",
        "Cached images (1–20):": "快取圖片數（1–20）：",
        "Auto AI super-resolve small images on load": "載入時自動 AI 超分小圖",
        "Auto AI dewatermark on load": "載入時自動 AI 去浮水印",
        "Quality Enhance": "畫質增強",
        "Super Resolution": "超解析度",
        "Remove Watermark": "去浮水印",
        "One-click Enhance": "一鍵增強",
        "Enhancement Parameters": "增強參數",
        "Vibrance (0–1):": "飽和度（0–1）：",
        "Contrast (0.5–2.0, 1.0 = off):": "對比度（0.5–2.0，1.0 = 不變）：",
        "Sharpness (0–1):": "銳度（0–1）：",
        "Super Resolution (Real-ESRGAN 4x)": "超解析度（Real-ESRGAN 4x）",
        "Watermark Removal (U2Net)": "去浮水印（U2Net）",
        "One-click Enhance Settings": "一鍵增強設定",
        "Missing models for": "缺少模型",
        "All models ready": "所有模型就緒",
        "Model not downloaded. Please download in One-click Enhance tab.": "模型未下載，請在「一鍵增強」頁面下載。",
        "One-click enhance:": "一鍵增強模式：",
        "Download third-party models for AI features:": "下載第三方模型以使用 AI 功能：",
        "On": "開",
        "Both (dedup + dewatermark)": "兩者都做（去重+去浮水印）",
        "Dedup only": "僅去重",
        "Watermark only": "僅去浮水印",
        "Ask to continue between duplicate groups": "重複組之間詢問是否繼續",
        "Confirm before cropping a Live Photo (result is a still image)": "裁切 Live Photo 前確認（結果將變為普通圖片）",
        "Enable proxy for model downloads": "模型下載啟用代理",
        "Type:": "類型：",
        "Host:": "位址：",
        "Port:": "連接埠：",
        "AI Models": "AI 模型",
        "Not downloaded": "未下載",
        "Downloading… %.0f%%": "下載中… %.0f%%",
        "Enabled": "已啟用",
        "Ready (disabled)": "就緒（已停用）",
        "Error: %@": "錯誤：%@",
        "Download": "下載",
        "Downloaded": "已下載",
        "Uninstall": "解除安裝",
        "Uninstall %@?": "解除安裝%@？",
        "The downloaded model files will be deleted. You can download them again later.": "下載的模型檔案將被刪除，之後可以重新下載。",
        "Logging": "日誌",
        "Enable logging (default: off)": "啟用日誌（預設關閉）",
        "Log file:": "日誌檔案：",
        "Browse...": "瀏覽...",
        "Restore Defaults": "恢復預設",
        "Restore This Page Defaults": "恢復本頁預設",

        // ── Shortcuts help window ────────────────────────────────────
        "Keyboard Shortcuts": "鍵盤快捷鍵",
        "Previous image (arrows / WASD / HJKL)": "上一張圖片（方向鍵 / WASD / HJKL）",
        "Next image (arrows / WASD / HJKL)": "下一張圖片（方向鍵 / WASD / HJKL）",
        "Rotate 90° clockwise": "順時針旋轉 90°",
        "Rotate 90° counterclockwise": "逆時針旋轉 90°",
        "Play / Pause slideshow": "播放/暫停幻燈片",
        "Start / Stop slideshow": "開始/停止幻燈片",
        "Toggle full screen": "切換全螢幕",
        "Exit slideshow / full screen": "結束幻燈片/全螢幕",
        "Show this help": "顯示本說明",
        "Fit / 100% (double-click image)": "適應視窗 / 100%（雙擊圖片）",
        "Zoom (mouse wheel / trackpad pinch)": "縮放（滑鼠滾輪 / 觸控板雙指）",

        // ── Dedup comparison window ──────────────────────────────────
        "Choose which image to keep": "選擇要保留的圖片",
        "← KEEP (Enter)": "← 保留 (Enter)",
        "KEEP (Enter) →": "保留 (Enter) →",

        // ── Empty-state placeholder ──────────────────────────────────
        "Open Images": "打開圖片",
        "Drag images here, or click here to open": "拖入圖片，或點擊此處打開",

        // ── AI state marks (title / status bar) ──────────────────────
        "AI Super-Resolved": "AI 已超分",
        "AI Watermark Removed": "AI 已去浮水印",
        "AI Enhanced": "AI 已增強",
    ]
}
