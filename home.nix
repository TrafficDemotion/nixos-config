{ pkgs, inputs, config, ... }:

{
  imports = [ inputs.caelestia-shell.homeManagerModules.default ];

  home.username = "paan";
  home.homeDirectory = "/home/paan";
  home.stateVersion = "26.05";

  programs.home-manager.enable = true;

  # ═══════════════════ 剪贴板历史（Caelestia 的 Super+V）═══════════════════
  # caelestia-cli 的 `caelestia clipboard` 只是 `cliphist list | fuzzel --dmenu`：
  # 它只读历史，不负责往历史里存东西。没有 watcher 时 cliphist 的库永远是空的，
  # Super+V 会弹出一个空列表（看起来像坏了）。这个模块就是官方那个 watcher
  # （wl-paste --watch cliphist store，另有 ... --type image 的那条），
  # 由 home-manager 生成用户服务，不需要自己写脚本。
  services.cliphist.enable = true;

  # ═══════════════════ 桌面外壳：Caelestia ═══════════════════
  # 状态栏 / 通知 / 启动器 / 仪表盘 / 锁屏 / 截图 / 剪贴板 全由它提供，
  # 由 home-manager 生成 systemd 用户服务（caelestia.service），不需要在 hyprland.lua 里 exec。
  # cli.enable 会把 Caelestia CLI 装进 PATH，同时带进它要求的依赖
  # （grim/slurp/swappy/fuzzel/cliphist/gpu-screen-recorder/libnotify 等）。
  programs.caelestia = {
    enable = true;
    cli.enable = true;

    # ── 打在 caelestia-shell 上的本地补丁 ──
    # 外壳的 QML 在 /nix/store 里只读，官方给的唯一覆盖点就是这个 `package`
    # 选项（HM 模块默认 = self.packages.<system>.with-cli）。补丁文件放在
    # patches/caelestia/，和这段 overrideAttrs 必须同版本演进 —— 见 README
    # 「给 Caelestia 打补丁」。改完只重跑「拷文件」那一步（约 8s，不编 C++）。
    #   0001 亮度自愈：一个 DDC 屏都探不到时每 10s 重扫 → 显示器后插/后通电
    #        也能自愈，不必再 `systemctl --user restart caelestia`；
    #        顺带给上游 #1809 的 modelData 判空（拔屏后 TypeError）。
    #   0002 Nexus 壁纸页：壁纸交给 aww 画（background.wallpaperEnabled = false）
    #        时仍显示当前壁纸预览、Wallpapers 按钮不再变灰。
    #   0003 外壳内部 UI 交互音效（C1）：新增单例 services/UiSounds.qml，挂在共享组件上——
    #        StateLayer（所有按钮/条目/图标/tile 的点击）、StyledSwitch（开关）、
    #        FilledSlider + StyledSlider（音量/亮度/媒体滑条）、CustomMouseArea（滚轮）。
    #   0007 锁屏精简：锁屏只留密码框（Content 只留 Center 一栏、Center 删掉时钟/日期/头像，
    #        只留密码框+状态行），上锁/解锁只做 opacity 淡入淡出（LockSurface 的 initAnim/unlockAnim
    #        去掉旋转/缩放/圆角回缩与中心锁图标）。
    #   0008 锁屏密码框：去掉常驻提示「Enter your password」（只去显示、保留量宽，空态密码框
    #        宽度不变；Loading…/Scanning face… 这类瞬时提示照旧显示）。
    # 锚点对不上会**构建失败**（不会静默失效）：升级外壳前先 `nixos-rebuild build`。
    package =
      inputs.caelestia-shell.packages.${pkgs.stdenv.hostPlatform.system}.with-cli
      .overrideAttrs (old: {
        patches =
          (old.patches or [])
          ++ [
            ./patches/caelestia/0001-brightness-selfheal.patch
            ./patches/caelestia/0002-wallpaper-page-usable.patch
            ./patches/caelestia/0003-ui-sounds.patch
            ./patches/caelestia/0004-ui-sounds-events.patch
            ./patches/caelestia/0005-ui-sounds-tab-popout.patch
            ./patches/caelestia/0006-ui-sounds-drawers-wheel.patch
            ./patches/caelestia/0010-ui-sounds-no-throttle.patch
            ./patches/caelestia/0011-ui-sounds-no-popup.patch
            ./patches/caelestia/0012-ui-sounds-launcher-page.patch
            ./patches/caelestia/0007-lock-minimal-fade.patch
            ./patches/caelestia/0008-lock-no-password-hint.patch
          ];
      });

    # ── 第三方壁纸守护进程：awww（就是 swww 改名后的版本）──
    # 水滴式过渡挂在 Caelestia CLI 官方的 wallpaper.postHook 上：每次切壁纸
    # （Nexus/启动器里点、`caelestia wallpaper -f/-r`）都会执行这条命令，并把
    # WALLPAPER_PATH / SCHEME_COLOURS / THUMBNAIL_PATH 作为环境变量传进来。
    # monet 取色不受影响：取色是 `caelestia wallpaper -f` 这个 CLI 自己做的
    # （算完写 state/scheme.json，外壳只读那个文件），跟谁把图铺到屏幕上无关。
    #   --transition-type grow  从一点长出圆（水滴涟漪；outer 是反向收缩）
    #   --transition-pos        圆心，取鼠标位置 → 「点哪就从哪扩散」
    #   --invert-y              它的 y 从底边算，hyprctl cursorpos 从顶边算；
    #                           注意它是**开关**，写 `--invert-y true` 会把 true 当成图片路径报错
    # 注意 postHook 走 shell=True 且 stderr 被丢弃：命令写错不报错，只是没效果。
    cli.settings.wallpaper.postHook = "awww img \"$WALLPAPER_PATH\" --transition-type grow --transition-pos \"$(hyprctl cursorpos | tr -d ' ')\" --invert-y --transition-duration 1 --transition-fps 60";
    # 终端不再接收 CLI 推的 OSC 配色序列（gen_sequences 里写死用 surface ≈ 纯黑，
    # 会把刚换壁纸那一刻开着的终端染黑、抵消模板里 surfaceContainer 的改善）。
    # 关掉后终端配色只认配置文件；代价 = 换壁纸后已开的窗口不即时变，新开才变。
    cli.settings.theme.enableTerm = false;

    # 声明式接管外壳设置 → ~/.config/caelestia/shell.json 由 home-manager 拥有。
    # 代价：在 Caelestia 的图形设置界面里改的东西不会持久化（那文件现在是 store 软链），
    # 要改外壳设置就改这里再 rebuild —— 这正是「一切可回滚复现」的代价与好处。
    settings = {
      # 壁纸交给第三方守护进程 awww 画（2026-09-13）。关掉这个开关后，外壳那个全屏
      # background 层会从 WlrLayer.Background 降到 WlrLayer.Bottom、颜色设成 transparent，
      # 自己的 Wallpaper{} Loader 也不再实例化（Background.qml:22-23 与 :48）——这正是上游
      # 给「用 swww 之类程序接管壁纸」留的口子，层序 background < bottom < 窗口，不会打架。
      # 代价：Nexus 里那个 "Wallpapers" 网格按钮会变灰（WallpaperAndStyle.qml:157 用同一个
      # 开关做 disabled 判据）。壁纸改从启动器搜 wallpapers 换，或 `caelestia wallpaper -f/-r`；
      # 锁屏不受影响（lock/LockSurface.qml 自己渲染 Wallpapers.current）。
      background.wallpaperEnabled = false;
      appearance.transparency.enabled = false; # 想要毛玻璃改 true
      general.apps = {
        terminal = [ "kitty" ];
        explorer = [ "yazi" ];
      };
      # Caelestia 上游默认的 idle 表就是三条：
      #   { timeout = 180; idleAction = "lock"; }
      #   { timeout = 300; idleAction = "dpms off"; returnAction = "dpms on"; }
      #   { timeout = 600; idleAction = ["suspendThenHibernate"]; }   ← 本机必须去掉
      # 第三条是致命项：这是台 PVE 虚机，进 s2idle 后没有唤醒源 = 永久假死（内存不释放、
      # 核显无输出、网络不通，只能在 PVE 控制台硬重启）。所以照抄上游前两条、去掉第三条，
      # 另有 configuration.nix 里的 systemd.sleep 硬闸兜底。
      # 历史：2026-09-11 之前为了"当串流主机时锁屏会让串流断开"把第一条（自动锁屏）删了；
      # 现在这台机器不再当串流主机（见 configuration.nix 里 services.sunshine 那段说明），
      # 自动锁屏已按上游默认恢复。
      general.idle.timeouts = [
        # 空闲 3 分钟自动锁屏（Caelestia 自带锁屏，动一下键鼠就回桌面）。
        { timeout = 180; idleAction = "lock"; }
        # 空闲 5 分钟熄屏。注意：如果屏幕全黑**且键盘没反应**，多半不是熄屏，而是
        # **活动 VT 被切走**（图形会话在 tty1、屏幕却在 tty3 → Hyprland 失去 DRM master
        # 后停止渲染）：按 Ctrl+Alt+F1，或从 ssh 执行 `sudo chvt 1` 恢复。
        # 真熄屏的唤醒方式：hyprctl dispatch 'hl.dsp.dpms({action="on"})'
        { timeout = 300; idleAction = "dpms off"; returnAction = "dpms on"; }
      ];
      services = {
        dataUnits = "Decimal";
        # 24 小时制（Nexus → Language & region → Clock format；上游默认按 locale 猜，这里写死）。
        useTwelveHourClock = false;
        # 所有温度默认摄氏度（2026-09-13 用户要求；Nexus → Language & region → Units 的两栏）。
        #   weatherUnits 管天气温度（上游按 locale 猜测量制，本机虽是公制，显式写出来更稳）；
        #   sensorUnits 管 CPU/GPU 这类系统温度（上游默认本来就是 Celsius，这里同样显式声明）。
        # 枚举值在 JSON 里按名字存（Settings/codecs.hpp 的 EnumCodec → QMetaEnum::keyToValue），
        # 可取值 Celsius / Fahrenheit / Kelvin（enums.hpp 的 TemperatureUnit）。
        weatherUnits = "Celsius";
        sensorUnits = "Celsius";
        # 滚轮/加减步进改成 3%（2026-09-13 用户要求；Nexus → Services → Input increments 的
        # "Volume step" / "Brightness step"，界面显示值就是这两个 ×100 —— 界面上要看到 3）。
        # 消费方：竖栏滚轮（modules/bar/Bar.qml 音量走 Audio.incrementVolume、亮度直接加）、
        # OSD 的 +/- 按钮（modules/osd/Content.qml）、Nexus 滑条两侧加减（SliderRow.qml）。
        audioIncrement = 0.03;
        brightnessIncrement = 0.03;
      };
      # 锁屏背景用壁纸，不要用 screencopy 截屏：本机屏幕是内核 EDID 假负载出来的
      # （叠加 Sunshine 自身还在 screencopy），锁屏时截屏会让 quickshell 的
      # Wayland 连接报 "invalid object" 直接挂掉，Hyprland 随后弹 lockscreen app died。
      # 见 caelestia-dots/shell#1814。视觉上仍是壁纸+模糊，一样好看。
      lock.useWallpaper = true;
      # 顶栏仪表盘弹层精简（2026-09-12 用户要求）：去掉 Dashboard 与 Weather 两个标签页，
      # 只留 Media / Performance。标签页内部的 用户卡/时钟/日历/资源环 上游没有单独开关，
      # 要关必须改 QML（重建 shell），所以这里只做到「关标签页」这一层。
      dashboard.showDashboard = false;
      dashboard.showWeather = false;
      # Performance 标签页也关掉（2026-09-16 用户要求）→ 仪表盘弹层只剩 Media 一个标签页。
      # 同一个键在 Nexus → Dashboard → General 里就是 "Show performance tab"。
      dashboard.showPerformance = false;
      # 主面板时钟显示秒（2026-09-13 用户要求；Nexus → Dashboard → General → "Show clock seconds"）。
      # 它作用的正是上面被关掉的 Dash 标签里的那个时钟（modules/dashboard/dash/DateTime.qml:49,62），
      # 所以这条先写进声明：标签页不开的话暂时看不到效果。
      dashboard.showClockSeconds = true;
      # 左侧竖栏改成非常驻（2026-09-12 用户要求）：Caelestia 1.0 的 bar 是屏幕**左侧竖栏**，
      # 上游默认 bar.persistent=true 会一直显示并占位。设 false 后它平时缩回左边框，鼠标贴到
      # 屏幕最左侧约 10px（= border.thickness）才滑出，鼠标一离开就缩回 —— 和 dashboard /
      # sidebar / utilities 那些贴边面板的手感一致（bar.showOnHover 上游默认 true，不用显式设）。
      # 代价：它不再占位（exclusive zone 退回边框宽度），最大化窗口会一直铺到屏幕左缘，栏滑出时
      # 浮在窗口之上。想临时钉住：把鼠标挪到左边框后按住左键向右拖 >20px（bar.dragThreshold）；
      # 向左拖回则取消钉住。上游没有「点图标切换」或快捷键可切，只有这个拖拽手势。
      bar.persistent = false;
      # 竖栏里的元素清单（2026-09-13 用户要求）：左上角的发行版图标（NixOS 雪花）与竖栏正中的
      # 「当前窗口图标 + 竖排标题」都关掉。两者分别是 entries 里的 logo 与 activeWindow。
      # ⚠️ 这是**整份清单替换上游默认值**，不是逐条覆盖：设置框架里 list 型选项一旦在 JSON 里
      # 出现就整体接管（plugin/src/Caelestia/Settings/listnode.cpp 的 syncJson → setValue("values")，
      # 且被覆盖后的元素不再有 fallback），所以必须把上游默认的九条按原顺序写全，只改 enabled。
      # 上游默认见 plugin/src/Caelestia/Config/barconfig.hpp 的 CONFIG_LIST(EntryList, entries, …)：
      #   logo, workspaces, spacer, activeWindow, spacer, tray, clock, statusIcons, power
      # 两个 spacer 是 Layout.fillHeight（占满剩余空间），作用是把 workspaces 顶在上方、
      # 把 tray/clock/statusIcons/power 压到底部；关掉 activeWindow 后中间那块就空出来。
      # 想恢复某一项：把它那行 enabled 改回 true；想彻底交还给上游默认：整段删掉再 rebuild。
      # 副作用：以后上游若新增/改名条目，这份清单不会自动跟着变（默认清单被覆盖了）。
      bar.entries = [
        { id = "logo"; enabled = false; }
        { id = "workspaces"; enabled = true; }
        { id = "spacer"; enabled = true; }
        { id = "activeWindow"; enabled = false; }
        { id = "spacer"; enabled = true; }
        { id = "tray"; enabled = true; }
        { id = "clock"; enabled = true; }
        { id = "statusIcons"; enabled = true; }
        { id = "power"; enabled = true; }
      ];
      # 工作区指示器显示 12 个（上游默认 5；2026-09-13 先从 5 调到 10，同日再调到 12）—— 就是
      # 竖栏里那串圆角小胶囊，点击/滚轮都作用在它上面。
      # 图形界面里对应 Nexus → Taskbar → Workspaces → "Shown"（1..20），但界面里存不下来（只读）。
      # 注意 hyprland.lua 里的 SUPER+数字 绑定目前只覆盖 1..0 十个：11、12 号工作区只能靠滚轮
      # 或另加绑定（`hl.dsp.focus({ workspace = "e+1" })` 那套）切过去。
      bar.workspaces.shown = 12;
      # ── 2026-09-13 用户要求：Caelestia 图形设置里找得到的这批开关，全部写进声明 ──
      # （Nexus → Taskbar 各子页 / Services / Notifications；键名逐条对应如下）
      # Taskbar → Clock → "Show icon"：关。竖栏时钟只留时间文字，不画时钟图标。
      bar.clock.showIcon = false;
      # Taskbar → Tray → "Background" 与 "Compact"：都开（托盘加底衬、紧凑排布）。
      bar.tray.background = true;
      bar.tray.compact = true;
      # Taskbar → Active window → "Show on hover" 与 "Popout on hover"：都关。
      # 注意 "Popout on hover" 这个开关在界面上属于 Active window 子页，但存的是
      # bar.popouts.activeWindow（BarActiveWindow.qml:44-45），不在 bar.activeWindow 里；
      # 而 activeWindow 这个 entry 本身在 bar.entries 里已是 enabled=false（整块不显示）——
      # 这两条属于「哪天把那个 entry 打开」时的行为声明。
      bar.activeWindow.showOnHover = false;
      bar.popouts.activeWindow = false;
      # Taskbar → Workspaces → 两个装饰开关：Active trail（活动区前拖一条轨迹）与
      # Occupied background（有窗口的工作区加深底色）都开；"Max window icons"（每个工作区最多
      # 画几个窗口图标）从默认 5 改成 3。
      bar.workspaces.activeTrail = true;
      bar.workspaces.occupiedBg = true;
      bar.workspaces.maxWindowIcons = 3;
      # Taskbar → Status icons：加回 Microphone（id 就是 microphone）与 Speakers（id 是 audio）、
      # 去掉 Battery。⚠️ 又是**整份清单替换**（理由同上面的 bar.entries）：按上游默认顺序写全
      # 七项、只翻这三个 enabled。上游默认见 barconfig.hpp 的 CONFIG_LIST(EntryList, statusIcons, …)：
      #   lockStatus(true), audio(false), microphone(false), kbLayout(false), network(true),
      #   bluetooth(true), battery(true)
      bar.statusIcons = [
        { id = "lockStatus"; enabled = true; }
        { id = "audio"; enabled = true; }
        { id = "microphone"; enabled = true; }
        { id = "kbLayout"; enabled = false; }
        { id = "network"; enabled = true; }
        { id = "bluetooth"; enabled = true; }
        { id = "battery"; enabled = false; }
      ];
      # 启动器 fuzzy search 五项全开（2026-09-12）。上游默认五项都是 false（走 fzf 的精确/前缀匹配），
      # 打开后列表改用模糊匹配：apps / actions / schemes / variants / wallpapers。
      # 依据：LauncherPanel.qml 的 "Fuzzy search" 分区就是这五项，写 GlobalConfig.launcher.useFuzzy.*；
      # 列表侧分别在 launcher/services/{Apps,Actions,Schemes,M3Variants}.qml 与 services/Wallpapers.qml
      # 读同一个 key。注意：Nexus 设置界面里点这些开关存不下来（shell.json 是 store 软链只读），
      # 界面里的改动只在当次运行期生效，所以必须写在这里。
      launcher.useFuzzy = {
        apps = true;
        actions = true;
        schemes = true;
        variants = true;
        wallpapers = true;
      };
      # Services → Notifications 页的 Toasts 这批（2026-09-13 用户要求）：
      #   "Show in fullscreen" 选 On —— 存的值是 "all"（界面三项 off / important / all 对应
      #     toastFullscreenValues，见 NotificationsPage.qml:38）；
      #   "Visible toasts" 7 个（utilities.maxToasts，上游默认 4）。
      utilities.toasts.fullscreen = "all";
      utilities.maxToasts = 7;
      # Utilities → Quick toggles：Bluetooth、Microphone（id 是 mic）、Game mode 三个关掉
      # （卡片上不再出现这三个按钮）。⚠️ 第三份**整份清单替换**：按上游默认顺序写全七项，
      # 见 utilitiesconfig.hpp 的 CONFIG_LIST(EntryList, quickToggles, …)：
      #   wifi, bluetooth, mic, settings, gameMode, dnd, vpn(false) —— 只翻那三个 enabled。
      utilities.quickToggles = [
        { id = "wifi"; enabled = true; }
        { id = "bluetooth"; enabled = false; }
        { id = "mic"; enabled = false; }
        { id = "settings"; enabled = true; }
        { id = "gameMode"; enabled = false; }
        { id = "dnd"; enabled = true; }
        { id = "vpn"; enabled = false; }
      ];
    };
  };

  # ═══════════════ 终端：kitty（配色跟随 Caelestia 的壁纸取色）══════════════════
  # 配色不在这里写死，而是由 Caelestia 从当前壁纸现算，渲染到
  #   ~/.local/state/caelestia/theme/kitty.conf
  # 再用 kitty 自己的 include 引进来（settings 里那一行）。整条链路：
  #   模板源文件 /etc/nixos/caelestia/kitty.conf
  #     → HM 复制到 ~/.config/caelestia/templates/kitty.conf（见下面的 xdg.configFile）
  #     → 换壁纸 / `caelestia scheme set` 时，Caelestia 的 CLI 用它自带的
  #       user-template 机制（apply_user_templates）把模板用当前配色重渲染一遍
  #     → kitty 读 include，新开的窗口就是新配色
  # 2026-09-15 调整：模板里背景从 `surface`（M3 tone6 ≈ #131413，接近纯黑）改成
  # `surfaceContainer`（tone12 ≈ #1f201f，色相仍来自壁纸但不再是黑底），
  # 同时把 cli 的 theme.enableTerm 关掉 —— CLI 原本还会往每个终端推一组写死用
  # surface 的 OSC 序列，那会把刚开的窗口瞬间染成纯黑、把这里的改善抵消掉。
  # 代价：换壁纸后已开着的终端不再即时跟随，要新开窗口才看到新配色。
  # 想退回纯静态配色：删掉下面两条 xdg.configFile + 删 ~/.config/caelestia/templates/，
  # 再把 kitty settings 的 include 换成写死的 background/color0..15。
  # ═══════════════════ UI 交互音效素材（pixel） ═══════════════════
  # 音源 = AOSP/LineageOS 的 UI 音（data/sounds/effects/Effect_Tick.ogg，Apache-2.0），
  # 用 ffmpeg 转成 48k 立体声 wav、按事件做了音高/音量区分，落在 ~/.local/share/sfx/
  # （这里声明 → 进 nix store，随 generation 回滚）。播放方 2026-09-13 起基本都在外壳里
  # （patches/caelestia/0003 组件级 + 0004 事件级，pw-play），只有剪贴板/emoji 那两条
  # 键盘触发还在 hypr/hyprland.lua 里（fuzzel 是外部进程，外壳看不到）。
  #   各音的实际参数（源峰值→施加增益→成品峰值）见 README「UI 交互音效」一节。
  xdg.dataFile = {
    "sfx/window-open.wav".source = ./sfx/window-open.wav;
    "sfx/window-close.wav".source = ./sfx/window-close.wav;
    "sfx/workspace-switch.wav".source = ./sfx/workspace-switch.wav;
    "sfx/camera-shutter.wav".source = ./sfx/camera-shutter.wav;
    "sfx/lock.wav".source = ./sfx/lock.wav;
    # C1（外壳内部交互音，见 patches/caelestia/0003-ui-sounds.patch）
    "sfx/ui-click.wav".source = ./sfx/ui-click.wav;
    "sfx/ui-toggle-on.wav".source = ./sfx/ui-toggle-on.wav;
    "sfx/ui-toggle-off.wav".source = ./sfx/ui-toggle-off.wav;
    "sfx/ui-scroll.wav".source = ./sfx/ui-scroll.wav;
    "sfx/ui-open.wav".source = ./sfx/ui-open.wav;
    "sfx/ui-close.wav".source = ./sfx/ui-close.wav;
    # 事件级（patches/caelestia/0004-ui-sounds-events.patch）
    "sfx/unlock.wav".source = ./sfx/unlock.wav;
    "sfx/video-record.wav".source = ./sfx/video-record.wav;
    "sfx/video-stop.wav".source = ./sfx/video-stop.wav;
  };

  # ── 重启外壳时别再连带杀掉它拉起来的应用（2026-09-13 用户要求）──
  # caelestia.service 上游没设 KillMode → 默认 control-group：重启外壳（改 settings、
  # 重装外壳包都会触发）时，从启动器/栏里开出来的 librewolf、kitty 全在它的 cgroup 里，
  # 会被一起 SIGTERM。改成只终止主进程（qs 自己），已开的应用留着。
  systemd.user.services.caelestia.Service.KillMode = "process";



  programs.kitty = {
    enable = true;
    settings = {
      # 字号（2026-09-13 按用户要求调小）：kitty 没有"整体缩放比例"选项，
      # 控制文字大小的就是这个 font_size，默认 11.0 pt → 现在 10.0。
      # 想再调：改这里的数字再 rebuild；临时看效果可在窗口里按 Ctrl+Shift+加/减缩放（不落盘）。
      font_size = 10.0;
      # 光标拖尾（2026-09-12 起，用户要 neovide 那种观感；kitty 没有平滑滑行/粒子，
      # cursor_trail 是官方唯一对应特效）：
      #   300  = 光标在一位停留 >300ms 后的移动才启动拖尾（默认 0 = 关）
      #   decay "0.15 0.6" = 残影最快/最慢衰减秒数（默认 "0.1 0.4"，调大＝拖尾更长）
      #   start_threshold 1 = 横/纵每移动一格都触发（默认 2）
      # 颜色沿用 cursor_trail_color 默认 none ＝ 光标背景色（现在也跟着配色变）
      cursor_trail = 300;
      cursor_trail_decay = "0.15 0.6";
      cursor_trail_start_threshold = 1;
      # 颜色全部来自 Caelestia 渲染出来的那份（链路见上面注释）。
      # 这里已不写任何颜色键，所以不用担心 include 之间的覆盖顺序。
      # kitty 会把 include 的路径做 ~ 展开；文件缺失时只记一条日志、不会报错停用配置。
      include = "~/.local/state/caelestia/theme/kitty.conf";
    };
  };

  # ═══════════════════ 编辑器 GUI 前端：Neovide ═══════════════════
  # neovide 本体来自 configuration.nix 的 systemPackages，这里只声明它的
  # ~/.config/neovide/config.toml（home-manager 的 programs.neovide 模块会把 settings
  # 序列化成 toml；package = null = 不再往用户 profile 里装第二份 neovide）。
  # 2026-09-16 定：窗口尺寸 1600x1000（屏幕 2560x1440）—— 尺寸不在这里配，见下面的说明；
  # 字体跟终端同一套 JetBrainsMono Nerd Font，12pt（上游默认是自带的 Fira Code 14pt，
  # 比 kitty 的 10pt 观感大一截，这里收到接近一档的位置）。
  # ⚠️ 窗口大小【不】在 neovide 里配：0.16.2 的 `--size`（以及 config 的 size）只在窗口映射前
  # 请求一次，Wayland 下会被忽略（实测 --size 400x300 依旧开成 800x600）；`--grid` 则有参数组
  # 冲突 bug 直接退出。所以尺寸写在 hypr/hyprland.lua 的窗口规则 `neovide-size` 里（合成器侧生效）。
  # 「整体缩放比例」也不在这里：它是 nvim 侧的 vim.g.neovide_scale_factor，写在
  # nvim/init.lua 的 Neovide 段（= 1.0，不额外缩放）。
  programs.neovide = {
    enable = true;
    package = null;
    settings = {
      # 字体族 + 字号。注意：neovide 里“控制字体”的官方那项其实是 nvim 的 guifont 选项
      # （见 neovide 文档 Configuration → Font），所以 nvim/init.lua 的 Neovide 段里也写了
      # 一份一模一样的 `vim.o.guifont = "JetBrainsMono Nerd Font:h10"`；这里这份是 nvim 连上
      # 之前用的首屏值（避免先闪一下默认字体）。改字号要两边一起改，或者只留 guifont 那份。
      # 2026-09-16：12pt → 11pt → 10pt（与 kitty 的 10pt 对齐）。
      font = {
        normal = [ "JetBrainsMono Nerd Font" ];
        size = 10.0;
      };
    };
  };

  # ═══════════════════ 编辑器：Neovim ═══════════════════
  # 插件全部来自 nixpkgs（下面的 plugins 列表），没有 lazy.nvim 这类运行时插件管理器：
  # 装插件 = 改列表 + rebuild（不联网拉插件、不在 ~/.local/share/nvim 里落野插件），
  # 卸插件 = 从列表里删掉一行。解析器也一样由 Nix 提供，不做 `:TSInstall` 现编。
  #
  # 配置本体在 /etc/nixos/nvim/init.lua（同目录），initLua 把它读进来生成
  # ~/.config/nvim/init.lua —— 那份是指向 /nix/store 的只读软链，别直接改。
  #
  # EDITOR/VISUAL（= nvim）与 vi/vim 别名由下面三项提供。这几项以前在
  # configuration.nix 的 programs.neovim 里，2026-09-13 挪到这里，跟插件和配置放一起；
  # configuration.nix 的 environment.systemPackages 里仍留着裸 `neovim`，
  # 那样 root/其它用户（含 sudo nvim）也有编辑器可用。
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;

    plugins = with pkgs.vimPlugins; [
      catppuccin-nvim # 颜色主题（Mocha，与 kitty 的配色是同一套）
      lualine-nvim # statusline
      bufferline-nvim # 顶部 buffer 标签栏
      nvim-web-devicons # 上面两个插件的文件类型图标（字体：本机 monospace = JetBrainsMono Nerd Font）
      neo-tree-nvim # 文件浏览器（左侧树）
      plenary-nvim # telescope 的依赖
      telescope-nvim # 查找：文件 / 全文（用 PATH 里的 fd、ripgrep）
      which-key-nvim # 按 <leader> 后弹出可用快捷键
      # Treesitter 的解析器（语法高亮/结构化解析）。nvim 0.12 自带
      # c/lua/vim/vimdoc/query/markdown 的解析器，这里补常用语言。
      (nvim-treesitter.withPlugins (
        p: [
          p.nix
          p.lua
          p.bash
          p.python
          p.json
          p.yaml
          p.toml
          p.markdown
          p.markdown_inline
          p.c
          p.cpp
          p.go
          p.rust
          p.javascript
          p.typescript
          p.html
          p.css
          p.diff
          p.gitignore
          p.regex
          p.vim
          p.vimdoc
          p.query
        ]
      ))
    ];

    initLua = builtins.readFile ./nvim/init.lua;
  };

  # ═══════════════════ 终端文件管理器：yazi / superfile ═══════════════════
  # 两个都声明「默认显示 dotfile」，但机制不一样（原因写在各段注释里）。
  #
  # yazi：上游有正式配置项，段名是 `[mgr]`（25.x 起由 `[manager]` 改名而来；
  # 写成 `[manager]` 不会报错、会被静默忽略 —— dotfile 依旧隐藏，2026-09-13 踩过）。
  # package = null =【不装第二份 yazi】：系统里那份来自 configuration.nix 的
  # environment.systemPackages，这个模块只负责生成 ~/.config/yazi/yazi.toml
  # （yazi 会把它和内置默认值合并，所以只写改动的那一项）。
  # enableZshIntegration 显式关掉：模块默认会往 zsh 里加一个 y 包装函数
  # （退出 yazi 后 cd 到最后浏览的目录），保持 shell 干净；想要就说一声。
  programs.yazi = {
    enable = true;
    package = null;
    enableZshIntegration = false;
    settings.mgr.show_hidden = true;

    # 键位（2026-09-16 用户要求，先大写 N/K → 当日改成小写 n/k）：
    #   n → 在当前目录打开 neovide      k → 在当前目录打开 kitty
    #   h / j / l → 关掉（绑成 noop：yazi 的“空动作”，内部遇到它会直接把这条 chord
    #                    过滤掉，见 yazi-config/src/keymap/chord.rs 的 noop()），
    #                    方向键不受影响，导航照旧。
    # 代价（prepend 会顶掉同键的默认绑定）：小写 n 原本是“跳到下一个搜索结果”、
    # k 原本是“上移一行”——前者没了（搜索后仍可用方向键/`N`… 注意 `N` 现在没绑），
    # 后者本来就被上面的 noop 关掉了。要保留“下一个搜索结果”就换个键或改用 / 里的 <CR>。
    # 为什么不用自己拼路径：yazi 的 shell 命令跑在【当前标签页的 cwd】里
    # （yazi-actor/src/mgr/shell.rs: `let cwd = form.cwd.unwrap_or_else(|| cx.cwd().clone())`），
    # 所以 `neovide .` / `kitty` 天然就是当前目录。
    # --orphan = 脱离 yazi 的任务调度，yazi 退出后窗口不会被连带杀掉。
    keymap.mgr.prepend_keymap = [
      {
        on = "n";
        run = "shell --orphan 'neovide .'";
        desc = "Open Neovide here";
      }
      {
        on = "k";
        run = "shell --orphan 'kitty'";
        desc = "Open kitty here";
      }
      {
        on = "h";
        run = "noop";
      }
      {
        on = "j";
        run = "noop";
      }
      {
        on = "l";
        run = "noop";
      }
    ];
  };

  # superfile（1.3.3）：上游【没有】这个配置项 —— 配置模板里压根没有 hidden/dotfile
  # 相关键，只有一个热键（默认 `.`）用来切换；可见性状态记在数据目录的文件里，
  # 启动时按它决定：~/.local/share/superfile/toggleDotFile，内容就是 true / false。
  # 所以这里直接声明那个状态文件的初始值。
  # 实测：true 时列表里有 .zshrc/.config，false 时没有。
  # 代价：在 superfile 里按 `.` 切换时，这个文件是 /nix/store 只读软链、写不进去
  # （只在 ~/.local/state/superfile/superfile.log 记一条），下次启动仍按声明值
  # = 恒为显示 dotfile。想保留「切一次永久记住」的语义，就把下面这行删掉。
  xdg.dataFile."superfile/toggleDotFile".text = "true";

  # superfile 的配色（2026-09-16）：与 kitty / nvim 同一套链路 —— 模板交给 Caelestia
  # 用当前壁纸现算的配色渲染，渲染结果 ~/.local/state/caelestia/theme/superfile.toml 再
  # 通过一条【出库软链】接到 superfile 自己的主题目录里。为什么必须绕这一下：
  # superfile 只认「~/.config/superfile/theme/<config.toml 里 theme= 的那个名字>.toml」
  # （源码 src/internal/common/load_config.go 的 LoadThemeFile：把 Config.Theme + ".toml"
  # join 到 ThemeFolder 上，不支持绝对路径），而 Caelestia 的渲染输出目录写死在状态目录。
  # mkOutOfStoreSymlink = home-manager 建一条直接指向绝对路径的软链（不进 nix store）；
  # Caelestia 重渲染时是「临时文件 + rename」，路径本身还在，软链不会断。
  # 另一处改动在 superfile 自己生成的用户文件里（不在 Nix 管）：~/.config/superfile/config.toml
  # 的 `theme = 'caelestia'`（原来是 'catppuccin'）。
  # 回滚：删掉下面这条 + 把 config.toml 改回 'catppuccin' 即可（模板文件留着无害）。
  xdg.configFile."superfile/theme/caelestia.toml".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.local/state/caelestia/theme/superfile.toml";

  # ═══════════════════ 浏览器：LibreWolf ═══════════════════
  # 包从 configuration.nix 挪到这里，跟 profile / 自定义 CSS / 设置一起由 home-manager 管。
  #
  # 这个 profile 分两层，别混淆：
  #   * 声明层（进 /nix/store，随 generation 回滚）：settings → profile 的 user.js、
  #     userChrome → chrome/userChrome.css、profiles.ini 与 profile 名，全由本文件生成。
  #     代价：settings 里的项每次启动强制生效（about:config 改不动），要改就改这里再 rebuild。
  #   * 数据层（不可声明、不随回滚、要自己备份）：cookies、登录态、tab/session、
  #     扩展本体与扩展数据、书签密码等，是 ~/.librewolf/default/ 里的普通文件，
  #     2026-09-11 从 Windows 侧 LibreWolf 155 挑选后搬来（只搬数据，没搬缓存/遥测）。
  #     备份做法：tar 一份 ~/.librewolf/default 即可（没有 nix 层面的自动回滚兜底）。
  #
  # 用 nixpkgs-unstable 的包：26.05 稳定版是 154，而 Windows 那份 profile 是 155 写的，
  # 版本降级会触发 places/cookies 的「数据库来自更新版本」保护（书签历史直接不可用、
  # cookies 有被弃用的风险），所以直接对齐 Windows 的 155.0.1-1。
  programs.librewolf = {
    enable = true;
    package = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.librewolf;

    profiles.default = {
      id = 0;
      isDefault = true;

      settings = {
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true; # 让下面的 userChrome 生效
        "browser.startup.homepage" = "https://google.com";
        "browser.startup.page" = 3; # 启动恢复上次会话（tab 全靠这条）
        # 崩溃/异常退出（VM 重启、被 kill）后也自动恢复会话，而不是默默丢掉。
        # 原 profile 里这条是 false（Firefox/LibreWolf 默认），后果是：只要上次不是"点关闭
        # 正常退出"，recovery.jsonlz4 就一直躺在那儿没人用，打开就是空窗口。
        "browser.sessionstore.resume_from_crash" = true;
        "browser.sessionstore.max_tabs_undo" = 9999;
        "browser.sessionstore.restore_on_demand" = true;
        "browser.sessionstore.restore_tabs_lazily" = true;
        "browser.tabs.warnOnClose" = true;
        "browser.sessionstore.warnOnQuit" = true;
        "browser.warnOnQuit" = true;
        "browser.warnOnQuitShortcut" = true;
        # 顶部工具栏的自定义布局（Firefox 的 browser.uiCustomization.state）。
        # 2026-09-12 从 ~/.librewolf/default/prefs.js 读出后固化在这里。
        # 代价（和别的 settings 一样）：以后在界面上拖按钮/加弹簧，下次启动会被这条声明覆盖回去；
        # 想改布局就改完告我一声（或自己改这里）再 rebuild。
        "browser.uiCustomization.state" = ''
          {
            "currentVersion": 26,
            "dirtyAreaCache": [
              "nav-bar",
              "vertical-tabs",
              "PersonalToolbar",
              "TabsToolbar",
              "widget-overflow-fixed-list",
              "unified-extensions-area",
              "toolbar-menubar"
            ],
            "newElementCount": 135,
            "placements": {
              "PersonalToolbar": [],
              "TabsToolbar": [
                "tabbrowser-tabs",
                "new-tab-button"
              ],
              "nav-bar": [
                "sidebar-button",
                "personal-bookmarks",
                "customizableui-special-spring123",
                "customizableui-special-spring124",
                "customizableui-special-spring130",
                "customizableui-special-spring132",
                "customizableui-special-spring133",
                "urlbar-container",
                "customizableui-special-spring131",
                "customizableui-special-spring129",
                "customizableui-special-spring128",
                "customizableui-special-spring127",
                "customizableui-special-spring126",
                "customizableui-special-spring125",
                "_testpilot-containers-browser-action",
                "developer-button",
                "unified-extensions-button",
                "vertical-spacer",
                "forward-button",
                "back-button"
              ],
              "toolbar-menubar": [
                "menubar-items"
              ],
              "unified-extensions-area": [
                "mozilla_cc3_internetdownloadmanager_com-browser-action",
                "chrome-mask_overengineer_dev-browser-action",
                "firefox_ghostery_com-browser-action",
                "_3c078156-979c-498b-8990-85f7987dd929_-browser-action",
                "gemini-voyager_nagi-ovo-browser-action",
                "_74145f27-f039-47ce-a470-a662b129930a_-browser-action",
                "adguardadblocker_adguard_com-browser-action",
                "_3c6bf0cc-3ae2-42fb-9993-0d33104fdcaf_-browser-action",
                "sponsorblocker_ajay_app-browser-action",
                "_5efceaa7-f3a2-4e59-a54b-85319448e305_-browser-action",
                "ublock0_raymondhill_net-browser-action",
                "firefox_tampermonkey_net-browser-action",
                "_a6c4a591-f1b2-4f03-b3ff-767e5bedf4e7_-browser-action",
                "canvasblocker_kkapsner_de-browser-action",
                "jid1-5fs7itlscuazbgwr_jetpack-browser-action",
                "_9ce99d37-4a5e-409a-a04b-0f3f50491bc7_-browser-action",
                "newtaboverride_agenedia_com-browser-action",
                "_36bdf805-c6f2-4f41-94d2-9b646342c1dc_-browser-action",
                "_c3c10168-4186-445c-9c5b-63f12b8e2c87_-browser-action",
                "_a4c4eda4-fb84-4a84-b4a1-f7c1cbf2a1ad_-browser-action",
                "_762f9885-5a13-4abd-9c77-433dcd38b8fd_-browser-action",
                "_b9acf540-acba-11e1-8ccb-001fd0e08bd4_-browser-action",
                "_62e31096-34e6-4503-8806-3d7a6004a1f4_-browser-action",
                "treestyletab_piro_sakura_ne_jp-browser-action",
                "_446900e4-71c2-419f-a6a7-df9c091e268b_-browser-action",
                "minyt_example_org-browser-action",
                "danabok16_gmail_com-browser-action",
                "_5cce4ab5-3d47-41b9-af5e-8203eea05245_-browser-action",
                "_531906d3-e22f-4a6c-a102-8057b88a1a63_-browser-action",
                "_7a7a4a92-a2a0-41d1-9fd7-1e92480d612d_-browser-action",
                "_e58d3966-3d76-4cd9-8552-1582fbc800c1_-browser-action",
                "jid1-zadieub7xozojw_jetpack-browser-action",
                "tab-session-manager_sienori-browser-action",
                "_60f82f00-9ad5-4de5-b31c-b16a47c51558_-browser-action",
                "_a8f7e9c2-4d3b-4a1e-9f8c-7b6d5e4a3c2b_-browser-action"
              ],
              "vertical-tabs": [],
              "widget-overflow-fixed-list": [
                "firefox-view-button",
                "privatebrowsing-button",
                "save-page-button",
                "import-button",
                "downloads-button",
                "fxa-toolbar-menu-button"
              ]
            },
            "seen": [
              "developer-button",
              "screenshot-button",
              "fxms-bmb-button",
              "adguardadblocker_adguard_com-browser-action",
              "_9ce99d37-4a5e-409a-a04b-0f3f50491bc7_-browser-action",
              "mozilla_cc3_internetdownloadmanager_com-browser-action",
              "firefox_tampermonkey_net-browser-action",
              "jid1-5fs7itlscuazbgwr_jetpack-browser-action",
              "newtaboverride_agenedia_com-browser-action",
              "_5efceaa7-f3a2-4e59-a54b-85319448e305_-browser-action",
              "_a6c4a591-f1b2-4f03-b3ff-767e5bedf4e7_-browser-action",
              "canvasblocker_kkapsner_de-browser-action",
              "_36bdf805-c6f2-4f41-94d2-9b646342c1dc_-browser-action",
              "_c3c10168-4186-445c-9c5b-63f12b8e2c87_-browser-action",
              "_a4c4eda4-fb84-4a84-b4a1-f7c1cbf2a1ad_-browser-action",
              "_762f9885-5a13-4abd-9c77-433dcd38b8fd_-browser-action",
              "_b9acf540-acba-11e1-8ccb-001fd0e08bd4_-browser-action",
              "sponsorblocker_ajay_app-browser-action",
              "_3c6bf0cc-3ae2-42fb-9993-0d33104fdcaf_-browser-action",
              "_62e31096-34e6-4503-8806-3d7a6004a1f4_-browser-action",
              "minyt_example_org-browser-action",
              "danabok16_gmail_com-browser-action",
              "_5cce4ab5-3d47-41b9-af5e-8203eea05245_-browser-action",
              "_446900e4-71c2-419f-a6a7-df9c091e268b_-browser-action",
              "_f4961478-ac79-4a18-87e9-d2fb8c0442c4_-browser-action",
              "gemini-voyager_nagi-ovo-browser-action",
              "_74145f27-f039-47ce-a470-a662b129930a_-browser-action",
              "_testpilot-containers-browser-action",
              "treestyletab_piro_sakura_ne_jp-browser-action",
              "_3c078156-979c-498b-8990-85f7987dd929_-browser-action",
              "ublock0_raymondhill_net-browser-action",
              "firefox_ghostery_com-browser-action",
              "_531906d3-e22f-4a6c-a102-8057b88a1a63_-browser-action",
              "_7a7a4a92-a2a0-41d1-9fd7-1e92480d612d_-browser-action",
              "_e58d3966-3d76-4cd9-8552-1582fbc800c1_-browser-action",
              "chrome-mask_overengineer_dev-browser-action",
              "jid1-zadieub7xozojw_jetpack-browser-action",
              "tab-session-manager_sienori-browser-action",
              "simple-tab-groups_drive4ik-browser-action",
              "reset-pbm-toolbar-button",
              "ai-window-toggle",
              "_60f82f00-9ad5-4de5-b31c-b16a47c51558_-browser-action",
              "_a8f7e9c2-4d3b-4a1e-9f8c-7b6d5e4a3c2b_-browser-action"
            ]
          }'';
        # LibreWolf 的 mozilla.cfg 里默认 dom.security.https_only_mode.upgrade_local=true：
        # HTTPS-Only 连「本地/私网地址」也升级成 https。内网服务（Hermes WebUI
        # http://192.168.2.120:30433、PVE 8006、OpenClash 面板 9090/3000…）全是明文 HTTP，
        # 被升级后只会拿到 SSL_ERROR_RX_RECORD_TOO_LONG。关掉「升级本地地址」，公网照旧保护。
        "dom.security.https_only_mode.upgrade_local" = false;
        "intl.locale.requested" = "en-US,zh-CN";
        "font.name.sans-serif.zh-CN" = "JetBrainsMono Nerd Font Propo";
        "font.size.variable.x-western" = 14;
      };

      # 从 Windows profile 原样搬来的自定义 CSS（放在 flake 里 → 改了就 rebuild）。
      userChrome = builtins.readFile ./librewolf/userChrome.css;
    };
  };

  # ═══════════════════ 用户级软件包 ═══════════════════
  home.packages = with pkgs; [
    hyprpolkitagent # polkit 认证弹窗（Caelestia 不带）
    qt6Packages.fcitx5-configtool # 输入法设置界面
    # 注：早期自己拼 shell 时装的 networkmanagerapplet（托盘网络图标）已于 2026-09-16 删掉 ——
    # 竖栏的网络状态图标（statusIcons 里的 network）与 Wi-Fi 面板是 Caelestia 自己实现的。

    # Caelestia CLI 的外部依赖：这些在 Nix 里只是它构建时的 buildInputs，
    # 不会自动进用户 profile，必须显式装上，否则剪贴板/截图/录屏/重启外壳都会失效。
    quickshell # 提供 `qs`（外壳的 kill / ipc）
    fuzzel # 剪贴板、emoji 选择器
    cliphist # 剪贴板历史
    swappy # 截图编辑器
    libnotify # notify-send
    psmisc # killall
    grim
    slurp
    wl-clipboard
    hyprpicker # 取色器
    gpu-screen-recorder # caelestia record
    # 壁纸守护进程（原 swww，nixpkgs 里已改名为 awww），由 hyprland.lua 的 hyprland.start
    # 里 exec 拉起；外壳自己不再画壁纸，理由与过渡命令见上面 cli.settings.wallpaper.postHook。
    awww
    moonlight-qt # Moonlight 客户端：串流 Windows 主机上的 Sunshine
    ddcutil # 外接显示器亮度（DDC/CI）：Caelestia 亮度条/亮度键的后端；
            # 缺了它外壳会静默回退到 brightnessctl，而本机根本没有背光设备

    # 视频 → 彩色 ASCII 动效（anifetch，包定义见 flake.nix 里的同名输入）。
    # 它运行时靠 PATH 找 chafa 渲帧、ffmpeg/ffprobe 抽帧、ffplay 放音，fastfetch 本机已有；
    # chafa 不在 Nix 的传递依赖里（只进了闭包、没进 PATH），必须显式装上，
    # 否则启动就报 "chafa rendering failed"。
    inputs.anifetch.packages.${pkgs.stdenv.hostPlatform.system}.default
    chafa
  ];

  # ═══════════════════ 桌面配置（软链进 ~/.config）═══════════════════
  # Hyprland 0.55 起配置用 Lua：~/.config/hypr/hyprland.lua
  xdg.configFile."hypr/hyprland.lua".source = ./hypr/hyprland.lua;
  # Caelestia 的「用户模板」：~/.config/caelestia/templates/ 下的每个文件都会被
  # Caelestia 的 CLI 在换壁纸/换配色时用当前配色重渲染一遍，写到
  # ~/.local/state/caelestia/theme/<同名文件>。这里用 HM 声明这两份模板的副本
  # （真正的渲染是 Caelestia 自己做的，没有自造脚本；样式与颜色名见两个源文件里的注释）：
  #   kitty.conf                → kitty 的 include 目标（终端配色）
  #   catppuccin-overrides.lua  → nvim 的 color_overrides（编辑器配色）
  #   superfile.toml            → superfile 的主题文件（文件管理器配色，见上面 superfile 段）
  xdg.configFile."caelestia/templates/kitty.conf".source = ./caelestia/kitty.conf;
  xdg.configFile."caelestia/templates/catppuccin-overrides.lua".source = ./caelestia/catppuccin-overrides.lua;
  xdg.configFile."caelestia/templates/superfile.toml".source = ./caelestia/superfile.toml;
  # 注：fuzzel（Super+V 的剪贴板列表 / Super+. 的 emoji 列表）不需要我们自己接模板 ——
  # Caelestia CLI 的 utils/theme.py:apply_fuzzel() 每次换配色都会用它的内置模板重写
  # ~/.config/fuzzel/fuzzel.ini（颜色取自当前壁纸调色板）。自己再声明一份会跟它打架
  # （实测：CLI 的 atomic_write 会覆盖 HM 建的软链）。2026-09-16 试过后撤掉了。

  # ═══════════════════ 会话环境变量 ═══════════════════
  home.sessionVariables = {
    LIBVA_DRIVER_NAME = "iHD"; # Intel 核显 VA-API
    NIXOS_OZONE_WL = "1";
    ELECTRON_OZONE_PLATFORM_HINT = "auto";
    MOZ_ENABLE_WAYLAND = "1";
    QT_QPA_PLATFORM = "wayland;xcb";
    GDK_BACKEND = "wayland,x11";
  };

  # ═══════════════════ 光标主题（Windows 11 / Jepri，「candy」深色小号）═══════════════════
  # 主题本体**不进 nix store、不进这个公开仓库**：包自带的 Agreement.txt 明确禁止再分发
  # （"You're NOT allowed to Distribute the pack files in any way"），所以转换后的 xcursor
  # 主题以本机资产形式放在 ~/.local/share/icons/W11-dark-candy-small/，重建配方见 README
  # 「光标主题」一节（换机器/重装要照它重做一次）。
  # 被找到靠 XCURSOR_PATH（/etc/set-environment 里已含 $HOME/.local/share/icons）；
  # 用哪个名字由 hypr/hyprland.lua 的 hl.env("XCURSOR_THEME"/"HYPRCURSOR_THEME") 指定。
  # 这里补的是 GTK/X11 那一路：它们读 gsettings(dconf)，不看环境变量。
  # （HM 的开关叫 `dconf.enable`，默认就开；系统侧 `programs.dconf.enable` 已在 configuration.nix 打开。）
  dconf.settings."org/gnome/desktop/interface" = {
    cursor-theme = "W11-dark-candy-small";
    cursor-size = 32;
  };

  # ═══════════════════ zsh ═══════════════════
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    history = {
      size = 10000;
      save = 10000;
      share = true;
    };
    initContent = ''
      zsh-newuser-install() { :; }
      # 开终端先播 anifetch 动效：它自己会把 fastfetch 的信息渲在 ASCII 动效右边，
      # 所以有它就不再单独跑 fastfetch。只在「交互式 + 真终端」里播；
      # 脚本、非交互 shell、非 TTY（ssh 带命令、管道等）一律退回纯 fastfetch。
      # 想临时跳过动画：ANI_OFF=1 zsh
      if [[ -o interactive && -t 1 && -z $ANI_OFF ]] && command -v anifetch >/dev/null 2>&1; then
        anifetch example.mp4 --loop 1
      elif command -v fastfetch >/dev/null 2>&1; then
        fastfetch
      fi
      if command -v zoxide >/dev/null 2>&1; then
        eval "$(zoxide init zsh)"
      fi
      source ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme
      [[ -r $HOME/.p10k.zsh ]] && source $HOME/.p10k.zsh
    '';
  };

  home.file.".p10k.zsh".source = ./p10k.zsh;
}
