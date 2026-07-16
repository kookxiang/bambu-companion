# Bambu Companion

Bambu Companion 是一个 macOS 状态栏应用，用来在局域网内监控 Bambu Lab 打印机。

它会直接连接打印机的 LAN MQTT 事件流和 RTSP 视频流，在状态栏弹出面板里展示当前打印状态、温度、AMS 料盘、封面图、告警和摄像头预览。

## 功能

- 状态栏显示当前打印进度。
- 弹出面板展示打印状态、任务名称、进度、层数、剩余时间、喷嘴、热床、机箱、风扇和 AMS 信息。
- 支持 H2D 等双喷嘴机型的左右喷嘴温度显示。
- AMS 料盘展示：当前使用槽位高亮、耗材颜色/类型、可用时显示预计剩余重量、悬停显示温湿度信息，并支持烘干状态提示。
- 通过 FTPS 从打印机读取 `.3mf` 文件并提取打印封面图，带本地缓存，避免重复下载。
- 使用 AVFoundation 直接播放原生 RTSP 视频流，无需安装 FFmpeg 或第三方播放器。
- 支持画中画式悬浮监控：可将视频弹出为无标题、始终置顶且可缩放的独立窗口，一边使用其他应用一边观察打印过程。
- 仅在状态栏面板或悬浮监控窗口打开时连接视频流，关闭监控后自动停止播放。
- 打印状态发生有效变化、或出现 HMS 告警时发送 macOS 通知。
- 支持英文和简体中文界面文本。
- 设置窗口可填写打印机名称、IP/主机名、序列号和局域网访问码。

## 运行要求

- macOS 14 或更新版本。
- Xcode 15.4 或更新版本。如果你在使用 beta 系统，也可以使用 Xcode Beta。
- 一台能在同一局域网内访问到的 Bambu Lab 打印机。
- 打印机已开启 LAN 模式 / 局域网访问。
- 打印机 IP 或主机名、序列号、局域网访问码。

## 网络访问

应用会直接访问打印机：

- MQTT over TLS：`8883` 端口。
- RTSP / RTSPS 视频流：`322` 端口。
- FTPS：用于下载 `.3mf` 文件并提取封面图。

应用不需要云账号。局域网访问码会存储在 macOS 钥匙串中，其他打印机设置会存储在 `UserDefaults` 中。

## 构建

用 Xcode 打开 `BambuCompanion.xcodeproj`，运行 `BambuCompanion` scheme。

也可以用命令行构建：

```sh
xcodebuild -scheme BambuCompanion -configuration Debug build
```

如果使用 Xcode Beta：

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild -scheme BambuCompanion -configuration Debug build
```

## 设置

1. 启动应用。
2. 从状态栏弹出面板打开 Settings。
3. 填写打印机 IP/主机名、序列号和局域网访问码。
4. 保存，或点击测试连接。

连接成功后，打印状态会通过 MQTT 推送更新。只有在断开连接或连接失败时，面板底部才会显示手动重连按钮。

点击面板内视频预览右上角的悬浮按钮，可以切换到画中画式监控窗口。悬浮窗口会保持在其他窗口上方，并可自由移动和缩放；鼠标移入后可通过左上角按钮关闭。

## 项目结构

- `BambuCompanion/`：应用源码和资源。
- `BambuCompanion/Assets.xcassets/`：App 图标资源。
- `BambuCompanion/HMSResources/`：从 Bambu Studio 复制的 HMS 错误信息资源。
- `BambuCompanionTests/`：MQTT 解析和相关行为的单元测试。
- `Design/`：Logo 概念图源文件。

## 说明

这是一个局域网内使用的第三方 companion app，与 Bambu Lab 没有关联，也不代表 Bambu Lab 官方。

App 图标是原创设计，灵感来自 companion cube 和 3D 打印语义；它有意避免直接复制 Portal Companion Cube 原始图案或 Bambu Lab 官方 Logo。

## 许可证

应用源码使用 MIT License，见 `LICENSE`。

`BambuCompanion/HMSResources/` 下的 HMS JSON 资源来自官方 Bambu Studio 仓库，按 GNU Affero General Public License v3.0 授权。相关说明和许可证文本见：

- `BambuCompanion/HMSResources/NOTICE.txt`
- `BambuCompanion/HMSResources/LICENSE-BambuStudio-AGPL-3.0.txt`
