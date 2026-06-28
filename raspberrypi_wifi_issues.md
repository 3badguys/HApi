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

### 🔧 第三步：高级调试（获取详细日志，定位根本原因）

当上述步骤无法连接，或连接后反复断开时，**使用调试模式捕获完整日志**，这是最有效的手段。

#### 3.1 停止系统服务，清理冲突文件
```bash
sudo systemctl stop wpa_supplicant
sudo rm -f /var/run/wpa_supplicant/wlan0   # 清除残留的控制接口文件
```

#### 3.2 启动调试模式，同时输出到终端和文件
```bash
sudo wpa_supplicant -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf -dd 2>&1 | tee wpa_debug.log
```

- 这会**实时显示**调试信息在屏幕上，同时**保存**到 `wpa_debug.log` 文件中。
- 观察日志中的关键词：
  - `CTRL-EVENT-CONNECTED` → 连接成功
  - `ASSOC-REJECT status_code=16` → 认证失败（检查密码/加密方式）
  - `4-Way Handshake failed` → 加密协商失败（检查 `proto`/`pairwise` 设置）
  - `Address already in use` → 服务冲突（按 3.1 清理即可）

#### 3.3 分析并调整配置
根据日志中的错误，调整 `/etc/wpa_supplicant/wpa_supplicant.conf`。

**基础配置模板（针对现代路由器和手机热点优化）**：
```bash
network={
    ssid="你的WiFi名称"
    psk="你的密码"
    proto=RSN          # 仅 WPA2
    key_mgmt=WPA-PSK
    pairwise=CCMP      # 仅 AES
    group=CCMP
    # freq_list=...    # 如需强制 2.4G，取消注释并填写频率列表
}
```

**针对手机热点的特别优化（重要）**：
- **问题现象**：连接手机热点时反复失败，日志显示 `status_code=16`。
- **根本原因**：手机热点对加密协商非常严格，如果树莓派同时抛出多个协议或加密选项（如 `proto=RSN WPA` 或 `pairwise=TKIP CCMP`），热点可能会因为“不专一”或“包含不安全选项”而直接拒绝。
- **解决方案**：**严格精简加密参数**，只保留最标准的 WPA2-AES，即：
  - `proto=RSN`（去掉 `WPA`）
  - `pairwise=CCMP`（去掉 `TKIP`）
  - `group=CCMP`（去掉 `TKIP`）
- 如果你使用的是老旧路由器，且上述配置无法连接，可以尝试将 `proto=RSN` 改为 `proto=WPA`（即降级为 WPA1），但**不推荐**，仅作为最后手段。

#### 3.4 调试完成后，恢复服务
```bash
sudo systemctl start wpa_supplicant
sudo systemctl start dhcpcd
```
（调试模式不会影响系统服务，但建议重启确保一切恢复正常）

---

### 🛠️ 第四步：永久修复（防止重启后复发）

#### 4.1 关闭电源管理（永久）
```bash
sudo nano /etc/rc.local
```
在 `exit 0` 前面加入：
```bash
iwconfig wlan0 power off
```

#### 4.2 在启动时自动重置网卡（解决开机卡死）
同样在 `/etc/rc.local` 的 `exit 0` 前面加入：
```bash
ip link set wlan0 down
ip link set wlan0 up
iwconfig wlan0 txpower on
sleep 2
systemctl restart wpa_supplicant
systemctl restart dhcpcd
```

#### 4.3 内核级禁用省电功能（降低运行时卡死概率）
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

#### 4.4 生效
```bash
sudo chmod +x /etc/rc.local
```
然后**拔掉电源线，等待 10 秒后重新插电**（软重启无效，必须冷启动）。

---

### 🔄 第五步：应急命令（运行时突然断连，无需重启）

```bash
sudo modprobe -r brcmfmac && sudo modprobe brcmfmac && sudo systemctl restart dhcpcd
```

---

### ✅ 第六步：验证修复是否生效
```bash
ip a show wlan0          # 应显示 UP 且有正常 IP
iwconfig wlan0 | grep "Power Management"   # 应为 off
sudo rfkill list         # Soft blocked 应为 no
```

---

以上就是完整的操作汇总，按顺序执行即可。如果以后还遇到问题，直接用应急命令快速恢复。👍