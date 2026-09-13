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
- **推送闸门**：`git-hooks/pre-push` 扫描本次推送涉及的文件里有没有密钥形态
  （PEM / OpenSSH 私钥块、GitHub 与 Cloudflare 的 token 前缀、AWS 访问键、age 私钥），命中即中止推送；
  仓库是 public，这一步不能省。确切的模式串见 `git-hooks/pre-push` 里的 `patterns`。hooks 不入库，新克隆后要重装：

  ```bash
  sudo install -m 755 /etc/nixos/git-hooks/pre-push /etc/nixos/.git/hooks/pre-push
  ```

  确认是误报时可应急放行：`sudo git -C /etc/nixos push --no-verify`。

恢复：`git clone https://github.com/TrafficDemotion/nixos-config` 到 `/etc/nixos`
（先备份原文件），新机器重建时 `hardware-configuration.nix` 要按本机重生成。

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
6. **外接屏亮度**要 `hardware.i2c.enable` + `ddcutil`（本机没有 `/sys/class/backlight`）；
   检测只在外壳启动那一刻跑一次，显示器断电时启动 → 亮度条静默失效，
   把显示器接回并通电后 `systemctl --user restart caelestia`。
7. **改 Caelestia settings 会重启外壳**，连带把它 cgroup 里的 librewolf/kitty 一起杀掉；
   动手前 `hyprctl layers | grep session-lock` 确认没锁屏。

## 桌面约定

- 窗口**默认浮动**（自由拖动、不铺满平铺格）：`hypr/hyprland.lua` 里的 `float-all` 规则；全屏用 SUPER+F。
- 拖动 / 缩放窗口：SUPER+左键 / SUPER+右键，或 ALT+左键 / ALT+右键。
- 单按 Win 键 = 启动器；SUPER+K 仪表盘；SUPER+L 锁屏；Ctrl+Alt+Del 电源菜单。
- 终端 kitty 配色跟随壁纸（Caelestia 用户模板渲染，`caelestia/kitty.conf`），
  Neovim 同理（`caelestia/catppuccin-overrides.lua`）。
