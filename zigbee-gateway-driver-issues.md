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

刷写完成后，拔掉网关，直接插回（不需按 Boot），再次测试 `AT` 命令，应返回 `OK`。

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
