# /etc/nixos —— 这台机器的 NixOS 配置

一切都在这里声明：改配置 → rebuild → 不满意就回滚上一代。
没有手写的辅助脚本、没有手工 `ln -s`、没有「改完就忘」的临时状态。

## 布局

| 文件 | 作用 |
| --- | --- |
| `flake.nix` | 入口：钉住 nixpkgs / home-manager / caelestia-shell 的 revision（见 `flake.lock`） |
| `configuration.nix` | 系统级：内核与显卡直通、软件假负载、网络、用户、SDDM、Sunshine |
| `home.nix` | 用户级（paan）：软件包、kitty 配色、Caelestia 外壳设置、zsh |
| `hypr/hyprland.lua` | Hyprland 0.55 Lua 配置（窗口默认浮动）→ `~/.config/hypr/hyprland.lua` |
| `nvim/init.lua` | Neovim 配置 → `~/.config/nvim/init.lua`（只读软链） |
| `caelestia/` | 跟随壁纸取色的模板（kitty 配色 / catppuccin overrides）→ `~/.config/caelestia/templates/` |
| `librewolf/userChrome.css` | LibreWolf 界面定制（`programs.librewolf.userChrome`） |
| `edid/aoc-q24g50f.bin` | 显示器的真实 EDID（软件假负载）→ 系统固件目录 |
| `pkgs/sunshine.nix` | vendored 的 Sunshine 包定义（nixpkgs 自带的版本会泄漏 dma-buf） |
| `patches/caelestia/*.patch` | 打在 caelestia-shell 上的本地补丁（见「给 Caelestia 打补丁」一节） |
| `sfx/*.wav` | UI 交互音效素材（AOSP 的 Effect_Tick 转出）→ `~/.local/share/sfx/` |
| `p10k.zsh` | powerlevel10k 配置 → `~/.p10k.zsh` |
| `hardware-configuration.nix` | `nixos-generate-config` 生成，不要手改 |

## 常用命令

```bash
sudo nixos-rebuild switch --flake /etc/nixos#nixos     # 应用改动
sudo nixos-rebuild test   --flake /etc/nixos#nixos     # 只试不写 boot 项
sudo nixos-rebuild switch --rollback                   # 回滚上一代（或开机菜单里选旧代）
sudo nixos-rebuild list-generations                    # 看历史
sudo nix flake update --flake /etc/nixos               # 升级 nixpkgs / home-manager / caelestia
```

改 `hypr/`、`home.nix` 之后必须 rebuild（这些文件在 Nix store 里、只读）。
`~/.config/caelestia/shell.json` 也由 home-manager 生成 → 在 Caelestia 图形设置界面里改的东西
不会持久化，外壳设置请改 `home.nix` 的 `programs.caelestia.settings`。

## 备份到 GitHub

公开仓库：<https://github.com/TrafficDemotion/nixos-config>（`origin` / `main`）。
`/etc/nixos` 本身就是仓库，改完直接提交推送：

```bash
sudo git -C /etc/nixos add -A
sudo git -C /etc/nixos commit -m "改了什么、为什么"
sudo git -C /etc/nixos push
```

- 认证走**部署密钥** `/root/.ssh/id_ed25519_github`（只对这一个仓库有写权限，不是账号级 token）；
  `/root/.ssh/config` 把 `github.com` 指到 `ssh.github.com:443` —— 本机 22 端口被代理挡掉。
- `.gitignore` 排除 `result` / `result-*` 符号链与 `*.bak-*`、`*.hm-backup` 本地回滚副本
  （版本历史交给 git，不再堆 `.bak` 文件）。
- **git 仓库会改变 nix 的求值行为**（实测）：
  - nix 只把 **git 已跟踪**的文件算作 flake 源码 —— 新建的配置文件/补丁在 `git add` 之前，
    `nixos-rebuild` 根本看不到它（`/nix/store/…-source` 里没有）。所以「加了文件却不 rebuild 生效」
    先查 `git status`。`warning: Git tree '/etc/nixos' is dirty` 是正常提示（改动未提交）。
  - nix 对 git 仓库路径做**属主检查**：非属主用户（paan）直接 `nix eval /etc/nixos#…` 会报
    `repository path '/etc/nixos' is not owned by current user (libgit2 error code = 7)`。
    已由 `configuration.nix` 里的 `programs.git.config.safe.directory = [ "/etc/nixos" ]`
    （写进 `/etc/gitconfig`）修掉；root / `sudo nixos-rebuild` 本来就不受影响。
- **推送闸门**：`git-hooks/pre-push` 扫描本次推送涉及的文件里有没有密钥形态
  （PEM / OpenSSH 私钥块、GitHub 与 Cloudflare 的 token 前缀、AWS 访问键、age 私钥），命中即中止推送；
  仓库是 public，这一步不能省。确切的模式串见 `git-hooks/pre-push` 里的 `patterns`。hooks 不入库，新克隆后要重装：

  ```bash
  sudo install -m 755 /etc/nixos/git-hooks/pre-push /etc/nixos/.git/hooks/pre-push
  ```

  确认是误报时可应急放行：`sudo git -C /etc/nixos push --no-verify`。

恢复：`git clone https://github.com/TrafficDemotion/nixos-config` 到 `/etc/nixos`
（先备份原文件），新机器重建时 `hardware-configuration.nix` 要按本机重生成。

## 给 Caelestia 打补丁（已实施）

外壳的 QML 在 `/nix/store/…-caelestia-shell-1.0.0/share/caelestia-shell/` 里只读，官方给的唯一
覆盖点是 home-manager 的 `programs.caelestia.package`（`types.package`）。所以「打补丁」= 在
`home.nix` 里把这个包换成打了补丁的版本：

```nix
programs.caelestia.package =
  inputs.caelestia-shell.packages.${pkgs.stdenv.hostPlatform.system}.with-cli  # HM 模块的默认就是它
  .overrideAttrs (old: {
    patches =
      (old.patches or [])
      ++ [
        ./patches/caelestia/0001-brightness-selfheal.patch
        ./patches/caelestia/0002-wallpaper-page-usable.patch
      ];
  });
```

### 当前补丁清单（针对 caelestia-shell 1.0.0）

| 补丁 | 改的文件 | 作用 |
| --- | --- | --- |
| `0001-brightness-selfheal.patch` | `services/Brightness.qml` | 一个 DDC 屏都探不到时每 10s 重扫 → 显示器后插/后通电**自愈**，不用再 `systemctl --user restart caelestia`；顺带给上游 #1809 的 `modelData` 判空（拔屏后 `TypeError: Cannot read property 'name' of null`） |
| `0002-wallpaper-page-usable.patch` | `modules/nexus/pages/WallpaperAndStyle.qml` | 壁纸交给 aww 画（`background.wallpaperEnabled = false`）时，Nexus 里仍显示当前壁纸预览、Wallpapers 按钮不再变灰（否则这个页面只能看不能改） |
| `0003-ui-sounds.patch` | `components/StateLayer.qml`、`controls/StyledSwitch.qml`、`FilledSlider.qml`、`StyledSlider.qml`、`CustomMouseArea.qml`、`services/UiSounds.qml`（新增） | 外壳内部交互音（C1）：挂在共享组件上，一次覆盖所有点击/开关/滑条/滚轮 |
| `0004-ui-sounds-events.patch` | `services/{UiSounds,Hypr,Recorder}.qml`、`components/ScreenState.qml`、`modules/areapicker/AreaPicker.qml`、`modules/lock/Lock.qml` | 事件级音效：开/关窗、切工作区、抽屉/面板开合、截图快门、锁/解锁、录屏起停 |
| `0005-ui-sounds-tab-popout.patch` | `services/UiSounds.qml`、`components/{ScreenState.qml,controls/CustomMouseArea.qml}`、`modules/dashboard/Tabs.qml`、`modules/bar/popouts/PopoutState.qml` | dashboard 切页只在真的换页时响一声；竖栏 popout 打开出声 |
| `0006-ui-sounds-drawers-wheel.patch` | `modules/drawers/Interactions.qml`、`modules/bar/popouts/PopoutState.qml`、`services/UiSounds.qml` | 抽屉整层滚轮不再空响（只在鼠标确实在竖栏上滚时出声）；popout 收起补一声 |
| `0007-lock-minimal-fade.patch` | `modules/lock/{Content,Center,LockSurface}.qml` | 锁屏只留密码框（删掉三栏内容与那个大面板、贴屏幕底部）+ 上锁/解锁只做淡入淡出（见下面「锁屏精简」一节） |

**验收手法（都不依赖肉眼看屏幕）**：

```bash
# 1) 补丁是否真的落进构建产物：应只有那两个文件 differ
OUT=$(nix-store -q --outputs /nix/store/*-caelestia-shell-1.0.0.drv | tail -1)
diff -rq /nix/store/vjg2d2f55dds0cbysw6ppn542scd9wlk-caelestia-shell-1.0.0/share/caelestia-shell \
         $OUT/share/caelestia-shell

# 2) 亮度自愈（可离线复现「外壳启动时显示器断电」）
sudo setfacl -m u:paan:--- /dev/i2c-4          # 让 ddcutil 探不到任何 DDC 屏
systemctl --user restart caelestia             # 在故障态下启动
caelestia-shell ipc call brightness get        # ≈0（走本机没装的 brightnessctl）
journalctl --user -u caelestia -n 20 | grep ddcutil   # 每 10s 一条 EACCES = 重扫在跑
sudo setfacl -m u:paan:rw- /dev/i2c-4          # 恢复访问，不发信号、不重启
sleep 12; caelestia-shell ipc call brightness get     # 自己回到显示器真值（= ddcutil -b 4 getvcp 10）
```

**补丁就放在这一个仓库里**（`patches/caelestia/0001-xxx.patch` + `home.nix` 里那段 `overrideAttrs`），不另开仓库：

- nix 只把 **git 已跟踪**的文件算进 flake 源码（见上一节），补丁必须与被求值的 flake 同树；
  分出去就得再加一个 flake input、多一份 lock 与版本漂移，维护量只增不减。
- 补丁只有配合 flake/HM 里那段 `overrideAttrs` 才有意义，两者必须同版本演进 —— 拆成两个仓库
  只会制造「改了 A 忘了 B」。恢复时也是克隆一个仓库就够。
- 只有要把补丁发布给别人复用（或提上游 PR）时才值得拆出去。

**升级外壳的固定流程**（补丁失配要**构建失败**，不许静默失效）：

```bash
sudo nix flake update --flake /etc/nixos                     # 只在这步才会动外壳版本
sudo nixos-rebuild build --flake /etc/nixos#nixos            # 只构建不切换：失配在这里爆，外壳不重启
# 按报错修 patches/ 里的锚点，然后
sudo nixos-rebuild switch --flake /etc/nixos#nixos
```

实测（2026-09-13 首次落地，两个补丁一起）：只改 QML 时重建的是「拷文件」那一步 ——
`nixos-rebuild build` 全程 **21.8s**（含求值与 HM 生成），不编 C++。锚点对不上时失败在
`patchPhase`，报 `patch: **** malformed patch` / `… does not apply`，构建直接中止、外壳不重启。
注意 `caelestia-shell` 的 flake.lock 把 rev 钉死了，所以补丁不会因为「NixOS 更新」自己失效，
只会在你主动 `nix flake update` 那一刻需要复核。

**加新补丁的标准动作**：在 `patches/caelestia/` 放一张 `git diff` 风格的补丁（`-p1` 可应用，
路径形如 `a/services/…`），追加到 `home.nix` 的 `patches` 列表里 → `sudo git -C /etc/nixos add -A`
（**不做这步 nix 看不到文件**）→ `nixos-rebuild build` 验证 → `switch`。

## UI 交互音效（全部由外壳 QML 补丁负责，Lua 只剩两条）

外壳 Caelestia 自己**没有任何音效接口**（assets 里只有壁纸/gif/字体/pam，唯一叫 audio 的是音量与
设备管理；上游唯一相关的 PR #1631 未合并），所以「点它自己的按钮出声」只能改 QML（见上一节）。
这里走的是**另一条路**：用 Hyprland 的事件回调在窗口/工作区变化时播声音 —— 纯 config、零补丁。

- 素材：AOSP/LineageOS 的 UI 音 `data/sounds/effects/{Effect_Tick,camera_click,Lock}.ogg`（Apache-2.0），
  转成 48k 立体声 wav，由 `home.nix` 的 `xdg.dataFile` 声明 → `~/.local/share/sfx/`（文件在 nix store 里）。
  五条音与峰值：`window-open` -3dB / `window-close` -6dB / `workspace-switch` -9dB（也用于「打开外壳面板」）/
  `camera-shutter` -5dB / `lock` -5dB。
- 播放：`pw-play`（PipeWire 自带。本机没有 pulseaudio/paplay）。默认 sink 是蓝牙音箱 ROSE SportFeel。
- 挂接分两类：
  - **事件**（Hyprland 自己报的）：`hl.on("window.open" / "window.close" / "workspace.active", …)`，
    回调参数见 `src/config/lua/LuaEventHandler.cpp`（上游）。
  - **键位**：`hl.bind(key, bindSfx("x.wav", hl.dsp.…), opts)` —— `bindSfx` 返回一个函数，先 `pw-play`
    再用官方 API `hl.dispatch(dispatcher)` 派发原动作。实测 `hl.dispatch` 既接受 dispatcher 也接受函数。
    已挂：单按 Win（启动器）、`SUPER+K`（仪表盘）、`SUPER+N`（侧栏）、`Ctrl+Alt+Del`（电源菜单）、
    `SUPER+V`/`SUPER+.`（剪贴板/emoji）、`Print` 与 `SUPER+Shift+S`/`+Alt+S`（截图）、`SUPER+L`（锁屏）。

**延迟（实测，2026-09-13）**：`pw-play` 单次调用墙钟 **112–136 ms**，空闲 4s 后与连发时**完全一样**
（sink 的 `pause-on-idle=false`，所以不是音箱唤醒慢）——这就是「事件已发生、声音慢半拍」的来源，
也是这条路线延迟的下限。连开 5 个窗口的 burst 测试里 **10/10 事件都出了声、无漏无重**，
所以「没响应」基本是这 130ms 的固定延迟 + 音本身只有 ~50ms 容易听漏（峰值已各提 3dB）。

复现素材（任意有 ffmpeg 的机器）：

```bash
B=https://raw.githubusercontent.com/LineageOS/android_frameworks_base/lineage-23.0/data/sounds/effects
curl -sfLO $B/Effect_Tick.ogg; curl -sfLO $B/camera_click.ogg; curl -sfLO $B/Lock.ogg
# 原始音高 / 低一点 / 高一点；下面这套是 2026-09-13「整体 +6 dB（响一倍）」之后的参数。
# 加成后的峰值：开窗/关窗/快门/锁屏/解锁/录屏 = 0 dBFS（每个文件仅 1–9 个样本顶到满刻度，
# 听不出削波）、切工作区/点击 = -3、开关 = -1、滚动 = -11 dB（Effect_Tick 本体只有 31ms）。
ffmpeg -y -i Effect_Tick.ogg   -af "volume=+8.8dB"                        -ar 48000 -ac 2 window-open.wav
ffmpeg -y -i Effect_Tick.ogg   -af "asetrate=44100*0.84,aresample=48000,volume=+6dB" -ar 48000 -ac 2 window-close.wav
ffmpeg -y -i Effect_Tick.ogg   -af "asetrate=44100*1.18,aresample=48000,volume=+6dB" -ar 48000 -ac 2 workspace-switch.wav
ffmpeg -y -i camera_click.ogg  -af "volume=+2.4dB"                        -ar 48000 -ac 2 camera-shutter.wav
ffmpeg -y -i Lock.ogg          -af "volume=+18.2dB"                       -ar 48000 -ac 2 lock.wav
```

> 要整体再响/再轻：**别去改 12 个文件**，一次 `for f in sfx/*.wav; do ffmpeg -i $f -af volume=±NdB …` 重跑
> 一遍再 switch 就行（`~/.local/share/sfx/` 是 store 软链，换文件不用重启外壳）。
> 唯一的天花板是 16-bit 满刻度：峰值已经到 0 dBFS 的那几个（开窗/关窗/快门/锁屏/解锁/录屏）
> 再往上就会削波 —— 想更高就把源改成 32-bit float wav，或反过来把「轻」的那几条再压低一点。
```

同目录其它可用的 AOSP UI 音：`Dock/Undock/Unlock/VideoRecord/VideoStop/KeypressStandard.ogg`。
换味道 = 转一个 wav + 加一行 `xdg.dataFile` + 改 `hyprland.lua` 里的文件名。

**验收（不用听，直接量）**：建一个可抓的 null sink 临时设为默认，录它的 monitor，同时触发事件：

```bash
pw-cli create-node adapter '{ factory.name=support.null-audio-sink node.name=sfxnull media.class=Audio/Sink object.linger=true audio.position=[FL FR] }'
wpctl set-default <null 的 id>
timeout 15 ffmpeg -f pulse -i sfxnull.monitor -t 15 /tmp/cap.wav &
hyprctl dispatch 'hl.dsp.exec_cmd("kitty --class sfxtest -e sleep 8")'  # 开窗 → 应 -6.0dB
hyprctl dispatch "hl.dsp.focus({workspace = 9})"                        # 切工作区 → 应 -12.0dB
```

实测结果（2026-09-13，两轮）：捕获里每段音的峰值/时刻与事件一一对应 ——
第一轮 `2.26s=-6.0`（开窗）、`6.10s / 7.64s=-12.0`（两次切工作区）、`10.37s=-9.0`（关窗）；
提音量后第二轮：`1.63s=-5.0` = **lock.wav**（同一函数里 `hl.dispatch` 的副作用也落到了 /tmp 的标记文件
→ 证明 `bindSfx` 这条路走得通）、`4.13s=-5.0` = camera-shutter、`6.78s=-3.0` = 开窗、`9.85s=-6.0` = 关窗。
事件→出声的时延约 100–140ms（pw-play 起流的时间）。关掉音效：`local sfxEnabled = false` 再 rebuild。

## 重启外壳不再连坐用户应用（KillMode）

`caelestia.service` 上游没写 `KillMode` → 默认 `control-group`：只要外壳重启（改 `settings`、重装外壳包
都会），从启动器/栏里开出来的 librewolf、kitty 全在它的 cgroup 里，会被一起 SIGTERM。已在 `home.nix` 里补
`systemd.user.services.caelestia.Service.KillMode = "process";`（HM 会与模块自带的 Service 段合并）。

实测（2026-09-13）：先记下 `/sys/fs/cgroup$(systemctl --user show caelestia.service -p ControlGroup --value)/cgroup.procs`
里那几个 librewolf PID（196840/196884/196926，都在外壳 cgroup 内），再 `systemctl --user restart caelestia`
→ 外壳换成新 PID 197551，那三个 librewolf **全部存活**。以后改外壳设置不会再关掉你的浏览器/终端。

> 注：`pw-record --target <sink>` 抓不到声音（不会自动连到 sink 的 monitor 口），
> 要录 monitor 就走 `ffmpeg -f pulse -i <sink 名>.monitor`（pipewire-pulse 提供 PA 兼容层）。

### C1：外壳内部交互音（`patches/caelestia/0003-ui-sounds.patch`）

上面那套只覆盖「Hyprland 看得见的」；鼠标点栏上图标、点启动器条目、点开关、拖滑条、滚轮这些
只有外壳自己知道。C1 就是给外壳打 QML 补丁，但**不逐处改**，而是挂在共享组件上：

| 补丁文件 | 覆盖 |
| --- | --- |
| **新增** `services/UiSounds.qml` | 单例：同一音频文件限流（点击 40ms / 开关 60ms / 滑条 90ms）+ `Quickshell.execDetached(["pw-play", …])`；`CAELESTIA_UI_SOUNDS=0` 可整体静音 |
| `components/StateLayer.qml` | **所有走它的点击**——实测 48 个文件：按钮、`bar` 图标（Power…）、popout 条目、启动器条目、utilities 的 tile、锁屏、Nexus、文件对话框 |
| `components/controls/StyledSwitch.qml` | 开关（`Switch` 模板不吃 StateLayer，所以不会和点击音重复） |
| `components/controls/FilledSlider.qml` | OSD 的音量 / 亮度条**拖动** |
| `components/controls/StyledSlider.qml` | 弹出面板 / Nexus / 仪表盘媒体页的滑条 |
| `components/controls/CustomMouseArea.qml` | **滚轮**：音量、亮度、工作区、日历翻页、滚动条 |

素材（`sfx/`，都由 AOSP `Effect_Tick.ogg` 派生，ffmpeg 转 48k 立体声）：
`ui-click` -9dB、`ui-toggle-on` -7dB（音高×1.28）、`ui-toggle-off` -7dB（×0.82）、`ui-scroll` -17dB（×1.42）。

关掉（声明式，一行）：`programs.caelestia.systemd.environment = [ "CAELESTIA_UI_SOUNDS=0" ];` 再 rebuild
（外壳重启一次，`KillMode=process` 已保证不连坐你的应用）。

**验收（不需要点界面）**——把补丁产物里的 `UiSounds.qml` 单独拿出来，用 `qs -p` 驱动一个最小配置：

```bash
mkdir -p /tmp/uisfx-test && cp <新外壳>/share/caelestia-shell/services/UiSounds.qml /tmp/uisfx-test/
cat > /tmp/uisfx-test/shell.qml <<'QML'
import QtQuick
import Quickshell
Scope {
    Timer { interval: 700;  running: true; onTriggered: UiSounds.click() }
    Timer { interval: 1500; running: true; onTriggered: UiSounds.toggle(true) }
    Timer { interval: 2300; running: true; onTriggered: UiSounds.toggle(false) }
    Timer { interval: 3100; running: true; onTriggered: UiSounds.slider() }
    Timer { interval: 4200; running: true; onTriggered: Qt.quit() }
}
QML
# 录 null sink 的 monitor 后 qs -p /tmp/uisfx-test，分析峰值
```

实测（2026-09-13）：
- 默认 → **恰好 4 段**：`1.24s=-9.0`(click)、`2.04s=-7.0`(toggle-on)、`2.86s=-7.0`(toggle-off)、`3.67s=-17.0`(scroll)。
- `CAELESTIA_UI_SOUNDS=0` → **0 段**（开关有效）。
- 用户在真外壳里操作时，捕获里额外出现 -9dB 点击音 → 说明 `StateLayer` 那处补丁在真外壳里确实在响。
- 顺带证明 `Quickshell.execDetached` 能用裸命令名：quickshell 生成进程的 PATH 含
  `/run/current-system/sw/bin`（`command -v pw-play` 命中、`rc=0`）。

**已知缺口**：少数手写 `MouseArea` 的组件没有音——`modules/bar/components/TrayItem.qml`（托盘条目）、
`Clock.qml`、`OsIcon.qml`（启动器入口，已随竖栏精简一起关掉）；面板「打开/关闭」本身没有单独音
（点它的那一下就是音）。延迟与上面的 Hyprland 路线相同（每条音仍起一个 `pw-play`，≈100–140ms 起流）。

### 事件级：把原来挂在 Hyprland Lua 上的音效搬进外壳（`patches/caelestia/0004-ui-sounds-events.patch`）

2026-09-13 第二张补丁。原来 `hypr/hyprland.lua` 里靠 `hl.on(...)` 与 `bindSfx()` 包键位做的事，
只要外壳看得见，就都改由 QML 触发 —— **触发点比键位包一层更宽**（鼠标点、IPC、空闲锁屏、CLI 都算）：

| 声音 | 挂在哪个文件 | 判据 |
|---|---|---|
| 开窗 / 关窗 | `services/Hypr.qml` | `Hyprland.toplevels`（`UntypedObjectModel`）的 `objectInsertedPost` / `objectRemovedPre` |
| 切工作区 | `services/Hypr.qml` | `onFocusedWorkspaceChanged` |
| 面板开合（启动器/仪表盘/电源菜单/侧边栏/右下抽屉/OSD） | `components/ScreenState.qml` | 那 7 个 `property bool` 抽屉布尔值的变化（`bar` 不挂：鼠标一动就变） |
| 截图快门 | `modules/areapicker/AreaPicker.qml` | `activeAsync` 变 true（8 个入口共用：`Print` / Super+Shift+S / +Alt+S 及其 clipboard 变体） |
| 锁屏 / 解锁 | `modules/lock/Lock.qml` | `WlSessionLock.locked` 变化 —— **解锁在 Lua 那套里根本没有事件可挂**，顺带补上了（`sfx/unlock.wav`） |
| 录屏开始 / 结束 | `services/Recorder.qml` | `onRunningChanged` |

配套：
- `services/UiSounds.qml` 增加 `windowOpen/windowClose/workspace/panel/shutter/lockState/record`，
  并加 `playIfQuiet(file, minInterval, quietMs)` —— **面板开合紧跟一次点击音时 250ms 内不再出声**，
  免得「点栏上图标开面板」听成两声。
- 外壳刚启动时 `Hyprland.toplevels` 里已经有一批窗口，会一次性触发 N 个「新窗口」→ 用
  `property bool soundsReady` + 2s `Timer` 把启动那一批吃掉。
- `hypr/hyprland.lua` 相应**瘦身**：`hl.on("window.open"/"window.close"/"workspace.active")` 三条删掉，
  9 条键位的 `bindSfx()` 外壳换成原来的裸 dispatcher。**只留两条**：`SUPER+V`（剪贴板）与
  `SUPER+.`（emoji）—— 它们其实是 `fuzzel --dmenu`（`caelestia clipboard` / `caelestia emoji` 都是
  外部进程），外壳看不到，QML 侧挂不上。

**验收（无需按键，全部实测过）**：null sink 设为默认 + `ffmpeg -f pulse -i <sink>.monitor` 内录，
每个动作打 epoch 时间戳再逐段对峰：

```bash
# 注意 wpctl 里 null sink 的名字列显示成 (null)，就靠它取 id：
pw-cli create-node adapter '{ factory.name=support.null-audio-sink node.name=sfxevt media.class=Audio/Sink object.linger=true audio.position=[FL FR] }'
NODE=$(wpctl status | sed -n 's/.*[^0-9]\([0-9]\{1,\}\)\. *(null).*/\1/p' | head -1)
wpctl set-default $NODE
ffmpeg -v error -y -f pulse -i sfxevt.monitor -t 12 /tmp/evt.wav &
# 动作：开/关一个 kitty；切工作区；caelestia-shell ipc call drawers toggle launcher
# ⚠️ Hyprland 0.55 + Lua 配置下 `hyprctl dispatch workspace 9` 直接报
#    `')' expected near '9'`，必须用 Lua 形式：hyprctl dispatch 'hl.dsp.focus({ workspace = "9" })'
```
实测结果（每个动作**恰好一次**发声，切片峰值与预期文件一一对应）：
切工作区 -9.0 dB ×2、开窗 -3.0 dB、关窗 -6.0 dB、抽屉开/关各 -9.0 dB；
`peak pw-play` 并发数=1（说明旧的 Lua 回调没有残留重复出声）。外壳 journal 无 QML 报错
（只有既有的 PowerProfiles 噪音）。

**没验到的**：截图快门、锁屏/解锁、录屏开始/结束需要真按键或锁屏（会打扰当前会话），
只做了「补丁落进 store + 外壳加载无报错」这一步；要确认就自己按一下
（`Print` / `SUPER+L` / 右下抽屉里的 Record）。

### 修正：dashboard 切页只响一次 + 竖栏 popout 的音（`patches/caelestia/0005-ui-sounds-tab-popout.patch`）

用户反馈两条，根因都是「音挂在滚轮上」而不是挂在「结果」上：

1. **滚轮不生效也响**：dashboard 页签的 `CustomMouseArea.onWheel` 是 `dashboardTab = Math.min/Math.max(…)`
   （带钳位），滚到第一/最后一页时**值没变、滚轮事件照样来**，而音挂在该共享组件的滚轮分支里 → 一直响。
   改法：`components/controls/CustomMouseArea.qml` 新增 `property bool wheelSfx: true`，页签那处设
   `wheelSfx: false`；切页音改挂在**结果**上 —— `components/ScreenState.qml` 的
   `onDashboardTabChanged: UiSounds.page()`（走 `playIfQuiet`，点页签时被点击音压掉，不会两声）。
   于是：真换页 = 1 声，滚到头/没换页 = 0 声。
2. **竖栏 popout 没音**：它们不是点开的 —— `modules/bar/Bar.qml` 的 `checkPopout(y)` 在鼠标移动时按位置
   判定，`popouts.currentName = <icon.name>` + `hasCurrent = true` 就开了。改法：挂
   `modules/bar/popouts/PopoutState.qml` 的 `onHasCurrentChanged`（只在 false→true 出声；用 `hasCurrent`
   而不是 `currentName`，这样在图标之间滑动、托盘项之间滑动都不会重复响）。

验收（不需要按键）：`hyprctl dispatch 'hl.dsp.cursor.move({x=3,y=1310})'` 把光标移到左边栏蓝牙图标上
→ 内录捕获到 **-3.0 dB** 一声，同时 `grim` 截图确认 Bluetooth popout 已弹出。
dashboard 切页那半只能真滚轮验证（Hyprland 不能注入滚轮事件），确认到「补丁进 store + 外壳无报错」为止。

### 再修：抽屉整层滚轮空响 + popout 收起音（`patches/caelestia/0006-ui-sounds-drawers-wheel.patch`）

用户第二次反馈「dashboard 内容页里滚滚轮也一直响、而且没切页」。真凶不在 dashboard：

`modules/drawers/Interactions.qml` 是个**覆盖整个抽屉区的全屏 `CustomMouseArea`**，它的 `onWheel` 只在
`event.x < bar.implicitWidth`（鼠标在竖栏上）时才真的转发给 `bar.handleWheel()`（音量/亮度/切工作区），
别处滚轮**什么也不做** —— 而音效挂在共享组件上，于是全屏范围里滚轮都空响。
改法：这层 `wheelSfx: false`，把出声挪到那个**真的会调东西**的分支里。

第二件：`PopoutState.hasCurrent` 由 true→false（popout 收起）时补一声（`window-close.wav`，-6 dB），
于是竖栏 popout 开/合都有音。

**验收状态（诚实版）**：
- popout **打开**音：有实拍证据 —— 光标移到竖栏蓝牙图标（`hl.dsp.cursor.move({x=3,y=1310})`）时捕获到
  -3.0 dB 一声，`grim` 截图里 Bluetooth popout 确实展开着。
- popout **收起**音与**滚轮**两处：**没能可靠复现**。原因有二：① Hyprland 不能注入滚轮事件，
  滚轮相关的改法只能靠「补丁进 store + 外壳无报错」推断；② 测试时用户本人正在用这台机器，
  我的 `hl.dsp.cursor.move` 和他的真实鼠标操作互相打架，捕获里混进他的点击音（-3 dB 与 popout
  打开音同档，无法区分）。**用光标注入做验收时，先确认用户没在动鼠标**（或改用键盘）
  —— 否则数据不可信。

### 锁屏精简：只留密码框（无面板、贴屏幕底部）+ 只做淡入淡出（`patches/caelestia/0007-lock-minimal-fade.patch`）

诉求：「锁屏能换成第三方吗」「想精简到只有密码框」「上锁/解锁那个锁动画去掉，只留 fade in/out」。

**为什么只能打补丁**：`lock` 的全部配置项只有 `enabled / useWallpaper / recolourLogo / enableFprint /
maxFprintTries / enableHowdy / maxHowdyTries / triggerHowdyOnWake / hideNotifs`
（`plugin/src/Caelestia/Config/lockconfig.hpp`）—— **锁屏界面内容和动画都没有开关**。
也**不要**用 `lock.enabled = false` 当「关掉外壳锁屏」：它只把内容（含密码框）藏起来，背景照旧铺满，
等于把自己锁在门外。

**改了三处**：

| 文件 | 改动 |
| --- | --- |
| `modules/lock/Content.qml` | 上游三栏（左＝天气/系统信息/媒体，右＝资源/通知抽屉）只留 Center 一栏，并给它 `Layout.fillWidth`（`Layout.preferredWidth` 是 `centerWidth`，单留一栏会被摆在左边） |
| `modules/lock/Center.qml` | 删掉 Clock（大字时钟）、日期文本、ProfilePic（头像），只留 PasswordInput + StateMessage（指纹提示/认证失败原因） |
| `modules/lock/LockSurface.qml` | ① 删掉「大面板」`lockContent` + `lockBg`（m3surface 圆角矩形+阴影）+ 中心锁图标 `lockIcon`；剩下的 `Content` 一组宽度取 `centerWidth`、高度由内容撑开，水平居中、`anchors.bottom` 贴屏幕底部、下边距 `Tokens.padding.extraExtraLarge`(48)。② 上锁：上游 `scale 0→1` + `rotation→360` + 锁图标反着转一圈 → 只留 `background`/`content` 的 opacity 淡入（`Anim.StandardLarge` = 600ms）。③ 解锁：上游内容缩到 0、圆角回缩、锁图标淡入、背景淡出 → 只留 `content` 淡出（`Anim.StandardSmall` = 200ms）；末尾 `PropertyAction locked=false` 不变（**先放完动画再解锁**，`ipc call lock unlock` 与 PAM 成功走同一条信号） |

时长 token 取自 `plugin/src/Caelestia/Config/tokens.hpp`：`small 200 / normal 400 / large 600 / extraLarge 1000`。

**实测验收（`hyprctl dispatch 'hl.dsp.global("caelestia:lock")'`，后台连续 `grim` 抓帧）**：

- 上锁：第 2 帧近全黑（15 KB）→ 第 3 帧半透明浮现（686 KB）→ 第 4 帧 840 KB → 稳定帧 845 KB，
  即「整屏 + 密码框一起淡入」；任何一帧都没有倾斜/缩小/旋转的方块（旧实现会看到一个转着放大的锁块）。
- 稳定帧：只有底部居中的密码框，距底边约 100 px（48 是写死的下边距，其余是**空状态行的占位高度**）；
  没有面板/时钟/头像/通知。想更贴底 → 把那个 `Tokens.padding.extraExtraLarge`(48) 改成 `medium`(12) 等。
- 解锁：`ipc call lock unlock` 后连查 `isLocked`，先 `true` 约 1 s 再 `false`（= 解锁被动画挡住），
  外壳 `NRestarts` 仍 0、日志无 `invalid object`。
- **没验到的**：真·PAM 解锁（敲密码）那条路的文案与手感 —— 要自己按一次 SUPER+L 输密码才算。
- 注意：这台机器的图形会话仍是旧的 `QT_IM_MODULE=fcitx`（登录后没重登过），锁屏上可能又出现
  「只能输数字」；**应急 = 在锁屏上按一次 Ctrl+Space**，根治 = 重新登录一次。

**回滚**：`home.nix` 的 patches 列表删掉 0007 那行 → `nixos-rebuild switch`（QML-only，不编 C++）。

## 已知坑

1. **直通核显的显示器检测**：guest 收不到 HPD 中断，开机那一刻没接显示器的输出口一律认不到。
   解决 = 软件假负载（不用买 EDID 假插头）：
   `drm.edid_firmware=HDMI-A-1:edid/aoc-q24g50f.bin` + `video=HDMI-A-1:2560x1440@60e`
   —— 两条必须一起用，单给 EDID 不生效。要点与排查过程见 skill `nixos-hyprland`
   的 `references/software-dummy-plug.md`。
2. **PVE 侧 Display 保持 `none`**：直通核显时再挂 virtio-gpu 会抢主 GPU，VT（Ctrl+Alt+F3）
   跑到看不见的虚拟屏上，greeter 起不来、没有图形会话。
3. **i915 固件**靠 `hardware.enableRedistributableFirmware`，否则 DMC/GuC 一直 `-ENOENT`。
4. **不要开 `networking.wireless`**：与 NetworkManager 冲突。
5. **从源码编译要加 `--max-jobs 1`**：这台 VM 内存小，编 quickshell 时被 OOM 杀过。
6. **外接屏亮度**要 `hardware.i2c.enable` + `ddcutil`（本机没有 `/sys/class/backlight`）。
   上游的 DDC 检测只在外壳启动那一刻与「屏幕列表变化」时跑一次；本机软件假负载让连接器恒
   connected → 列表永不变，所以**显示器断电时启动会让亮度条静默失效**。已由补丁
   `0001-brightness-selfheal.patch` 修掉：一个 DDC 屏都探不到时每 10s 重扫，插回并通电后
   ≤10s 自己恢复（实测：故障态 IPC=0、journal 每 10s 一条 `ddcutil … EACCES`；恢复 i2c 访问后
   12s 内 IPC 回到显示器真值，外壳 PID 不变）。补丁若被回退，兜底仍是
   `systemctl --user restart caelestia`（或 `ddcutil -b 4 setvcp 10 <n>` 临时绕开外壳）。
7. **改 Caelestia settings 会重启外壳**，连带把它 cgroup 里的 librewolf/kitty 一起杀掉；
   动手前 `hyprctl layers | grep session-lock` 确认没锁屏。

## 桌面约定

- 窗口**默认浮动**（自由拖动、不铺满平铺格）：`hypr/hyprland.lua` 里的 `float-all` 规则；全屏用 SUPER+F。
- 拖动 / 缩放窗口：SUPER+左键 / SUPER+右键，或 ALT+左键 / ALT+右键。
- 单按 Win 键 = 启动器；SUPER+K 仪表盘；SUPER+L 锁屏；Ctrl+Alt+Del 电源菜单。
- 终端 kitty 配色跟随壁纸（Caelestia 用户模板渲染，`caelestia/kitty.conf`），
  Neovim 同理（`caelestia/catppuccin-overrides.lua`）。
