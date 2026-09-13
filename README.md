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
