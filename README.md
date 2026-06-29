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
│   ├── config/
│   │   └── configuration.yaml.template   # HA 配置模板
│   ├── esphome-configs/                  # ESPHome 设备配置文件
│   ├── mosquitto/
│   │   ├── config/
│   │   │   └── mosquitto.conf.template   # MQTT 配置模板
│   │   ├── mosquitto-entrypoint.sh       # 容器启动脚本（自动生成密码文件）
│   │   ├── data/                         # MQTT 持久化数据（不跟踪）
│   │   └── log/                          # MQTT 日志（不跟踪）
│   ├── zigbee2mqtt/
│   │   └── data/
│   │       └── configuration.yaml.template # Z2M 配置模板
│   └── nodered/
│       └── data/                         # Node-RED 流程数据（不跟踪）
│
├── voice/                                # ★ 项目2: 离线语音处理栈
|   ├── docker-compose.yml
|   ├── .env                              # 从根 .env 复制（不跟踪）
|   ├── openwakeword/
|   │   └── custom/                       # 自定义唤醒词模型 (.tflite)
|   ├── vosk/
|   │   └── data/                         # Vosk STT 数据（模型自动下载）
|   └── piper/
|       └── models/                       # Piper TTS 模型 (.onnx + .json)
│
├── satellite/                            # ★ 项目3: 原生安装 Wyoming Satellite
│   ├── config/
│   │   └── satellite.conf.template       # 卫星配置模板
│   ├── scripts/
│   │   ├── install.sh                    # 一键安装脚本
│   │   └── start.sh                      # 调试启动脚本
│   └── systemd/
│       └── wyoming-satellite.service     # systemd 服务
│
└── camera/                               # ★ 项目4: 原生安装 Motion 摄像头
    ├── config/
    │   └── motion.conf.template          # Motion 配置模板
    ├── scripts/
    │   ├── install.sh                    # 一键安装脚本
    │   └── start.sh                      # 调试启动脚本
    ├── systemd/
    │   └── motion.service                # systemd 服务
    └── recordings/                       # 录像存储目录
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
| `ZIGBEE_COORDINATOR_PORT` | Zigbee 协调器串口 | `/dev/ttyUSB0` 或者 `/dev/ttyACM0`（Linux）；Windows 用 `COM3` 等 |
| `ZIGBEE_COORDINATOR_BAUDRATE` | 协调器波特率 | `115200` |
| `ZIGBEE_CHANNEL` | Zigbee 信道（15/20/25 避开 WiFi 1/6/11） | `15` |
| `ZIGBEE_NETWORK_KEY` | Zigbee 网络密钥（`GENERATE` = 首次自动生成） | `GENERATE` |
| `ZIGBEE_PAN_ID` | Zigbee PAN ID（`GENERATE` = 首次自动生成） | `GENERATE` |
| `ZIGBEE_EXT_PAN_ID` | Zigbee Extended PAN ID（`GENERATE` = 首次自动生成） | `GENERATE` |
| `TRUSTED_PROXIES` | HA 受信反向代理 CIDR（Docker bridge） | `172.16.0.0/12` |
| `VOSK_LANGUAGE` | Vosk 语音语言代码（首次运行自动下载模型） | `zh` |
| `PIPER_VOICE` | Piper 合成语音名 | `zh_CN-huayan-medium` |
| `SATELLITE_NAME` | Wyoming Satellite 名称 | `Living Room Satellite` |
| `SATELLITE_PORT` | Satellite Wyoming 监听端口 | `10700` |
| `SATELLITE_MIC_DEVICE` | 麦克风 ALSA 设备 | `plughw:1,0` |
| `SATELLITE_SPEAKER_DEVICE` | 扬声器 ALSA 设备 | `plughw:1,0` |
| `MOTION_CAMERA_DEVICE` | 摄像头设备路径 | `/dev/video0` |
| `MOTION_CAMERA_WIDTH` / `MOTION_CAMERA_HEIGHT` | 视频分辨率 | `640` × `480` |
| `MOTION_FRAMERATE` | 视频帧率 | `15` |
| `MOTION_WEBCONTROL_PORT` | Motion Web 控制端口 | `8081` |
| `MOTION_STREAM_PORT` | Motion 实时流端口 | `8082` |

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

### Wyoming Satellite（原生安装）

Wyoming Satellite 将本地麦克风/扬声器桥接到 HA 的 Wyoming 语音服务，适合在远离 HA 主机的房间部署。

**安装：**
```bash
npm run sat:install
```

此脚本将：
1. 安装系统依赖（`python3`、`alsa-utils`、`portaudio`）
2. 通过 `pip` 安装 `wyoming-satellite`
3. 检测音频设备并输出可用列表
4. 部署 `systemd` 服务并开机自启

**配置：**
编辑 `.env` 中的 Satellite 相关变量：
- `SATELLITE_MIC_DEVICE` / `SATELLITE_SPEAKER_DEVICE`：运行 `arecord -L` / `aplay -L` 查看可用设备
- `SATELLITE_NAME`：显示在 HA 中的名称
- `WAKE_URI` / `STT_URI` / `TTS_URI`：指向语音栈的 Wyoming 服务地址

**HA 集成：**
进入 **设置 → 设备与服务 → 添加集成 → Wyoming Protocol**，填入 Satellite 所在主机的 IP 和端口（默认 `10700`）。

**手动调试：**
```bash
npm run sat:start     # 前台运行，Ctrl+C 停止
npm run sat:status    # 查看 systemd 状态
npm run sat:logs      # 查看日志
```

### Motion 摄像头（原生安装）

Motion 是 Linux 下的摄像头运动检测守护进程，通过 MQTT 将事件发布到 HA。

**安装：**
```bash
npm run cam:install
```

此脚本将：
1. 通过 `apt` 安装 `motion` 和 `v4l-utils`
2. 检测摄像头设备
3. 将配置部署到 `/etc/motion/motion.conf`
4. 创建录像存储目录
5. 部署 `systemd` 服务并开机自启

**配置：**
编辑 `.env` 中的 Motion 相关变量：
- `MOTION_CAMERA_DEVICE`：运行 `v4l2-ctl --list-devices` 查看摄像头
- `MOTION_CAMERA_WIDTH` / `MOTION_CAMERA_HEIGHT`：分辨率
- `MOTION_MQTT_HOST`：MQTT 服务器地址（通常为 `localhost`）

**HA 集成（4 种方式）：**

| 方式 | 说明 |
|------|------|
| **A. MQTT 自动发现** | Motion 通过 MQTT 发布事件，部分 HA 版本会自动发现 |
| **B. 手动 MQTT binary_sensor** | 在 `configuration.yaml` 中手动添加 `mqtt.binary_sensor`（安装脚本会打印示例） |
| **C. motionEye 插件** | HA 插件商店安装 motionEye，功能更丰富的 Web 管理界面 |
| **D. Generic Camera** | HA 中添加 Generic Camera 集成，填入 Motion 的流地址 |

**Web 界面：**
- 控制面板：`http://<host-IP>:8081`
- 实时流：`http://<host-IP>:8082`

**手动调试：**
```bash
npm run cam:start     # 前台运行，Ctrl+C 停止
npm run cam:status    # 查看 systemd 状态
npm run cam:logs      # 查看日志
```

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

npm run sat:install   # 安装 Wyoming Satellite（原生）
npm run sat:start     # 启动 Satellite（调试）
npm run sat:status    # 查看 Satellite 状态
npm run sat:logs      # 查看 Satellite 日志
npm run sat:restart   # 重启 Satellite

npm run cam:install   # 安装 Motion 摄像头（原生）
npm run cam:start     # 启动 Motion（调试）
npm run cam:status    # 查看 Motion 状态
npm run cam:logs      # 查看 Motion 日志
npm run cam:restart   # 重启 Motion

npm run all:up        # 启动全部 Docker 服务
npm run all:down      # 停止全部 Docker 服务
```

或直接使用 `docker compose` 命令：

```bash
docker compose -f homeassistant/docker-compose.yml up -d
docker compose -f voice/docker-compose.yml up -d
```

## ⚠️ 注意事项

1. **Host 网络模式：** Home Assistant 和 ESPHome 使用 `host` 网络，在 Windows/macOS 上 Docker Desktop 的 host 网络支持有限，建议在生产环境使用 Linux 宿主机。Windows 用户可能需要将部分 host 网络改为 bridge + 端口映射。

2. **Zigbee 协调器：**
   - Linux: `/dev/ttyUSB0` 或 `/dev/ttyACM0` 或 `/dev/serial/by-id/...`（推荐后者，持久化编号）
   - Windows: `COM3`（且在 `docker-compose.yml` 中需使用 `devices:` 映射）
   - macOS: `/dev/cu.usbserial-xxx`

3. **配置文件安全：**
   - 所有含密码/密钥的配置文件均由 `.template` 通过脚本生成
   - `.env` 和生成的配置文件均已加入 `.gitignore`
   - **请勿将 `.env` 提交到 Git 仓库！**

4. **Mosquitto 密码认证：** 容器启动时自动根据 `.env` 中的 `MQTT_USERNAME` / `MQTT_PASSWORD` 生成密码文件，无需手动操作。Zigbee2MQTT 也自动使用相同凭证连接。

5. **模型存储：** 语音模型文件体积较大（Vosk 中文模型约 42MB，大型模型可达 1GB+），请确保磁盘空间充足。模型文件不会提交到 Git。

6. **端口冲突：** 启动前确认以下端口未被占用：`8123`（HA）、`1883/9001`（MQTT）、`8080`（Z2M）、`1880`（Node-RED）、`6052`（ESPHome）、`10200/10300/10400`（语音服务）。

7. **文件权限：** Mosquitto 容器的 entrypoint 脚本会自动修复 `data/`、`log/` 和密码文件的权限，无需手动处理。

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
- [Wyoming Satellite](https://github.com/rhasspy/wyoming-satellite) — 远程语音采集/播放卫星
- [Motion](https://motion-project.github.io/) — 摄像头运动检测守护进程
- [Wyoming Protocol](https://github.com/rhasspy/wyoming) — 语音服务通信协议
- [HassIL](https://github.com/hassil) — Home Assistant 内置意图匹配引擎
