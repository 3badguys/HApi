# 树莓派 Zigbee 网关驱动修复记录 (CH9102X + CC2652P)

## 问题背景

插入 USB Zigbee 网关 (基于 CH9102X + CC2652P) 后，系统默认加载了通用驱动 `cdc_acm`，导致设备节点为 `/dev/ttyACM0`，且无法响应 `AT` 命令（网关不返回 `OK`）。需要强制使用沁恒官方驱动 `ch343` 来接管设备。

---

## 环境信息

- 设备：树莓派 4B (Raspberry Pi OS, 内核 6.1.21-v8+)
- 网关芯片：USB 转串口 **CH9102X** + Zigbee 芯片 **CC2652P**
- 目标：让系统使用 `ch343` 驱动，设备节点为 `/dev/ttyCH343USB0`

---

## 1. 下载并编译官方 `ch343` 驱动

```bash
# 克隆官方驱动仓库
git clone https://github.com/WCHSoftGroup/ch343ser_linux.git

# 进入驱动目录
cd ch343ser_linux/driver

# 编译驱动
make

# 安装驱动到系统（复制模块到系统目录 + 更新依赖 + 写入 /etc/modules）
sudo make install
```

> 如果 `make` 报错缺少头文件，先执行：
> ```bash
> sudo apt install raspberrypi-kernel-headers
> ```

---

## 2. 确认 `cdc_acm` 是否为可加载模块

```bash
grep cdc_acm /lib/modules/$(uname -r)/modules.builtin
```

- **无输出** → 说明 `cdc_acm` 是可加载模块（`.ko`），可以用黑名单屏蔽。
- **有输出** → 说明是 built-in，需要用 `udev` 规则（本机为无输出，所以采用黑名单）。

### 2.1 查看 `cdc_acm` 模块详细信息（可选）

```bash
modinfo cdc_acm
```

输出示例：
```
filename:       /lib/modules/6.1.21-v8+/kernel/drivers/usb/class/cdc-acm.ko.xz
license:        GPL
description:    USB Abstract Control Model driver for USB modems and ISDN adapters
alias:          usb:v*p*d*dc*dsc*dp*ic02isc02ip06in*
...
```

- `filename`：模块文件路径（`.xz` 表示压缩，不影响加载）
- `alias`：驱动匹配的 USB 设备 ID 模式，说明它愿意接管哪些设备
- 这些信息帮助我们确认 `cdc_acm` 确实是一个独立模块，且会匹配你的网关硬件。

---

## 3. 屏蔽 `cdc_acm` 驱动

### 3.1 创建黑名单文件

使用一行命令直接创建黑名单文件：

```bash
echo "blacklist cdc_acm" | sudo tee /etc/modprobe.d/blacklist-cdc_acm.conf
```

这会在 `/etc/modprobe.d/` 下生成 `blacklist-cdc_acm.conf` 文件，内容为 `blacklist cdc_acm`。

### 3.2 更新 initramfs（让屏蔽在早期启动生效）

```bash
sudo update-initramfs -u
```

### 3.3 重启树莓派

```bash
sudo reboot
```

---

## 4. 验证驱动切换成功

重启后，重新插入 Zigbee 网关，然后执行以下检查：

### 4.1 确认 `cdc_acm` 未加载

```bash
lsmod | grep cdc_acm
# 应无输出
```

### 4.2 确认 `ch343` 已自动加载

```bash
lsmod | grep ch343
# 应显示 ch343 模块信息
```

### 4.3 查看内核日志

```bash
dmesg | tail -20
```

期望看到：
```
usb 1-1.1: new full-speed USB device number X using xhci_hcd
usb 1-1.1: New USB device found, idVendor=1a86, idProduct=55d4
usb_ch343 1-1.1:1.0: ttyCH343USB0: usb to uart device
```

### 4.4 检查设备节点

```bash
ls -l /dev/ttyCH343USB0
# 应显示该设备文件
```

---

## 5. 测试串口通信 (`AT` 命令)

确认驱动切换成功后，测试网关是否响应：

```bash
stty -F /dev/ttyCH343USB0 115200 cs8 -cstopb -parenb -ixon -ixoff -crtscts
echo -e "AT\r" | sudo tee /dev/ttyCH343USB0 && timeout 3 cat /dev/ttyCH343USB0
```

- **如果返回 `OK`** → 网关硬件正常，可继续配置 Zigbee2MQTT。
- **如果无响应** → 可能需要刷写 CC2652P 固件（参考步骤 6）。

---

## 6. (可选) 刷写 CC2652P 协调器固件

如果 `AT` 命令无响应，说明 Zigbee 芯片固件损坏或缺失，需要重新刷写。

### 6.1 安装刷写工具 `cc2538-bsl`

```bash
cd ~
mkdir -p cc2538-bsl
cd cc2538-bsl
git clone https://github.com/JelmerT/cc2538-bsl.git .
```

### 6.2 安装 Python 依赖

```bash
sudo apt install python3-serial python3-intelhex -y
```

### 6.3 下载官方协调器固件

前往 [Koenkk/Z-Stack-firmware Releases](https://github.com/Koenkk/Z-Stack-firmware/releases) 下载适用于 `CC2652P` 的 `coordinator` 固件，建议选择 `CC1352P2_CC2652P_other_coordinator_YYYYMMDD.zip`。

下载后解压得到 `.hex` 文件。

### 6.4 让网关进入刷写模式

1. 拔掉网关 USB。
2. **按住**网关上的 `Boot` 按钮。
3. 保持按住，重新插入 USB。
4. 等待 2-3 秒后松开按钮。

### 6.5 执行刷写

```bash
# 假设你下载的固件名为 CC1352P2_CC2652P_other_coordinator_20250321.hex
sudo python3 cc2538_bsl.py -ewv -p /dev/ttyCH343USB0 --bootloader-sonoff-usb ./CC1352P2_CC2652P_other_coordinator_20250321.hex
```

### 6.6 为什么修改 `network_key`、`pan_id` 或 `ext_pan_id` 后必须重刷（或擦除 NVRAM）？

Zigbee 协调器（CC2652P 芯片）的 **Flash 存储器** 中分为两个主要区域：

- **固件区**：存放 Zigbee 协议栈和协调器程序（即你刷写的 `.hex` 或 `.bin` 文件）。
- **NVRAM（非易失性随机存取存储器）**：存放当前网络的运行参数，包括：
  - `network_key`（网络密钥）
  - `pan_id` 和 `extended_pan_id`（扩展 PAN ID）
  - 已配对设备列表、绑定表、路由表等

#### 三个参数各自的作用

| 参数 | 位数 | 作用 |
|------|------|------|
| **`network_key`** | 128 位（16 字节） | Zigbee 网络加密密钥，所有通信数据都通过它加密，防止未授权设备监听。 |
| **`pan_id`** | 16 位（如 `0x60C3`） | 局域网络标识符，用于在同一空间内区分不同 Zigbee 网络。多个网络可以使用相同的 `pan_id`（只要它们相距足够远）。 |
| **`ext_pan_id`** | 64 位（IEEE 扩展地址） | 全球唯一网络标识符，在网络冲突或扫描时精确识别你的专属网络。即使两个网络的 `pan_id` 相同，`ext_pan_id` 也能将它们区分开。 |

**`network_key`、`pan_id`、`ext_pan_id` 三者共同构成了 Zigbee 网络的完整“身份证”**，它们全部存储在硬件的 NVRAM 中。

#### 为什么修改其中任何一个都必须重刷？

当你仅修改 Zigbee2MQTT 配置文件（或环境变量）中的这些参数时，**实际上只改变了软件端告诉硬件“应该用什么参数建网”的期望值**。但硬件通电启动时，会**优先读取 Flash 中 NVRAM 里已存储的旧参数**。如果 NVRAM 中已经存在一份完整的网络身份（包括旧的 key、pan_id 和 ext_pan_id），固件就会认为“我已经属于一个旧的 Zigbee 网络”，从而**拒绝使用你提供的新参数进行 commissioning**，最终导致启动超时，报错：

```
network commissioning timed out - most likely network with the same panId or extendedPanId already exists nearby
```

**关键点**：即使你只修改了其中一个参数（比如只改了 `ext_pan_id`），只要 NVRAM 里还存着旧值，固件就会检测到网络身份不一致，拒绝启动。因此，**任何一项网络身份参数的修改，都必须清空 NVRAM 或重刷固件才能生效**。

#### 解决这个问题的两种途径：

| 方法 | 操作 | 优点 | 缺点 / 风险 |
|------|------|------|------------|
| **① 仅擦除 NVRAM 页** | 使用 `cc2538-bsl -E <页号>` 只清除 NVRAM 区域，保留固件。 | 固件不变，操作时间短。 | 需要知道 NVRAM 的确切起始页号（不同固件版本可能不同），指定错误页号可能导致固件损坏或擦除无效。工具使用较复杂，不适合新手。 |
| **② 全片擦除 + 重刷固件**（本文采用） | 使用 `cc2538-bsl -e -w 固件.bin` 将整个 Flash 擦除，然后写入全新固件。 | **最彻底、最可靠**。NVRAM 被完全清空，固件同时也更新到最新版本，避免旧版 bug。操作步骤标准化，社区广泛采用。 | 耗时稍长（约 1 分钟），需要重新下载固件文件。 |

**因此，当你决定更换网络密钥、PAN ID 或扩展 PAN ID 时，最稳妥的做法就是直接全擦并刷入最新协调器固件。**
这不仅清空了旧网络参数，还能让你享受固件更新带来的性能提升和稳定性修复。

#### ⚠️ 重要提醒：刷完固件后必须删除 `coordinator_backup.json`

Zigbee2MQTT 会在 `data` 目录下保存一个 `coordinator_backup.json` 文件，用于在协调器意外损坏时恢复网络。**如果该文件存在**，Z2M 启动时会将其中的旧网络参数（包括旧的 `network_key`、`pan_id` 和 `ext_pan_id`）重新写回硬件的 NVRAM，导致你刚刚清空的参数再次被覆盖，新网络仍然无法创建。

所以，刷完固件并重新插拔协调器后，**务必执行**：
```bash
rm -f homeassistant/zigbee2mqtt/data/coordinator_backup.json
```
然后再启动 Z2M，这样硬件就会以“空白”状态接受你在配置文件里指定的新 `network_key`、`pan_id` 和 `ext_pan_id`，顺利建立新网络。

---

## 7. 配置 Zigbee2MQTT

确保 `configuration.yaml` 中 `serial` 部分使用正确的设备路径：

```yaml
serial:
  port: /dev/ttyCH343USB0
  adapter: zstack
  baudrate: 115200
```

然后启动 Z2M 容器，检查日志是否正常启动。

---

## 8. 最终验证

- `lsmod | grep ch343` → 有输出
- `ls -l /dev/ttyCH343USB0` → 存在
- `AT` 命令返回 `OK`
- Z2M 日志显示 `Zigbee2MQTT started`

至此，Zigbee 网关在树莓派上驱动切换完成，可以正常使用了。

---

## 附：如果上述方案无效（备选）

如果黑名单屏蔽 `cdc_acm` 后仍被抢占（例如系统是 built-in），可使用 `udev` 规则强制绑定：

创建 `/etc/udev/rules.d/99-ch343.rules`，内容：
```
SUBSYSTEM=="usb", ATTRS{idVendor}=="1a86", ATTRS{idProduct}=="55d4", ACTION=="add", RUN+="/bin/sh -c 'echo $kernel > /sys/bus/usb/drivers/cdc_acm/unbind 2>/dev/null; echo $kernel > /sys/bus/usb/drivers/usb_ch343/bind 2>/dev/null'"
```

然后重新加载规则并插拔设备。

---

## 参考链接

- [WCH 官方驱动仓库](https://github.com/WCHSoftGroup/ch343ser_linux)
- [cc2538-bsl 工具](https://github.com/JelmerT/cc2538-bsl)
- [Koenkk/Z-Stack-firmware](https://github.com/Koenkk/Z-Stack-firmware/releases)

---

**操作系统：** Raspberry Pi OS (Debian 11)  
**内核版本：** 6.1.21-v8+  
