## 📋 树莓派 WiFi 断连 / 无法自动连接 排查与修复清单

---

### 🔍 第一步：快速排查（判断问题类型）

```bash
# 1. 查看网卡物理状态
ip link show wlan0

# 2. 检查软屏蔽（软件锁）
sudo rfkill list

# 3. 检查电源管理（省电模式是否开启）
iwconfig wlan0 | grep "Power Management"
```

**判断结果**：
- `rfkill` 显示 `Soft blocked: yes` → 执行 `sudo rfkill unblock wifi`
- `Power Management: on` → 执行 `sudo iwconfig wlan0 power off`
- `state DOWN` + `NO-CARRIER`，且上面两项都正常 → 进入第二步

---

### ⚡ 第二步：手动激活网卡（临时修复）

停掉可能干扰的服务，强制拉高网卡：

```bash
sudo systemctl stop wpa_supplicant dhcpcd
sudo ip link set wlan0 up
sudo iwconfig wlan0 txpower on
sudo iwlist wlan0 scan   # 验证能否扫到 WiFi（应有列表输出）
```

如果能扫到网络，说明硬件完好，继续：

```bash
sudo systemctl start wpa_supplicant dhcpcd

# 查看 wpa_supplicant 当前连接信息
# 输出内容包括：SSID（已连接的网络名）、BSSID（AP 的 MAC 地址）、
#              IP 地址（通过 DHCP 获取的）、认证状态（COMPLETED 表示成功）等。
# 常见状态字段：wpa_state=COMPLETED（成功关联），ip_address=192.168.x.x（获取到 IP）
sudo wpa_cli -i wlan0 status

ip a show wlan0          # 确认是否获取到 IP（192.168.x.x / 10.x.x.x）
```

---

### 🛠️ 第三步：永久修复（防止重启后复发）

#### 3.1 关闭电源管理（永久）
```bash
sudo nano /etc/rc.local
```
在 `exit 0` 前面加入：
```bash
iwconfig wlan0 power off
```

#### 3.2 在启动时自动重置网卡（解决开机卡死）
同样在 `/etc/rc.local` 的 `exit 0` 前面加入：
```bash
ip link set wlan0 down
ip link set wlan0 up
iwconfig wlan0 txpower on
sleep 2
systemctl restart wpa_supplicant
systemctl restart dhcpcd
```

#### 3.3 内核级禁用省电功能（降低运行时卡死概率）
编辑 `/boot/cmdline.txt`：
```bash
sudo nano /boot/cmdline.txt
```
在文件末尾（空格隔开）添加：
```
brcmfmac.feature_disable=0x800
```

编辑 `/boot/config.txt`（可选，增强稳定性）：
```bash
sudo nano /boot/config.txt
```
在末尾添加：
```
dtoverlay=brcmfmac,ignore_warnings=1
```

#### 3.4 生效
```bash
sudo chmod +x /etc/rc.local
```
然后**拔掉电源线，等待 10 秒后重新插电**（软重启无效，必须冷启动）。

---

### 🔄 应急命令（运行时突然断连，无需重启）

```bash
sudo modprobe -r brcmfmac && sudo modprobe brcmfmac && sudo systemctl restart dhcpcd
```

---

### ✅ 验证修复是否生效
```bash
ip a show wlan0          # 应显示 UP 且有正常 IP
iwconfig wlan0 | grep "Power Management"   # 应为 off
sudo rfkill list         # Soft blocked 应为 no
```

---

以上就是完整的操作汇总，按顺序执行即可。如果以后还遇到问题，直接用应急命令快速恢复。👍