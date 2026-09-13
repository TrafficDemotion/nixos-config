# /etc/nixos/configuration.nix —— 系统级配置
#
#   重建：    sudo nixos-rebuild switch --flake /etc/nixos#nixos
#   只试不切：sudo nixos-rebuild test   --flake /etc/nixos#nixos
#   回滚：    sudo nixos-rebuild switch --rollback（或启动菜单里选上一代）
#
# 目录：flake.nix 入口 / configuration.nix 系统 / home.nix 用户（kitty 配色、Caelestia 设置）
#       hypr/hyprland.lua = Hyprland 配置；edid/ = 软件假负载用的显示器 EDID
#       hardware-configuration.nix 自动生成，不要手改

{ config, lib, pkgs, inputs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # Sunshine 用一个本地 vendored 的包定义（./pkgs/sunshine.nix）升到上游
  # v2026.910.221003：nixpkgs 26.05 与 unstable 都还停在 2026.516，而那个版本的
  # wlr 抓屏会以 ~1 GB/min 泄漏 dma-buf 内存（实测：连上客户端约 4 分钟后 guest
  # 内存见底、Hyprland 在 screencopy 路径 SEGV 进 safe mode；停掉 sunshine 进程
  # 内存立刻全回来）。新版含 2026-06 的 wlroots DMA-BUF modifier 修复与后续两个
  # 泄漏修复。用 unstable 的包集来 callPackage，保证 Qt6/cmake 等依赖够新。
  # 回滚：删掉下面这个 overlays 即可回到 nixpkgs 自带的 Sunshine。
  nixpkgs.overlays = [
    (final: prev: {
      sunshine = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.callPackage ./pkgs/sunshine.nix { };
    })
  ];

  # ═══════════════════════ 启动 / 内核 / 硬件 ═══════════════════════

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # 直通的 Intel 核显（Alder Lake-S）不在 initrd 里加载：i915 等真正根分区挂好后再初始化，
  # 这样它就能从系统固件目录读到下面那份 EDID；放 initrd 里的话固件也得跟着塞进 initrd，没必要。
  # 注：这里原本还有 boot.kernelModules = [ "uinput" ]，那是给 Sunshine 造虚拟键鼠用的；
  # 2026-09-11 起 NixOS 不再当串流主机，已删（要恢复的话 Sunshine 的 NixOS 模块自己不加载
  # uinput 模块 —— 得把这行加回来，见下面 services.sunshine 那段注释）。

  # ── 软件假负载（不买 EDID 假插头）────────────────────────────
  # 把实机 AOC Q24G50F 的 EDID 当固件喂给内核，让 i915 认为 HDMI-A-1 上永远接着这台显示器：
  #   * 内核控制台 / SDDM greeter / Hyprland / Sunshine 始终有输出
  #     （不再需要开机后进 tty 手动 start-hyprland，也不用每次手建 headless 虚拟屏）
  #   * 那个口一直对外输出 2560x1440 信号 → 显示器线插上去直接出画面，
  #     不依赖“直通核显的 HPD 中断进不了 guest”这个坑
  # EDID 是从 Windows 侧注册表 dump 出来的真实数据（256 字节，含 CTA 扩展块）。
  boot.kernelParams = [
    "drm.edid_firmware=HDMI-A-1:edid/aoc-q24g50f.bin"
    # video=...e：开机时就把 HDMI-A-1 强制置为「已连接」。
    # 必须两条一起用：连接器处于 disconnected 时 i915 根本不去读 EDID，
    # 那份固件 EDID 就永远轮不到（实测：光有 edid_firmware 时该口状态仍是 disconnected）。
    "video=HDMI-A-1:2560x1440@60e"
  ];
  hardware.firmware = [
    (pkgs.runCommandLocal "edid-aoc-q24g50f" { } ''
      install -Dm644 ${./edid/aoc-q24g50f.bin} $out/lib/firmware/edid/aoc-q24g50f.bin
    '')
  ];

  # 固件（i915 的 DMC/HuC/GuC 等）。不开这个内核会一直报
  # i915/adls_dmc_ver2_01.bin、i915/tgl_guc_70.bin -ENOENT，DMC/GuC 全废。
  hardware.enableRedistributableFirmware = true;

  # 图形栈 + 核显硬件编解码（VA-API / QSV：mpv、Firefox、Sunshine 都用）
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      intel-media-driver # VA-API (iHD)
      vpl-gpu-rt # oneVPL GPU runtime（ADL 及更新）
      intel-compute-runtime # OpenCL
    ];
  };

  services.qemuGuest.enable = true; # QEMU guest agent

  # ── 禁止系统睡眠：VM 里挂起 = 假死 ──────────────────────────
  # PVE 虚拟机进 s2idle 后没有可用的唤醒源，挂起即永久假死：内存不释放、
  # 核显无输出、网络不通，只能在 PVE 控制台硬重启。
  # 2026-09-11 两次卡死都来自 Caelestia 的 idle 挂起（源头已在 home.nix 里去掉），
  # 这里再加一道硬闸：任何来源的 suspend 请求都被拒绝。
  # ── 锁屏：用 Caelestia 自带的（2026-09-11 真因已查明并修复）──────────
  # "每次锁屏必崩" 的原因不是 Caelestia 本身，而是 Hyprland 里的孤儿 ext-session-lock
  # （quickshell issue #1054：上次崩溃时没释放的锁会让之后每次锁屏都 FATAL abort，
  #   而 abort 本身又在制造新孤儿锁 —— 自我强化）。重启一次图形会话清除后即恢复正常。
  # 曾临时用 programs.hyprlock 顶替，它还会连带给 hypridle 装 unit（hypridle 没有
  # ~/.config/hypr/hypridle.conf，启动即 abort），现已移除。
  # ⚠️ 绝不要在锁屏状态下重启 caelestia / display-manager —— 那正是制造孤儿锁的方式。

  systemd.sleep.settings.Sleep = {
    AllowSuspend = "no";
    AllowHibernate = "no";
    AllowSuspendThenHibernate = "no";
    AllowHybridSleep = "no";
  };

  # 机器上没有 swap 设备，加压缩内存交换，避免 OOM
  zramSwap.enable = true;

  # 无磁盘 swap 时 3.8G 内存扛不住从源码编译（quickshell 那次就被 OOM killer 杀了）。
  # 这个 swapfile 是用 `btrfs filesystem mkswapfile --size 8g /swapfile` 建的
  # （btrfs 上正确的建法：nodatacow + 预分配），这里只负责开机启用。
  swapDevices = [ { device = "/swapfile"; } ];

  # btrfs 每月自动 scrub
  services.btrfs.autoScrub = {
    enable = true;
    fileSystems = [ "/" ];
  };

  # ═══════════════════════════ 网络 ═══════════════════════════

  networking.hostName = "nixos";
  networking.networkmanager.enable = true;
  # 不要再开 networking.wireless：那是 wpa_supplicant 直管，和 NetworkManager 抢网卡

  # ═══════════════════════════ 蓝牙 ═══════════════════════════
  # 主板的 Intel AX210 蓝牙是 USB 直通进来的（8087:0032，driver = btusb），
  # 内核开机时已经把固件喂进去了，驱动侧不需要任何配置：
  #   Bluetooth: hci0: Found device firmware: intel/ibt-0041-0041.sfi
  #            → Firmware loaded in 1421612 usecs / Device booted in 24429 usecs
  #   rfkill: 1: hci0: Bluetooth  Soft blocked: no  Hard blocked: no
  # 缺的只是用户态的 BlueZ —— 之前系统里既没有 bluetooth.service 也没有 bluetoothctl。
  hardware.bluetooth = {
    enable = true;
    # 开机就上电，不用每次手动 enable 适配器。
    powerOnBoot = true;
  };
  # 界面用它自带的，不装 blueman 之类的托盘小程序：
  # Caelestia 外壳有蓝牙状态图标 + 点击弹出面板（适配器开关 / 扫描 / 已配对设备连接）
  # 和 Nexus 里的蓝牙页（配对流程），走 Quickshell 的 BlueZ D-Bus 后端。

  # ═══════════════════════ i2c（外接显示器 DDC/CI 亮度） ═══════════════════════
  # 这台机器只有外接 HDMI 显示器，没有任何 /sys/class/backlight 设备，
  # 屏幕亮度只能走 DDC/CI（i2c 总线）。加载 i2c-dev 并把 /dev/i2c-* 授权给
  # i2c 组和本地登录用户（uaccess，由 logind 发 ACL）；
  # 否则节点是 crw------- root root，Caelestia 亮度条拿不到总线，什么都调不了。
  # 对应关系实测：HDMI-A-1 → /dev/i2c-4（i915 gmbus），AOC Q24G50F 支持 MCCS 2.2。
  hardware.i2c.enable = true;

  # ═════════════════ 输入法热键（fcitx5） ═════════════════
  # 用 fcitx5 自带的默认绑定：TriggerKeys=Ctrl+Space（+ Zenkaku_Hankaku / Hangul），
  # AltTriggerKeys=Shift_L，组枚举键 Super+Space / Shift+Super+Space。
  # 2026-09-12 曾把触发键挪到 Ctrl+Alt+Space（让串流到 Windows 时 Ctrl+Space 能透传），
  # 同日按用户要求撤销 —— 不再在 /etc/xdg 里放自定义 config，直接吃 fcitx5 默认值。
  # （如需再改，仍应放 /etc/xdg/fcitx5/config：fcitx5 会原子重写 ~/.config 那份。）

  # ═══════════════════════ 时区 / 语言 / 键盘 ═══════════════════════

  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };
  # 这里同时给 X11（Xwayland）和 Wayland 会话提供默认键盘布局
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # ═════════════════════════ 输入法（fcitx5）═════════════════════════
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5 = {
      addons = with pkgs; [
        qt6Packages.fcitx5-chinese-addons # 中文：拼音 / 双拼 / 五笔 等
        fcitx5-mozc # 日文：Mozc（与上面同一份 fcitx5 core 5.1.19，已验证）
      ];
      # 预置引擎列表（写进 /etc/xdg/fcitx5/profile）。你在 fcitx5 配置工具里的改动会落到
      # ~/.config/fcitx5/，优先级更高，rebuild 不会冲掉。
      settings.inputMethod = {
        "Groups/0" = {
          Name = "Default";
          "Default Layout" = "us";
          DefaultIM = "pinyin";
        };
        "Groups/0/Items/0" = {
          Name = "keyboard-us";
          Layout = "";
        };
        "Groups/0/Items/1" = {
          Name = "pinyin";
          Layout = "";
        };
        "Groups/0/Items/2" = {
          Name = "mozc";
          Layout = "";
        };
      };
    };
  };

  # ═════════════════════════════ 字体 ═════════════════════════════

  fonts = {
    packages = with pkgs; [
      nerd-fonts.jetbrains-mono
      nerd-fonts.symbols-only
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
    ];
    fontconfig.defaultFonts = {
      monospace = [ "JetBrainsMono Nerd Font" ];
      sansSerif = [
        "Noto Sans CJK SC"
        "Noto Sans"
      ];
      emoji = [ "Noto Color Emoji" ];
    };
  };

  # ═════════════════════════════ 用户 ═════════════════════════════

  users.users.paan = {
    isNormalUser = true;
    description = "paan";
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
      "input"
      # 原来还有 "uinput"（Sunshine 造虚拟键鼠用）：2026-09-11 不再当串流主机后去掉，
      # 需要时 Sunshine 的 NixOS 模块会自己建这个组。
    ];
    # 密码仍由 mutableUsers 管（/etc/shadow），不在这里写 hashedPassword
  };
  users.defaultUserShell = pkgs.zsh;
  programs.zsh.enable = true;

  # ══════════════════════════════ Nix ══════════════════════════════

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
  };
  # auto-optimise-store 已过时，改用定时优化任务
  nix.optimise.automatic = true;
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };
  nixpkgs.config.allowUnfree = true;

  # ═════════════════════════ NAS（TrueNAS CIFS）═════════════════════

  fileSystems."/mnt/truenas/DATA" = {
    device = "//192.168.2.120/DATA";
    fsType = "cifs";
    options = [
      "credentials=/etc/samba/truenas-credentials"
      "vers=3.0"
      "uid=1000"
      "gid=100"
      "file_mode=0664"
      "dir_mode=0775"
      "x-systemd.automount"
      "x-systemd.idle-timeout=60"
      "noauto"
      "nofail"
      "_netdev"
    ];
  };
  fileSystems."/mnt/truenas/PICTRUES-MEDIAS" = {
    device = "//192.168.2.120/PICTRUES-MEDIAS";
    fsType = "cifs";
    options = [
      "credentials=/etc/samba/truenas-credentials"
      "vers=3.0"
      "uid=1000"
      "gid=100"
      "file_mode=0664"
      "dir_mode=0775"
      "x-systemd.automount"
      "x-systemd.idle-timeout=60"
      "_netdev"
      "nofail"
    ];
  };

  # ═══════════════════════ 桌面：Hyprland + SDDM ═══════════════════════

  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
    withUWSM = true; # UWSM 管理会话，systemd 集成（graphical-session.target 等）
  };

  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };
  # 默认会话（SDDM 登录界面上的下拉框也仍可临时切换）
  services.displayManager.defaultSession = "hyprland-uwsm";

  # 自动登录：不接显示器时登录界面虽然起得来（HDMI-A-1 是常亮的虚拟输出），但看不见它，
  # 也就没法从 Moonlight 连进来用；开了自动登录，连上就是已登录的桌面。
  services.displayManager.autoLogin = {
    enable = true;
    user = "paan";
  };

  # 注销后自动再登录一次。SDDM 的 Relogin 默认是 false ⇒ 一旦注销（Caelestia 会话菜单
  # 的第一项就是"注销"：点左下角电源图标后弹出的第一个图标，很容易误触）就停在登录
  # 界面/TTY，桌面和所有应用全丢。打开之后，误触注销 ≈ 花 20-30 秒自动回到已登录桌面。
  # 代价：想"真的注销"请用重启/关机（那两项菜单里也有），或临时把这个选项改回 false。
  services.displayManager.sddm.autoLogin.relogin = true;

  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config = {
      common.default = [ "gtk" ];
      hyprland.default = [
        "hyprland"
        "gtk"
      ];
    };
  };

  programs.dconf.enable = true;
  security.polkit.enable = true;

  # UPower：Caelestia 外壳要从它读电池/电源信息，没有这个服务时每次启动都会报
  # `Could not launch service org.freedesktop.UPower`（2026-09-11 在日志里看到的）。
  # 这台是虚机、没有电池，装了也只是让外壳不再报错、电源相关面板显示为空。
  services.upower.enable = true;

  # ════════════════════════════ 音频 ════════════════════════════

  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  # 这里原来有一条给 Sunshine 用的 udev 规则（/dev/uinput、/dev/uhid 授权给 uinput 组）：
  # Sunshine 以用户级服务运行、拿不到 cap，所以靠 uaccess 给当前会话授权。
  # 2026-09-11 不再当串流主机后删掉了 —— 留着反而有害：uinput 组随 Sunshine 模块一起没了，
  # 规则里的 GROUP="uinput" 会指向不存在的组。要恢复串流主机，`services.sunshine.enable = true`
  # 就够（那个模块自己会建 uinput 组并加同样的规则）。

  # 说明：这里曾经有两个兜底单元（display-manager-hotplug.service 与
  # display-manager-hotplug-retry.timer），用于「核显没有活动输出 → 核显 greeter 秒死」时
  # 把显示管理器重新拉起来。2026-09-10 起改用软件假负载（drm.edid_firmware +
  # video=HDMI-A-1:2560x1440@60e，见本文件上方），核显的输出始终存在，greeter 不会再死，
  # 这两个单元与对应的 udev 规则已删除。

  # ═══════════════════════ 串流（2026-09-11 起关闭）═══════════════════════
  # 这台机器不再当串流**主机**：主力用法是在 NixOS 上开 Moonlight 客户端去连
  # Windows 的 Sunshine（那个方向一直很好用，且与主机无关）。Sunshine 当主机用的
  # 那几个"让渡"因此全部作废 —— 自动锁屏回来了（见 home.nix 的 idle 表）、
  # 不用再为"锁屏时串流会断"留后果。
  # 关掉它还实打实省资源：Sunshine 常驻约 0.3 GB RSS + i915 GEM/Shmem 占用，
  # 而 guest 总共只有 6 GiB（这是台 PVE 虚机，内存很紧）。
  # 恢复方法（把下面三行加回来即可；包定义与 overlay 都还留着，见 ./pkgs/sunshine.nix
  # 与上面的 nixpkgs.overlays —— 那份是 vendored 的新版 Sunshine v2026.910，
  # 因为 nixpkgs 自带的 2026.516 的 wlr 抓屏会以 ~1 GB/min 泄漏 dma-buf 内存）：
  #   services.sunshine = {
  #     enable = true;                     # 模块自带 uinput 组 + udev 授权规则
  #     settings.capture = "wlr";          # 官方文档推荐给 Hyprland
  #     settings.address_family = "both";  # 同时也监听 IPv6
  #   };
  # 另外 shell 层要补一处：本机 /dev/uinput 的 uinput 内核模块曾在
  # boot.kernelModules 里显式加载（已删），恢复 Sunshine 时把它加回来。
  # ⚠️ 另外两条实战经验（2026-09-11 用 5 次配对实验换来的，恢复时省得再踩）：
  #   * 配对要用前台 `sunshine -0 <conf>`（PIN 从 stdin 读）绕开 WebUI 的 CSRF 问题，
  #     而且**一次失败的配对会把 host 卡死** —— 之后新的配对请求它连 PIN 提示都不出，
  #     必须重启那个前台实例；所以配对时别留失败尝试。
  #   * 客户端要让它走 **IPv4**：Sunshine 开着 IPv6 监听时 avahi 会广播 ULA，
  #     Moonlight 会优先挑 ULA，而实测同一次配对走 IPv4 成功、走 ULA 失败
  #     （IPv6 侧的 serverinfo 是通的，问题出在配对流程）。

  # ═══════════════════════ SSH / 安全 ═══════════════════════

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = true;
    };
  };

  # paan 免密 sudo（wheel 组）
  security.sudo.wheelNeedsPassword = false;

  # ═══════════════════════ 系统软件 ═══════════════════════

  environment.systemPackages = with pkgs; [
    # 基础工具
    wget
    curl
    unzip
    p7zip
    ripgrep
    fd
    fzf
    gnumake
    gcc
    git
    cifs-utils
    trash-cli
    # 诊断（这次排查要用的：lspci / lsusb / vainfo / intel_gpu_top）
    pciutils
    usbutils
    dmidecode
    libva-utils
    intel-gpu-tools
    # 终端 / 编辑器
    neovim
    neovide
    btop
    zoxide
    yazi
    superfile
    lazygit
    lazydocker
    fastfetch
    # 媒体 / 图形
    ffmpeg
    exiftool
    yt-dlp
    obs-studio
    moonlight
    # 浏览器：Firefox 换成 LibreWolf（2026-09-11）。同源（Gecko），
    # 但默认去掉了遥测、赞助内容和"研究"组件，隐私默认值更接近"配置好的 Firefox"。
    # 包本体由 home.nix 的 programs.librewolf 管（这样能和 profile / userChrome / 设置
    # 一起声明、一起回滚；配置目录仍是 ~/.librewolf/，跟 Firefox 的 ~/.mozilla 互不干扰）。
    tor-browser
    tor
    # Wayland / Hyprland 生态
    kitty
    waybar
    rofi
    dunst
    wl-clipboard
    grim
    slurp
    xdg-utils
  ];

  # Neovim 的声明挪到了 home.nix 的 programs.neovim（插件 + init.lua 属于用户侧配置，
  # 2026-09-13 迁移）；这里只留 environment.systemPackages 里的裸 `neovim`，
  # 让 root/其它用户仍然有个能用的编辑器（paan 自己 PATH 里是 home-manager 那份带插件的包装版）。
  #
  # EDITOR/VISUAL 仍在这里给全套环境（含图形会话）声明：原来由 programs.neovim.defaultEditor
  # 提供，模块被删后只剩 home-manager 的 shell 侧变量，而图形会话只吃 /etc/set-environment，
  # 不吃 home-manager 的 hm-session-vars.sh，所以显式写这两行补回来。
  environment.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };

  # 这个值决定 NixOS 兼容的数据格式版本，安装后不要改
  system.stateVersion = "26.05";
}
