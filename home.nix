{ pkgs, inputs, config, ... }:

let
  # ── Neovim 插件清单（交给 lazy.nvim 加载，见 programs.neovim 那段的说明）──
  # 这里只写【要直接用的】插件本体；各插件自己的依赖（nixpkgs 放在
  # passthru.dependencies 里 —— 例：neo-tree-nvim → plenary.nvim / nui.nvim，
  # nvim-treesitter.withPlugins → 解析器）由下面生成 lua spec 的那段递归摊平后
  # 一并交给 lazy，不用在这里重复列。
  nvimPlugins = with pkgs.vimPlugins; [
    catppuccin-nvim # 颜色主题（Mocha，与 kitty 的配色是同一套）
    lualine-nvim # statusline
    bufferline-nvim # 顶部 buffer 标签栏
    nvim-web-devicons # 上面两个插件的文件类型图标（字体：本机 monospace = JetBrainsMono Nerd Font）
    neo-tree-nvim # 文件浏览器（左侧树）
    plenary-nvim # telescope 的依赖
    telescope-nvim # 查找：文件 / 全文（用 PATH 里的 fd、ripgrep）
    which-key-nvim # 按 <leader> 后弹出可用快捷键
    nvim-autopairs # 括号/引号自动配对（setup 在 init.lua 里，全用上游默认值）
    # 缩进对齐线（上游 lukas-reineke/indent-blankline.nvim，v3，模块名 ibl）；
    # 开关与颜色写在 nvim/init.lua 的 require("ibl").setup 与 apply_custom_hl 两处。
    indent-blankline-nvim
    # 会话记忆（上游 resession.nvim）：记住「每次打开时的 split 布局」。
    # 选它而不是 auto-session：resession 是显式 API，我们要的语义是
    # 「不带参数启动才自动恢复当前目录的会话；带文件参数就照旧只开那个文件 + 树」，
    # 见 nvim/init.lua 里 resession 那一段。插件本体仍来自 nixpkgs，不下载不更新。
    resession-nvim
    # 右侧代码缩略图（上游 Isrothy/neominimap.nvim）：nixpkgs（连 nixpkgs-unstable）里都没有
    # 这个插件，所以用本地 vendored 的包定义 ./pkgs/neominimap.nix（buildVimPlugin + 钉住
    # 上游 tag）。配置在 nvim/init.lua 的 vim.g.neominimap 那段（必须在 lazy.setup 之前设）。
    (pkgs.callPackage ./pkgs/neominimap.nix { })
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
in
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
  # extraOptions 默认只带 -max-dedupe-search 10，所以从启动器里点「较旧」的条目时，
  # 复制回去的内容会被当成新条目再存一条（看着像「多出一条重复」）—— 调到 500（= max-items）
  # 让整个历史范围都去重。
  services.cliphist = {
    enable = true;
    extraOptions = [ "-max-dedupe-search" "500" "-max-items" "500" ];
  };

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
            #   0013 启动器里内置剪贴板 / emoji 列表：Super+V / Super+. 不再弹 fuzzel
            #        窗口，而是以 clipboard / emoji 模式打开启动器（数据仍来自
            #        cliphist 与 `caelestia emoji`）。
            ./patches/caelestia/0013-launcher-clipboard-emoji.patch
            #   0014 剪贴板面板顺序（接 0013）：Quickshell 的 Variants 只按「值第一次出现」排序，
            #        模型里新出现的值一律追加到末尾，所以「再复制一次某条」会把那条顶到列表最
            #        底部。这里按 cliphist list 的原始顺序重排 instances（原因见补丁内注释）。
            ./patches/caelestia/0014-launcher-clipboard-order.patch
            #   0015 Nexus 设置界面：删掉 Panels / Apps / Services / Language & region 四页的
            #        导航项与对应组件 —— 这四页编辑的全是 shell.json 的键（bar/dashboard/
            #        launcher/sidebar/utilities、general.apps、services.*、nexus.*），而本机
            #        shell.json 由 HM 托管成只读软链，在这四页里改东西只会弹 Failed to save
            #        config。两个数组（PageRegistry.pages / PageCompRegistry.pageComps）按下标
            #        一一对应，必须同删；删的是下标 6..9，0..3 不动（bar popout 的映射依赖它）。
            ./patches/caelestia/0015-nexus-hide-shell-pages.patch
            #   0016 Nexus 设置界面：删掉 NavPane 上那个「Search settings」搜索框 ——
            #        上游没实现设置搜索，它只写 NexusState.searchOpen 而那个属性全外壳
            #        没有消费者，输入什么都不会发生。
            ./patches/caelestia/0016-nexus-no-search-bar.patch
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

  # ── Waydroid 会话自启动（2026-09-22 用户要求）──
  # Android 容器那一半是系统服务（waydroid-container.service，NixOS 模块已 enable），
  # 但「会话」那一半是用户级的：不写这条就得每次手动 `waydroid session start`。
  # 挂在 graphical-session.target 上 —— 本机是 uwsm 会话，实测该 target 是 active
  # （`systemctl --user list-units --type=target | grep graphical`），而且 uwsm 把
  # WAYLAND_DISPLAY=wayland-1 / XDG_RUNTIME_DIR 导进了 systemd user 环境
  # （`systemctl --user show-environment` 可见），所以 waydroid 连得上合成器。
  # UI 不自动弹（要不要看随你）：需要时点启动器里的 "Waydroid"（包自带 Waydroid.desktop）
  # 或跑 `waydroid show-full-ui`。
  systemd.user.services.waydroid-session = {
    Unit = {
      Description = "Waydroid session (Android container session)";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.waydroid-nftables}/bin/waydroid session start";
      Restart = "on-failure";
      RestartSec = 5;
      # Android 的 lcd density。waydroid 在 session 启动时这样算
      # （`tools/actions/session_manager.py:73-80`）：先问**宿主**的 `ro.sf.lcd_density`
      # —— 宿主是 NixOS，没有 getprop，得到空串 → 落到 `GRID_UNIT_PX` 环境变量，
      # **dpi = GRID_UNIT_PX × 20** → 都没有才写 "0" 让 Android 自己决定。
      # 8 × 20 = 160 dpi。为什么要 160：Android 的输出分辨率必须**等于窗口尺寸**
      # （见 hyprland.lua 里 waydroid-pixel7-size 那条规则 —— 窗口比分辨率小是「裁剪」不是
      # 缩放，实测 405x900 的窗口配 1080x2400 只显示左上角一块），现在的组合是
      # 分辨率 405x900 + 窗口 405x900；160dpi 下 1dp = 1px ⇒ 逻辑宽度 405dp，
      # Pixel 7（panther）是 411dp（1080px / 420dpi × 160），手机布局观感一致。
      # ⚠️ 别走 `persist.waydroid.lcd_density` 那个 prop —— 实测设了也不会被读，生效的仍是 ro.sf.lcd_density。
      Environment = [ "GRID_UNIT_PX=8" ];
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };



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
      # 右侧缩略图（neominimap）画的是盲文点阵 U+2800–U+28FF，而 JetBrainsMono Nerd Font
      # 里没有这个区段（实测 fc-list ":charset=2800" 只有 DejaVu Sans / DejaVu Serif /
      # FreeMono / Unifont 这几族）→ 用 symbol_map 把这一段显式指给等宽的 FreeMono，
      # 否则缩略图会是一排豆腐块。FreeMono 来自系统已装的 GNU FreeFont，不需要装新包。
      symbol_map = "U+2800-U+28FF FreeMono";
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
      # 2026-09-17：加上第二项 FreeMono —— 逗号列表就是 neovide 的字体回退链
      # （Primary, Fallback1…，见它文档 Configuration → Font），给右侧缩略图
      # （neominimap）的盲文点阵 U+2800–U+28FF 兜底；与 nvim/init.lua 里那行
      # guifont 保持一致（两处注释都写了，改的时候一起改）。
      font = {
        normal = [
          "JetBrainsMono Nerd Font"
          "FreeMono"
        ];
        size = 10.0;
      };
    };
  };

  # ═══════════════════ 编辑器：Neovim ═══════════════════
  # 插件来源 = nixpkgs（文件顶部 let 里的 nvimPlugins 列表），**加载**交给 lazy.nvim：
  # Nix 侧把这些插件的路径生成成一份 lua spec（下面那段 xdg.configFile），
  # init.lua 里 `require("lazy").setup(require("nix-plugins"), {...})` 读它。也就是：
  #   * 插件本体仍在 /nix/store —— 离线可用、随 flake.lock 可重现、不做 :TSInstall 现编；
  #   * lazy 只负责加载/开关、提供 :Lazy 与 :Lazy profile 界面，不下载也不更新
  #     （每条 spec 都带 dir = <store 路径>，lazy 视为「已安装」）。
  # 装插件 = 往顶部的 nvimPlugins 列表加一项 + rebuild；
  # 卸插件 = 从列表里删掉一行（不联网拉插件、不在 ~/.local/share/nvim 里落野插件）。
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

    # 这里只放 lazy.nvim 本体：它必须先于其它插件出现在 runtimepath 上，
    # 由 home-manager 直接铺进 packpath（~/.local/share/nvim/site/pack/hm/start），
    # 所以不需要官方文档里那段 `git clone` 的 bootstrap（本机也不让编辑器联网拉插件）。
    # 其余插件都在顶部的 nvimPlugins 列表里，由 lazy 按下面生成的 spec 加载。
    plugins = [ pkgs.vimPlugins.lazy-nvim ];

    initLua = builtins.readFile ./nvim/init.lua;
  };

  # ── lazy.nvim 的插件清单（由 Nix 生成，别手改）────────────────────────────
  # 每条 = { name, dir = <store 路径>, lazy = false }：
  #   * dir 指向 /nix/store 里的插件本体 → lazy 认为它「已安装」，不下载不更新
  #     （在 :Lazy 面板里归到本地那种，没有 install/update 动作）；
  #   * lazy = false = 启动即加载，跟改造前（全部由 packpath 自动加载）行为一致。
  #     想改成按事件/文件类型懒加载：光改这里的 lazy 不够，还得把 init.lua 里那个
  #     插件的 require(...).setup 一起挪进它的 config 回调，否则 require 找不到模块。
  # 依赖（passthru.dependencies，递归）在这里摊平 —— lazy 只认 spec 里出现过的路径，
  # 不像 home-manager 的 plugins 那样会自动带上依赖（少一个 nui，neo-tree 就直接
  # 报「模块找不到」）。
  xdg.configFile."nvim/lua/nix-plugins.lua".text =
    let
      lib = pkgs.lib;

      # 依赖闭包：自己在前、依赖在后，按 store 路径去重（用路径比较，避免深比较 attrset）
      add =
        seen: p:
        let
          path = toString p;
        in
        if builtins.any (x: toString x == path) seen then
          seen
        else
          builtins.foldl' add (seen ++ [ p ]) (p.dependencies or []);

      # lazy 面板里显示的名字 = derivation 的 pname 去掉 nixpkgs 的 "vimplugin-" 前缀
      # （vimplugin-nvim-autopairs → nvim-autopairs）。少数没有 pname 的（treesitter 的
      # queries 那批）退回目录名，并把开头的 32 位 store 哈希剪掉。
      luaName =
        p:
        let
          raw = p.pname or (baseNameOf (toString p));
        in
        lib.removePrefix "vimplugin-" (
          if builtins.match "[0-9a-z]{32}-.*" raw != null then
            lib.removePrefix "${builtins.head (lib.splitString "-" raw)}-" raw
          else
            raw
        );

      entry =
        p:
        let
          name = luaName p;
        in
        ''
          {
            name = "${name}",
            dir = "${toString p}",
            lazy = false,${
              lib.optionalString (name == "catppuccin-nvim") " -- 主题要最先加载\n            priority = 1000,"
            }
          },'';
    in
    ''
      -- ⚠️ 本文件由 home.nix 生成，不要手改：改 home.nix 顶部的 nvimPlugins 列表后 rebuild。
      -- 每个字段的含义见 home.nix 里生成这一段的那段注释。
      return {
      ${lib.concatMapStrings entry (builtins.foldl' add [] nvimPlugins)}
      }
    '';

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

    # 「默认打开的文本编辑器」= 上游 [opener] edit 那一条（打开文本/代码文件、空文件时用它）。
    # 上游默认 = `${EDITOR:-vi} %s` 且 block = true（把主屏让给终端里的 nvim）；
    # 2026-09-16 按用户要求改成 GUI 的 neovide：orphan = true（不阻塞 yazi，yazi 退出后
    # 窗口仍在），不用 block。
    # 为什么写一条就等于整条替换：yazi 的配置是 deserialize-over 混入，而 Opener 是 HashMap，
    # 同名键是整份覆盖而不是逐条追加（yazi-shim/src/toml/traits.rs 的
    # HashMap::deserialize_over_with 直接 insert）——所以这里只会剩下面这一条。
    # 注意 `*/` 那条文件夹规则用的第一个名字也是 edit（use = [ "edit", "open", "reveal" ]），
    # 所以「对文件夹按 Enter / 选编辑」也会走 neovide（和之前走 nvim 是同一个位置）。
    settings = {
      mgr.show_hidden = true;
      opener.edit = [
        {
          run = "neovide %s";
          desc = "Neovide";
          orphan = true;
          for = "unix";
        }
      ];
    };

    # 键位（2026-09-16）：
    #   h / j / k / l → 全部关掉（绑成 noop：yazi 的“空动作”，内部遇到它会直接把这条
    #                    chord 过滤掉，见 yazi-config/src/keymap/chord.rs 的 noop()）。
    #   后果：vim 那套字母导航全没了，导航改走这些（都是 yazi 预设、未被覆盖）：
    #     上/下移动 = <Up> / <Down>
    #     进目录     = <Enter> 或 <Right>      出目录 = <Left>
    #     历史前进/后退 = H / L（大写，与 hjkl 无关）
    #     翻页/首尾 = <PageUp>/<PageDown>、gg / G
    # 同一天还试过 n → 在当前目录开 neovide、k → 开 kitty，随后按用户要求撤掉 ——
    # 撤掉后 n 恢复 yazi 默认（跳到下一个搜索结果）；k 现在又被上面这条 noop 接管。
    # 想加回某个 shell 动作就在下面列表里补一条（prepend 会顶掉同键的默认绑定）：
    #   { on = "n"; run = "shell --orphan 'neovide .'"; desc = "Open Neovide here"; }
    # 顺带记着这种命令为什么不必自己拼路径：yazi 的 shell 命令跑在【当前标签页的 cwd】里
    # （yazi-actor/src/mgr/shell.rs: `let cwd = form.cwd.unwrap_or_else(|| cx.cwd().clone())`）。
    keymap.mgr.prepend_keymap = [
      {
        on = "h";
        run = "noop";
      }
      {
        on = "j";
        run = "noop";
      }
      {
        on = "k";
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

  # ═══════════ 默认应用（XDG：文件管理器 / 终端 / 浏览器）＋ 隐藏条目 ═══════════
  # 生效层级：~/.config/mimeapps.list（XDG_CONFIG_HOME，由本文件生成）优先于
  # /etc/xdg/mimeapps.list 与各 XDG_DATA_DIRS 里的 mimeinfo.cache —— 所以「系统默认」
  # 在这里声明就够，不用动 NixOS 的 xdg.mime。
  #
  # 文件管理器 = yazi：nixpkgs 的 yazi 自带 yazi.desktop
  # （Exec=yazi %f, Terminal=true, MimeType=inode/directory），不必自己造 desktop 条目。
  # 改之前 inode/directory 落到了 kitty-open.desktop（kitty 的 desktop 文件也声明了这个 MIME）。
  # 浏览器 = librewolf.desktop（HM 装的那份，在 /etc/profiles/per-user/paan/share/applications）。
  # 终端另有专门约定 x-scheme-handler/terminal；更通用的那条见下面的 terminal-exec。
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "inode/directory" = [ "yazi.desktop" ];
      "text/html" = [ "librewolf.desktop" ];
      "x-scheme-handler/http" = [ "librewolf.desktop" ];
      "x-scheme-handler/https" = [ "librewolf.desktop" ];
      "x-scheme-handler/terminal" = [ "kitty.desktop" ];
    };
  };

  # 默认终端（xdg-terminal-exec，freedesktop 的 Default Terminal Execution 提案）：
  # HM 的官方模块会装 xdg-terminal-exec 本体 + 写 ~/.config/xdg-terminals.list。
  # Terminal=true 的 desktop 条目（比如上面的 yazi.desktop）在支持该规范的启动器里
  # 就靠这个列表决定「用哪个终端把它跑起来」。
  xdg.terminal-exec = {
    enable = true;
    settings.default = [ "kitty.desktop" ];
  };

  # 从启动器里藏掉两个系统自带条目 —— XDG 规范里「同 id 的文件取优先级最高的那份」，
  # ~/.local/share/applications/<id>.desktop 正好压过 /run/current-system/sw 里那份：
  #   uuctl              ← uwsm 自带（uwsm 本体是会话管理器，要继续留着，只是不要这个条目）
  #   kbd-layout-viewer5 ← fcitx5-configtool 自带（启动器里显示为 Keyboard layout viewer）
  # Hidden=true 是规范里「屏蔽下层同名条目」的写法（NoDisplay 只是「不在菜单里显示」）；
  # exec 给 `true`：条目本身不可用是刻意的，给个能解析的命令免得判成无效条目又被下层顶回来。
  # 不删包里的文件是因为要打 overlay 重建 uwsm / fcitx5 —— 见「能不用自造手段就不用」的约定。
  xdg.desktopEntries = {
    uuctl = {
      name = "uuctl";
      exec = "true";
      settings.Hidden = "true";
    };
    kbd-layout-viewer5 = {
      name = "Keyboard layout viewer";
      exec = "true";
      settings.Hidden = "true";
    };
    # 覆盖 nixpkgs 自带的 scrcpy.desktop（同名条目写在 ~/.local/share/applications，
    # 优先级高于 profile 里那份）：发行版那条跑裸 `scrcpy`，而这台 BlissOS 没有音频设备 →
    # scrcpy 的音频线程抛 UnsupportedOperationException，整个 server 被带走、窗口一闪就退
    # （表现就是「启动器里点了没反应」）。
    # 这里显式 --no-audio；--tcpip 让它自己先 adb connect（设备是 TCP 5555，重启后不用手工连）。
    scrcpy = {
      name = "scrcpy (BlissOS)";
      comment = "Stream and control BlissOS VM107 (audio off, auto-connects 192.168.2.197:5555)";
      exec = "${pkgs.scrcpy}/bin/scrcpy --no-audio --tcpip=192.168.2.197:5555 --keyboard=uhid --mouse=sdk --mouse-bind=++++ --max-size=1280";
      icon = "scrcpy";
      categories = [ "Utility" "RemoteAccess" ];
      terminal = false;
      settings.StartupNotify = "false";
    };
    scrcpy-console = {
      name = "scrcpy (BlissOS, console)";
      comment = "Same as above, but runs in a terminal (shows logs) and uses a real HID mouse (captured/relative mode - for games)";
      exec = "${pkgs.scrcpy}/bin/scrcpy --no-audio --tcpip=192.168.2.197:5555 --keyboard=uhid --mouse=uhid --max-size=1280 --pause-on-exit=if-error";
      icon = "scrcpy";
      categories = [ "Utility" "RemoteAccess" ];
      terminal = true;
      settings.StartupNotify = "false";
    };
  };

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
        # 2026-09-19 Web Push：LibreWolf 的硬化默认把 dom.push.connection.enabled 关掉（只留
        # 页面开着时的 SSE/WS），所以 ntfy 这类站点勾不了「后台通知」。打开推送传输层后，
        # 「浏览器在跑、标签页在后台/窗口最小化」也能收到系统通知；完全退出浏览器时消息会
        # 留在 Mozilla autopush（TTL 内），下次启动 LibreWolf 才弹 —— 桌面端没有系统级推送
        # 守护进程，这点和手机 App 不同。前提：能连 updates.push.services.mozilla.com。
        "dom.push.enabled" = true;            # 本来就是默认值，显式写出来免得被硬化配置改掉
        "dom.push.connection.enabled" = true; # ← 关键：LibreWolf 默认 false，推送连接就靠它
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
    scrcpy # Android 串流/远控客户端（scrcpy 4.x，连 BlissOS VM107）
    android-tools # 提供 adb（scrcpy 需要；也方便直接 adb shell）
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

    # 终端屏保（drift，https://github.com/phlx0/drift）：空闲若干秒后把终端变成
    # 动态壁纸，按任意键回到提示符。包定义在 ./pkgs/drift.nix —— 上游 flake 的
    # vendorHash 是占位符（作者自己让人 nix build 一次再回填），且钉了 unstable 的
    # nixpkgs，所以像 sunshine 那样 vendored 一份走我们自己的 nixpkgs。
    (pkgs.callPackage ./pkgs/drift.nix { })

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
    # compinit 现在由 home-manager 自己跑（zsh-autocomplete 那行是注释状态）。
    # ⚠️ 这两个开关要和下面 zinit 段里的 autocomplete 那行**一起**动：
    # 重新启用 zsh-autocomplete 时，要把它那行取消注释、并把这里改回
    # enableCompletion = false —— 它的 README 要求「删掉所有 compinit 调用」，
    # 其中 Nix 一节的原话就是 programs.zsh.enableCompletion = false
    # （那一关会连带丢掉 HM 夹带的 nix-zsh-completions，记得在 home.packages 里补回来）。
    enableCompletion = true;
    # 插件改由 zinit 统一管理（见下面 initContent 顶部的 zinit 段）。
    # HM 这两个开关各自会 source 一份插件，和 zinit 同时开就是重复加载
    # （autosuggestions 会叠两套 widget、syntax-highlighting 会重复包 zle）→ 关掉。
    autosuggestion.enable = false;
    syntaxHighlighting.enable = false;
    history = {
      size = 10000;
      save = 10000;
      share = true;
    };
    initContent = ''
      # ── zinit（zsh 插件管理器）＋ 插件 ──────────────────────────
      # 本体来自 nixpkgs（钉版本，不走官网那条 curl | sh 的在线引导脚本）；
      # 插件由 zinit 自己 clone 到 ~/.local/share/zinit/plugins/。
      # 以后加插件就是在下面加一行：zinit light <user>/<repo>。
      source ${pkgs.zinit}/share/zinit/zinit.zsh

      # 加载顺序有硬要求，别乱挪：
      # ① zsh-autocomplete：**2026-09-16 起暂时停用**（用户要先只用 autosuggestions +
      #    fzf-tab 跑一段时间看看）。它与 fzf-tab 抢同一套补全 UI —— 实测两者一起开时
      #    Tab 归 fzf-tab、但 autocomplete 自己的「边走边列」不生效，空行按 ↑ 还会报
      #    `command not found: _autocomplete__history_lines` / `_autocomplete__unambiguous`。
      #    想启用：取消下面这行注释，并把 programs.zsh.enableCompletion 改回 false
      #    （它要自己接管 compinit），且必须排在所有插件最前面加载。
      # zinit light marlonrichert/zsh-autocomplete
      # ② fzf-tab 要在 compinit 之后、在会包 widget 的插件（autosuggestions /
      #    syntax-highlighting）之前 —— 见它的 README 安装说明。
      zinit light Aloxaf/fzf-tab
      zinit light zsh-users/zsh-autosuggestions

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

      # drift（终端屏保）：空闲 DRIFT_TIMEOUT 秒后自动开始播放，按任意键回到提示符。
      # 不想要就删掉这段（或直接 drift 手跑）。场景/主题：drift --showcase
      if command -v drift >/dev/null 2>&1; then
        export DRIFT_TIMEOUT=180
        eval "$(drift shell-init zsh)"
      fi

      # 语法高亮必须**最后**加载（zsh-syntax-highlighting FAQ：要在所有自定义 widget 之后）
      zinit light zsh-users/zsh-syntax-highlighting
    '';
  };

  home.file.".p10k.zsh".source = ./p10k.zsh;
}
