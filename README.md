# HApi — Home Assistant in raspberrypi

基于 Docker Compose 部署，将 Home Assistant 核心平台、设备通信中间件、语音处理引擎整合为两个独立编排栈，开箱即用。

## 📁 项目结构

```
HApi/
├── README.md
├── package.json                          # Node.js 项目管理 & 便捷脚本
├── .env.template                         # 全局环境变量模板（跟踪到 Git）
├── .env                                  # 实际环境变量（不跟踪，含敏感信息）
├── .gitignore
├── scripts/
│   ├── setup.js                          # 项目初始化（复制 .env、生成目录、调 generate-config）
│   └── generate-config.js                # 从 .template 文件 + .env 变量生成实际配置
│
├── homeassistant/                        # ★ 项目1: 核心HA服务栈
│   ├── docker-compose.yml
│   ├── .env                              # 从根 .env 复制（不跟踪）
│   ├── config/                           # HA 配置文件（不跟踪）
│   ├── esphome-configs/                  # ESPHome 设备配置文件
│   ├── mosquitto/
│   │   ├── config/
│   │   │   └── mosquitto.conf.template   # MQTT 配置模板
│   │   ├── data/                         # MQTT 持久化数据（不跟踪）
│   │   └── log/                          # MQTT 日志（不跟踪）
│   ├── zigbee2mqtt/
│   │   └── data/
│   │       └── configuration.yaml.template # Z2M 配置模板
│   └── nodered/
│       └── data/                         # Node-RED 流程数据（不跟踪）
│
└── voice/                                # ★ 项目2: 离线语音处理栈
    ├── docker-compose.yml
    ├── .env                              # 从根 .env 复制（不跟踪）
    ├── openwakeword/
    │   └── custom/                       # 自定义唤醒词模型 (.tflite)
    ├── vosk/
    │   └── data/                         # Vosk STT 数据（模型自动下载）
    └── piper/
        └── models/                       # Piper TTS 模型 (.onnx + .json)
```

## 🚀 快速开始

### 前置要求

- **Docker** ≥ 20.10
- **Docker Compose** ≥ 2.0（或 `docker compose` 插件）
- **Node.js** ≥ 18（仅运行初始化脚本用）
- 一块 Zigbee 协调器（如 CC2652、CC2531、ZBDongle-E），如仅测试可跳过

### 1. 克隆项目

```bash
git clone <your-repo-url> HApi
cd HApi
```

### 2. 配置环境变量

```bash
# 从模板创建 .env（或直接运行 setup 脚本自动创建）
cp .env.template .env
```

编辑 `.env`，按实际情况修改下列关键配置：

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `TIMEZONE` | 时区 | `Asia/Shanghai` |
| `MQTT_USERNAME` | MQTT 用户名 | `mqtt_user` |
| `MQTT_PASSWORD` | MQTT 密码 | `change_me_to_a_strong_password` |
| `ZIGBEE_COORDINATOR_PORT` | Zigbee 协调器串口 | `/dev/ttyUSB0`（Linux）；Windows 用 `COM3` 等 |
| `ZIGBEE_COORDINATOR_BAUDRATE` | 协调器波特率 | `115200` |
| `VOSK_LANGUAGE` | Vosk 语音语言代码（首次运行自动下载模型） | `zh` |
| `PIPER_VOICE` | Piper 合成语音名 | `zh_CN-huayan-medium` |

### 3. 运行初始化脚本

```bash
npm run setup
```

此脚本将：
- 创建所有必要的目录结构
- 为 `homeassistant/` 和 `voice/` 生成 `.env` 文件
- 从 `.template` 模板生成 Mosquitto 和 Zigbee2MQTT 的实际配置文件

### 4. 下载语音模型（按需）

**Vosk（STT 语音识别）：**
首次启动时根据 `.env` 中的 `VOSK_LANGUAGE` 自动下载对应语言模型，无需手动操作。
如需手动放置预下载模型，放入 `voice/vosk/data/` 目录即可。
模型列表: https://alphacephei.com/vosk/models

**Piper（TTS 语音合成）：**
```bash
# 下载 zh_CN-huayan-medium 语音（约 50MB）
# 模型列表: https://huggingface.co/rhasspy/piper-voices
cd voice/piper/models/
wget https://huggingface.co/rhasspy/piper-voices/resolve/main/zh/zh_CN/huayan/medium/zh_CN-huayan-medium.onnx
wget https://huggingface.co/rhasspy/piper-voices/resolve/main/zh/zh_CN/huayan/medium/zh_CN-huayan-medium.onnx.json
```

**自定义唤醒词（可选）：**
```bash
# 将训练好的 .tflite 唤醒词模型放入 voice/openwakeword/custom/
```

### 5. 启动服务

```bash
# 启动 Home Assistant 核心栈
npm run ha:up

# 启动语音服务栈
npm run voice:up

# 或一次性启动全部
npm run all:up
```

## 📦 服务概览

### Home Assistant 核心栈

| 服务 | 容器名 | 网络模式 | 端口 | Web 地址 |
|------|--------|----------|------|----------|
| **Home Assistant** | `ha-core` | host | 8123 | `http://<宿主机IP>:8123` |
| **Mosquitto** | `ha-mosquitto` | bridge (`shared_ha_net`) | 1883 (MQTT), 9001 (WS) | — |
| **Zigbee2MQTT** | `ha-z2m` | bridge (`shared_ha_net`) | 8080 | `http://<宿主机IP>:8080` |
| **Node-RED** | `ha-nodered` | bridge (`shared_ha_net`) | 1880 | `http://<宿主机IP>:1880` |
| **ESPHome** | `ha-esphome` | host | 6052 | `http://<宿主机IP>:6052` |

> **网络设计说明：** Home Assistant 和 ESPHome 使用 `host` 网络模式以保障设备发现（mDNS/Bonjour）、USB 直通和 Zigbee 协调器访问的稳定性。Mosquitto、Zigbee2MQTT、Node-RED 共享 `shared_ha_net` 自定义桥接网络，通过容器名互相通信，降低端口冲突风险。

### 语音服务栈

| 服务 | 容器名 | 网络模式 | 端口 | 功能 |
|------|--------|----------|------|------|
| **openWakeWord** | `voice-openwakeword` | bridge (`shared_voice_net`) | 10400 | 唤醒词检测 |
| **Vosk** | `voice-vosk` | bridge (`shared_voice_net`) | 10300 | 离线语音识别 (STT) |
| **Piper** | `voice-piper` | bridge (`shared_voice_net`) | 10200 | 离线语音合成 (TTS) |

## 🔧 配置与集成

### HACS 安装

你需要进入 Home Assistant 容器，然后执行一个安装脚本。

#### 1. 进入容器
执行以下命令：
```bash
docker exec -it ha-core sh
```

#### 2. 执行安装命令
进入容器后，运行以下命令：
```bash
wget -O - https://get.hacs.xyz | bash -
```

#### 3. 退出并重启容器
宿主机上重启 Home Assistant 容器：
```bash
docker restart ha-core
```

#### 4. 安装完成后
HA 重启后，进入 **设置 → 设备与服务 → 添加集成**，搜索 `HACS` 进行安装，按照提示完成与 GitHub 账号的授权即可。

### MQTT 集成

1. HA 页面：**设置 → 设备与服务 → 添加集成**
2. 搜索 `MQTT`
3. 服务器地址填 `localhost`，端口 `1883`
4. 如启用了认证则填入用户名密码

### Zigbee2MQTT

- 确保 Zigbee 协调器已插入宿主机
- 在 `.env` 中配置 `ZIGBEE_COORDINATOR_PORT`
- Z2M 自动通过 MQTT Discovery 将设备暴露给 HA
- 管理页面: `http://<宿主机IP>:8080`

### Node-RED

- 访问 `http://<宿主机IP>:1880`
- 使用 Palette 安装 `node-red-contrib-home-assistant-websocket` 节点
- MQTT 节点服务器地址填 `mosquitto`（容器名，同网络内可解析）

### ESPHome

- 访问 `http://<宿主机IP>:6052`
- 配置文件保存在 `homeassistant/esphome-configs/` 目录
- 首次烧录需 USB 直通：取消 `docker-compose.yml` 中 ESPHome 的 `devices` 注释

### 语音助手配置

1. **添加 Wyoming 集成：**
   - HA 页面：**设置 → 设备与服务 → 添加集成**
   - 搜索 `Wyoming Protocol`
   - 分别添加三个服务：
     - openWakeWord: `localhost:10400`
     - Vosk (STT): `localhost:10300`
     - Piper (TTS): `localhost:10200`

2. **创建语音助手：**
   - HA 页面：**设置 → 语音助手 → 添加助手**
   - 指定：
     - 语音识别 (STT): 选择 Wyoming Vosk
     - 语音合成 (TTS): 选择 Wyoming Piper
     - 唤醒词引擎: 选择 Wyoming openWakeWord
   - HA 内置的 HassIL 引擎会自动处理意图匹配

## 📜 npm 脚本速查

```bash
# 初始化项目
npm run setup

# 重新生成配置文件
npm run generate-config          # all: 全部
npm run generate-config ha       # 仅 HA 栈
npm run generate-config voice    # 仅语音栈

# 服务管理
npm run ha:up         # 启动 HA 栈
npm run ha:down       # 停止 HA 栈
npm run ha:logs       # 查看 HA 栈日志
npm run ha:restart    # 重启 HA 栈

npm run voice:up      # 启动语音栈
npm run voice:down    # 停止语音栈
npm run voice:logs    # 查看语音栈日志
npm run voice:restart # 重启语音栈

npm run all:up        # 启动全部
npm run all:down      # 停止全部
```

或直接使用 `docker compose` 命令：

```bash
docker compose -f homeassistant/docker-compose.yml up -d
docker compose -f voice/docker-compose.yml up -d
```

## ⚠️ 注意事项

1. **Host 网络模式：** Home Assistant 和 ESPHome 使用 `host` 网络，在 Windows/macOS 上 Docker Desktop 的 host 网络支持有限，建议在生产环境使用 Linux 宿主机。Windows 用户可能需要将部分 host 网络改为 bridge + 端口映射。

2. **Zigbee 协调器：**
   - Linux: `/dev/ttyUSB0` 或 `/dev/serial/by-id/...`（推荐后者，持久化编号）
   - Windows: `COM3`（且在 `docker-compose.yml` 中需使用 `devices:` 映射）
   - macOS: `/dev/cu.usbserial-xxx`

3. **配置文件安全：**
   - 所有含密码/密钥的配置文件均由 `.template` 通过脚本生成
   - `.env` 和生成的配置文件均已加入 `.gitignore`
   - **请勿将 `.env` 提交到 Git 仓库！**

4. **Mosquitto 密码认证：** 默认允许匿名连接。如需启用密码保护：
   ```bash
   docker exec -it ha-mosquitto mosquitto_passwd -c /mosquitto/config/passwd <用户名>
   ```
   然后编辑 `mosquitto.conf.template` 取消 `password_file` 注释并将 `allow_anonymous` 改为 `false`，重新运行 `npm run generate-config ha` 并重启。

5. **模型存储：** 语音模型文件体积较大（Vosk 中文模型约 42MB，大型模型可达 1GB+），请确保磁盘空间充足。模型文件不会提交到 Git。

6. **端口冲突：** 启动前确认以下端口未被占用：`8123`（HA）、`1883/9001`（MQTT）、`8080`（Z2M）、`1880`（Node-RED）、`6052`（ESPHome）、`10200/10300/10400`（语音服务）。

7. **文件权限：** 在 Linux 上，如果遇到 Mosquitto 日志写入错误，需要修复目录权限：
   ```bash
   sudo chown -R 1883:1883 homeassistant/mosquitto/log/
   ```

8. **ESPHome 编译：** 首次使用 ESPHome 需要在宿主机安装驱动（CP210x/CH340），并将 USB 设备通过 `devices` 映射到容器。

## 🏗️ 技术栈

- [Home Assistant](https://www.home-assistant.io/) — 开源智能家居平台
- [Mosquitto](https://mosquitto.org/) — 轻量级 MQTT 消息代理
- [Zigbee2MQTT](https://www.zigbee2mqtt.io/) — Zigbee ↔ MQTT 桥接
- [Node-RED](https://nodered.org/) — 可视化自动化流程编辑器
- [ESPHome](https://esphome.io/) — ESP32/ESP8266 固件编译烧录
- [openWakeWord](https://github.com/dscripka/openWakeWord) — 离线唤醒词检测
- [Vosk](https://alphacephei.com/vosk/) — 离线语音识别
- [Piper](https://github.com/rhasspy/piper) — 离线语音合成
- [Wyoming Protocol](https://github.com/rhasspy/wyoming) — 语音服务通信协议
- [HassIL](https://github.com/home-assistant/hassil) — Home Assistant 内置意图匹配引擎
