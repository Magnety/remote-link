# RemoteLink — 跨平台远程控制软件

基于 **Flutter + Rust** 的跨平台远程桌面控制软件，通过 QQ 机器人实现多设备发现与 WebRTC P2P 信令交换。

## 支持平台
| 平台 | 控制端 | 被控端 | 构建方式 |
|------|--------|--------|----------|
| Windows | ✓ | ✓ | `scripts/build_windows.sh` (cross) 或 Windows 本机 |
| macOS | ✓ | ✓ | `scripts/build_macos.sh` (需 macOS) |
| Android | ✓ | — | `scripts/build_android.sh` |
| Linux (附加) | ✓ | — | `flutter build linux` |

## 技术栈
- **Flutter 3.x** — GUI (Material 3, 中文)
- **Rust 1.70+** — 核心协议、身份、信令、状态同步
- **flutter_rust_bridge** — Dart ↔ Rust FFI
- **WebRTC** — P2P 视频/数据通道
- **SQLite** — 本地设备缓存
- **Ed25519 / X25519** — 设备签名 / 密钥协商

## 快速开始
```bash
cd apps/flutter_app
flutter pub get
flutter run
./scripts/build_android.sh
./scripts/build_windows.sh
./scripts/build_macos.sh
```

## 目录结构
```
remote-link/
├── apps/flutter_app/       # Flutter 应用
├── core/                   # Rust 核心库 (workspace members)
├── signaling-adapters/     # 信令适配器
├── native/                 # 平台原生模块
├── tests/                  # 测试
├── docs/                   # 文档
├── scripts/                # 构建脚本
```

## 首次启动
1. 启动后进入 QQ 机器人配置向导
2. 选择信令方式（QQ 官方 / OneBot / Mock 测试）
3. 输入凭据 → 验证连接 → 保存
4. 创建设备组或输入配对码加入
5. 进入设备管理主页
