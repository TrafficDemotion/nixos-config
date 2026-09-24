-- ~/.config/hypr/hyprland.lua
-- 源文件：/etc/nixos/hypr/hyprland.lua（home-manager 软链到这里；改了要 rebuild 才生效）
-- Hyprland 0.55 起 hyprlang 换 Lua，文档：https://wiki.hypr.land/Configuring/Start
-- 桌面外壳是 Caelestia（Quickshell）：状态栏/通知/启动器/锁屏/截图都由它提供，
-- 由它自己的 systemd 用户服务启动，这里不需要 exec。键位沿用 Caelestia 官方默认。
-- 窗口一律浮动（自由拖动，不做平铺）：见文件末尾的 float-all 规则。
-- 键位里的 SUPER = Win 键

--------------------
----  显示器  ----
--------------------
hl.monitor({
  output = "",
  mode = "preferred",
  position = "auto",
  scale = "auto",
})

-- 核显 HDMI-A-1：那份「软件假负载」EDID 对应的输出（插上真显示器就是它）。
-- 刷新率必须写死：**首选时序 ≠ 最高刷新率** —— 这份 AOC Q24G50F 的 EDID 把
-- 2560x1440@60 放在第一个 DTD（首选），144Hz 那条在 CEA 扩展块里（范围描述符 48–144Hz），
-- 所以 mode = "preferred" 永远只会拿到 60Hz。写死 144 有两个理由：
--   ① 面板本身就吃 144；② Moonlight 客户端设的是 1080p@120fps，放 60Hz 上等于砍一半。
-- scale 必须写死 1，否则 auto 会按 DPI 猜出非 1 的缩放。
-- 换屏/换线后若这条模式不在 EDID 的模式列表里，Hyprland 会报 Invalid mode 并忽略该规则
-- （退回自动选择）；那时把这里改成该 EDID 支持的值，或干脆写回 mode = "preferred"。
hl.monitor({
  output = "HDMI-A-1",
  mode = "2560x1440@144",
  position = "auto",
  scale = 1,
})

--------------------
----  程序  ----
--------------------
local terminal = "kitty"
local browser = "firefox"
local editor = "kitty -e nvim"
local files = "kitty -e yazi"

------------------------
----  环境变量  ----
------------------------
-- 光标主题：Windows 11 by Jepri Creations 的「candy」深色小号版（dark/small/09. candy）。
-- 主题本体是 xcursor 格式，放在本机 ~/.local/share/icons/W11-dark-candy-small/
-- （包自带的 Agreement.txt 禁止再分发 → 不进这个公开仓库、也不进 nix store；
--  它靠 /etc/set-environment 的 XCURSOR_PATH 被找到，重建配方见 README）。
-- 主题名是从环境变量读的 → **只在 Hyprland 启动时生效**；当前会话想立刻换就用
--   hyprctl setcursor W11-dark-candy-small 32
-- 尺寸 32＝包内原生像素（图里有 32/48/64/96 四档，libXcursor 不缩放：写 24 也会拿 32 那张）。
hl.env("XCURSOR_THEME", "W11-dark-candy-small")
hl.env("HYPRCURSOR_THEME", "W11-dark-candy-small")
hl.env("XCURSOR_SIZE", "32")
hl.env("HYPRCURSOR_SIZE", "32")
hl.env("NIXOS_OZONE_WL", "1") -- Chromium / Electron 走原生 Wayland
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
hl.env("MOZ_ENABLE_WAYLAND", "1") -- Firefox 走 Wayland
hl.env("GDK_BACKEND", "wayland,x11")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("LIBVA_DRIVER_NAME", "iHD") -- Intel 核显硬解/硬编（VA-API）

----------------------------
----  开机自启  ----
----------------------------
hl.on("hyprland.start", function()
  hl.exec_cmd("hyprpolkitagent") -- polkit 认证弹窗
  -- 注：早期自己拼 shell 时这里还 exec 过 `nm-applet --indicator`（托盘网络图标），
  -- 2026-09-16 删掉 —— 竖栏的网络图标与 Wi-Fi 面板是 Caelestia 自己实现的
  -- （home.nix 的 bar.statusIcons 里的 network）。
  -- 壁纸守护进程（2026-09-13）：外壳自己不再画壁纸（见 home.nix 里
  -- settings.background.wallpaperEnabled = false），屏幕上的图由 awww 铺在 background 层。
  -- 它启动时会按输出从缓存恢复上次那张图（manpage：--no-cache 才是「不去缓存找」），
  -- 所以不需要额外的「初始化命令」。切壁纸走 caelestia CLI 的 wallpaper.postHook。
  hl.exec_cmd("awww-daemon")
  -- 输入法 fcitx5 不在这里启动：NixOS 模块自带的 XDG autostart（fcitx5 包里的
  -- org.fcitx.Fcitx5.desktop，由 uwsm 变成 app-org.fcitx.Fcitx5@autostart.service）已经负责
  -- 拉起它。两处都写会开两个实例抢 D-Bus 名，败者报 "Unable to request dbus name" 后自杀
  -- （2026-09-12 删掉原来这行的 `hl.exec_cmd("fcitx5 -d")`）。
end)

------------------------------
----  UI 交互音效（pixel）----
------------------------------
-- 主体已搬进外壳的 QML 补丁（patches/caelestia/0003 + 0004，2026-09-13）：
--   窗口开/关、切工作区        → services/Hypr.qml（toplevels 模型增删 + focusedWorkspace 变化）
--   面板开合（启动器/仪表盘/电源菜单/侧边栏/右下抽屉/OSD）
--                              → components/ScreenState.qml（那几个布尔值变化，含鼠标点与 IPC 触发）
--   截图快门（Print / Super+Shift+S / +Alt+S）→ modules/areapicker/AreaPicker.qml（activeAsync）
--   锁屏 + 解锁                → modules/lock/Lock.qml（locked 变化；解锁原先没有事件可挂）
--   录屏开始/结束              → services/Recorder.qml（running 变化）
--   点击 / 开关 / 滑条 / 滚轮  → 共享组件（StateLayer / StyledSwitch / Filled*Slider / CustomMouseArea）
-- 音效总开关：home.nix 里 programs.caelestia.systemd.environment = [ "CAELESTIA_UI_SOUNDS=0" ]。
-- ⚠️ 只有下面两条还留在这里：剪贴板与 emoji 是**外部 fuzzel 进程**（`caelestia clipboard` /
--    `caelestia emoji` 都只是 `fuzzel --dmenu`），外壳看不到它们开合，QML 侧挂不上。
-- 素材：AOSP/LineageOS 的 UI 音，ffmpeg 转 48k 立体声（命令见 README「UI 交互音效」），
-- 文件由 home.nix 的 xdg.dataFile 声明 → ~/.local/share/sfx/（在 nix store 里）。
-- 播放用 pw-play（PipeWire 自带）。关掉：把 sfxEnabled 改成 false。
local sfxEnabled = true
local sfxDir = "/home/paan/.local/share/sfx/"

local function playSfx(file)
  if sfxEnabled then
    hl.exec_cmd("pw-play " .. sfxDir .. file)
  end
end

-- 「先出声、再干活」：同一次按键里既放音又派发原动作。
local function bindSfx(file, dispatcher)
  return function()
    playSfx(file)
    hl.dispatch(dispatcher)
  end
end

------------------------
----  外观 / 动画  ----
------------------------
hl.config({
  general = {
    gaps_in = 5,
    gaps_out = 12,
    border_size = 2,
    col = {
      -- 活动窗口边框：纯白（2026-09-12 按用户要求从青绿渐变 rgba(33ccffee)→rgba(00ff99ee) 改成白色）
      active_border = "rgba(ffffffff)",
      inactive_border = "rgba(595959aa)",
    },
    resize_on_border = false,
    allow_tearing = false,
  },

  decoration = {
    rounding = 8,
    rounding_power = 2,
    active_opacity = 1.0,
    inactive_opacity = 1.0,
    shadow = {
      enabled = true,
      range = 4,
      render_power = 3,
      color = 0xee1a1a1a,
    },
    blur = {
      enabled = true,
      size = 3,
      passes = 1,
      vibrancy = 0.1696,
    },
  },

  animations = {
    enabled = true,
  },
})

-- 曲线（"default" 是内置曲线）
hl.curve("easeOutQuint", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })
hl.curve("easeInOutCubic", { type = "bezier", points = { { 0.65, 0.05 }, { 0.36, 1 } } })
hl.curve("linear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })
hl.curve("almostLinear", { type = "bezier", points = { { 0.5, 0.5 }, { 0.75, 1 } } })
hl.curve("quick", { type = "bezier", points = { { 0.15, 0 }, { 0.1, 1 } } })
hl.curve("easy", { type = "spring", mass = 1, stiffness = 71.2633, dampening = 15.8273644 })

hl.animation({ leaf = "global", enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "border", enabled = true, speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows", enabled = true, speed = 4.79, spring = "easy" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 4.1, spring = "easy", style = "popin 87%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.49, bezier = "linear", style = "popin 87%" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade", enabled = true, speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers", enabled = true, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 4, bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 1.5, bezier = "linear", style = "fade" })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesIn", enabled = true, speed = 1.21, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "zoomFactor", enabled = true, speed = 7, bezier = "quick" })

--------------------
----  杂项  ----
--------------------
hl.config({
  misc = {
    force_default_wallpaper = 0,
    disable_hyprland_logo = true,
    -- 锁屏期间继续渲染下面的工作区（Hyprland 官方选项）。两个作用：
    -- ① 解锁时桌面已是渲染好的，不再「卡一下 → 窗口/bar 整帧弹出来」；
    -- ② 配合 0007 补丁把锁屏整层淡成透明，解锁就是真正的交叉淡化（桌面在下层淡入）。
    -- 锁屏本身仍是完全不透明的（壁纸 + 密码框），外面看不到桌面内容。
    session_lock_xray = true,
  },
})

----------------
----  输入  ----
----------------
hl.config({
  input = {
    kb_layout = "us",
    kb_variant = "",
    kb_model = "",
    kb_options = "",
    kb_rules = "",
    follow_mouse = 1,
    sensitivity = 0,
    touchpad = {
      natural_scroll = false,
    },
  },
})

----------------
----  键位  ----
----------------
local mainMod = "SUPER"

-- Caelestia：面板 / 会话 / 通知
hl.bind("SUPER + SUPER_L", hl.dsp.global("caelestia:launcher"), { release = true }) -- 单按 Win 键 = 启动器
hl.bind(mainMod .. " + N", hl.dsp.global("caelestia:sidebar")) -- 侧边栏
hl.bind("CTRL + ALT + Delete", hl.dsp.global("caelestia:session")) -- 电源菜单
hl.bind("CTRL + ALT + C", hl.dsp.global("caelestia:clearNotifs"), { locked = true })

-- vim 风的字母键位：h、j 本来就没有绑定；k（仪表盘）2026-09-16 停用，l（锁屏）2026-09-21
-- 按用户要求恢复（他习惯按 SUPER+L 锁屏）。仪表盘仍有鼠标入口：竖栏右下的电源图标 /
-- 会话菜单、单按 Win 的启动器；想恢复 k 就把那行前面的 `-- ` 去掉。
-- hl.bind(mainMod .. " + K", hl.dsp.global("caelestia:showall")) -- 仪表盘（显示所有面板，已停用）
hl.bind(mainMod .. " + L", hl.dsp.global("caelestia:lock")) -- 锁屏（Caelestia 内置，背景已改壁纸；解锁没有事件可挂）

-- 应用
hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + W", hl.dsp.exec_cmd(browser))
hl.bind(mainMod .. " + C", hl.dsp.exec_cmd(editor))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(files))

-- 窗口
hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen({ action = "toggle" }))
hl.bind(mainMod .. " + ALT + F", hl.dsp.window.fullscreen({ mode = "maximized" }))
hl.bind(mainMod .. " + P", hl.dsp.window.pin())
-- 平铺/浮动切换（SUPER + ALT + Space）按用户要求停用（2026-09-16）。
-- 本机所有窗口默认就是浮动（见文件末尾的 float-all 规则），这条只会把窗口切成平铺。
-- 恢复办法：把下一行前面的 `-- ` 去掉。
-- hl.bind(mainMod .. " + ALT + Space", hl.dsp.window.float({ action = "toggle" }))
hl.bind("ALT + TAB", hl.dsp.window.cycle_next(), { repeating = true })
hl.bind("SHIFT + ALT + TAB", hl.dsp.window.cycle_next({ next = false }), { repeating = true })

-- 缩放窗口：整组停用（2026-09-16 用户要求「SUPER + 加号/减号都删掉」）。
-- 起因：09-16 早些时候只停用了 SUPER + SHIFT + Equal（他按到时窗口被拉高了），
-- 这次把 Equal / Minus / SHIFT + Minus 一并停用 —— 窗口大小只靠鼠标
-- （SUPER 或 ALT + 右键拖动）。
-- 恢复办法：把下面四行前面的 `-- ` 去掉。
-- hl.bind(mainMod .. " + Equal", hl.dsp.window.resize({ x = 40, y = 0, relative = true }), { repeating = true })
-- hl.bind(mainMod .. " + Minus", hl.dsp.window.resize({ x = -40, y = 0, relative = true }), { repeating = true })
-- hl.bind(mainMod .. " + SHIFT + Equal", hl.dsp.window.resize({ x = 0, y = 40, relative = true }), { repeating = true })
-- hl.bind(mainMod .. " + SHIFT + Minus", hl.dsp.window.resize({ x = 0, y = -40, relative = true }), { repeating = true })

-- 焦点：SUPER + 方向键
hl.bind(mainMod .. " + left", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down", hl.dsp.focus({ direction = "down" }))

-- 工作区：SUPER + 数字切换，SUPER + SHIFT + 数字把窗口移过去
for i = 1, 10 do
  local key = i % 10 -- 10 对应 0
  hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
  hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- 特殊工作区（scratchpad）
hl.bind(mainMod .. " + S", hl.dsp.workspace.toggle_special("special"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:special" }))

-- SUPER + 滚轮：轮换工作区
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

-- SUPER + 左键拖动移动窗口，右键拖动缩放；习惯普通桌面的话用 ALT + 左/右键同理
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
hl.bind("ALT + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind("ALT + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- 截图 / 录屏（Caelestia）
hl.bind("Print", hl.dsp.exec_cmd("caelestia screenshot"), { locked = true })
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.global("caelestia:screenshotFreeze"))
hl.bind(mainMod .. " + SHIFT + ALT + S", hl.dsp.global("caelestia:screenshot"))
hl.bind("CTRL + ALT + R", hl.dsp.exec_cmd("caelestia record"))

-- 剪贴板 / emoji（2026-09-16 起）：改走外壳自己的启动器界面（本地补丁 0013，
-- 见 home.nix 的 patches 列表）——`caelestia:clipboard` / `caelestia:emoji` 是外壳
-- 注册的全局快捷键，列表由 AppList 画，跟外壳同一套组件与配色。
-- 原来的 `caelestia clipboard` / `caelestia emoji -p`（fuzzel 版）仍然可用，只是不再绑键位。
hl.bind(mainMod .. " + V", bindSfx("workspace-switch.wav", hl.dsp.global("caelestia:clipboard")))
hl.bind(mainMod .. " + Period", bindSfx("workspace-switch.wav", hl.dsp.global("caelestia:emoji")))

-- 音量（wpctl 来自 pipewire）
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
hl.bind(mainMod .. " + SHIFT + M", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true })

-- 亮度（Caelestia 管）
hl.bind("XF86MonBrightnessUp", hl.dsp.global("caelestia:brightnessUp"), { locked = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.global("caelestia:brightnessDown"), { locked = true })

-- 媒体播放（Caelestia 管，不再需要 playerctl）
hl.bind("XF86AudioPlay", hl.dsp.global("caelestia:mediaToggle"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.global("caelestia:mediaToggle"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.global("caelestia:mediaNext"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.global("caelestia:mediaPrev"), { locked = true })
hl.bind("XF86AudioStop", hl.dsp.global("caelestia:mediaStop"), { locked = true })

-- 重启外壳（出问题时用）
hl.bind("CTRL + SUPER + SHIFT + R", hl.dsp.exec_cmd("qs -c caelestia kill"), { release = true })
hl.bind("CTRL + SUPER + ALT + R", hl.dsp.exec_cmd("qs -c caelestia kill; sleep .1; caelestia shell -d"), { release = true })

------------------------
----  窗口规则  ----
------------------------
-- 所有窗口默认浮动 = 自由拖动、不铺满平铺格；SUPER+F 仍可全屏（游戏/视频用这个）
hl.window_rule({
  name = "float-all",
  match = { class = ".*" },
  float = true,
})

-- 窗口记住「上次的尺寸」（2026-09-17 用户要求：关掉再开还是上次模样）。
-- 用的是 Hyprland 原生的 window rule 效果 persistent_size（0.55 起有；wiki → Window Rules →
-- Dynamic effects："For floating windows, internally store their size. When a new floating window
-- opens with the same class and title, restore the saved size"）。
-- 实现（`src/desktop/state/FloatState.cpp` 的 CFloatStateCache）：一张**内存里的**哈希表，
-- 键 = (initialClass, initialTitle, xdgTag)，值 = 尺寸；窗口几何被计算时
-- （`src/layout/target/WindowTarget.cpp:293`）如果命中就盖掉应用请求的尺寸。
-- 边界（按上游源码，比 wiki 那句更准，别指望更多）：
--   * **只记尺寸，不记位置** —— 位置仍由 Hyprland 每次自己决定（Wayland 客户端本来也不能指定位置）；
--   * 那张表在内存里 ⇒ **重启 Hyprland / 重登会话就清空**，不是跨会话记忆；
--   * 键里含 title ⇒ 标题会变的程序（浏览器按页面标题、终端按 cwd 或正在跑的程序）只有
--     "标题一样的那次"才会命中；标题稳定的程序（neovide 带文件名、设置类小窗）命中率最高。
hl.window_rule({
  name = "persistent-size",
  match = { class = ".*" },
  persistent_size = true,
})

-- Waydroid（Android 容器）窗口尺寸钉成 Google Pixel 7（代号 panther）的屏幕：1080x2400（20:9）。
-- 用户 2026-09-22 要求「固定窗口尺寸为 pixel7-panther 的屏幕尺寸」。
--   * 静态 size 规则**会压过**上面那条 persistent-size 记忆（见 neovide 那段 A/B 实测），
--     这正是这里想要的 —— 否则 Waydroid 窗口会被「上次拖成多大」记走，尺寸飘。
--   * 注意这与 Android 自己的输出分辨率是两件事：那个由 session 启动时的
--     `persist.waydroid.width/height` 决定（`waydroid prop set …` 后必须重启 session）。
--   * 尺寸 405x900 = Pixel 7（panther，1080x2400）的**等比缩放**（比例都是 9:20），高约屏（2560x1440）的 5/8。
--     **锁死靠的是 `min_size` + `max_size` 写成同一个值** —— 只写 `size` 不够：那只是「开窗时的初始尺寸」，
--     用户照样能用 SUPER+右键拖动改掉（2026-09-22 用户实测反馈）。两个约束相等后拖动 resize 会被钳制回来。
--     依据：Hyprland 0.55.4 的 window-rule 效果列表里就有 `max_size` / `min_size` / `keep_aspect_ratio`
--     （`src/desktop/rule/windowRule/WindowRuleEffectContainer.cpp`）。实测（`hyprctl eval` 临时加这条规则后）：
--     `hl.dsp.window.resize({x=800,y=800})` 与 `{x=200,y=200}` 结果都是 405x900，且对**已经开着的**窗口立即生效。
--   * 曾按字面钉成 1080x2400（Pixel 7 的真实像素尺寸），实测在 1440 高的屏上上下各伸出 480px
--     （`at: 740,-480`）还占掉近半屏幕，用户否了。1080x2400 只作 Android 内部渲染分辨率
--     （`persist.waydroid.width/height`），窗口另有其尺寸。
hl.window_rule({
  name = "waydroid-pixel7-size",
  match = { class = "^Waydroid$" },
  size = "405 900",
  min_size = "405 900",
  max_size = "405 900",
})

-- scrcpy（串 BlissOS VM107）的窗口：**拖动缩放时保持比例**（2026-09-24 用户要求"缩放时保持窗口比例、不要黑边"）。
--   * 画面比例 = 面板 720x1600（9:20）→ `--max-size=1280` 得 576x1280；窗口比例与画面一致 ⇒ 不会出现黑边。
--   * **不要写 `size` / `min_size` / `max_size`**：`size` 会压过上面那条 `persistent_size`（用户自己拖出的尺寸记不住），
--     `min_size` == `max_size` 又会把窗口锁死（用户 2026-09-24 反馈"最小尺寸太大了"，想再拖小）。只留 `keep_aspect_ratio`。
--   * `keep_aspect_ratio` 只约束**交互式拖动**；程序化 `hl.dsp.window.resize({x=…,y=…})` 不受它管（实测能拉成 1000x400，
--     所以别用 dispatch 去验证它）。要**真正锁死**才加 `min_size`/`max_size` 同值（那时程序化 resize 会被钳回）。
--   * 窗口 class 是 Nix wrapper 的名字 **`.scrcpy-wrapped`**（不是 `scrcpy`）—— 判据 `hyprctl clients`。
--   * regex 走 std::regex（ECMAScript）：**只转义 `.`**，别用 Lua 的 `%` —— 写成 `%-` 会静默不匹配（踩过）。
--   * 改完记得 `nixos-rebuild switch` **再 `hyprctl reload`**，否则不生效（软链换新不会自动重载）。
hl.window_rule({
  name = "scrcpy-keep-aspect",
  match = { class = "^\\.scrcpy-wrapped$" },
  keep_aspect_ratio = true,
})

-- 忽略所有应用的最大化请求
hl.window_rule({
  name = "suppress-maximize-events",
  match = { class = ".*" },
  suppress_event = "maximize",
})

-- 修 XWayland 的拖动问题
hl.window_rule({
  name = "fix-xwayland-drags",
  match = {
    class = "^$",
    title = "^$",
    xwayland = true,
    float = true,
    fullscreen = false,
    pin = false,
  },
  no_focus = true,
})

-- 设置类小窗口默认浮动
hl.window_rule({
  name = "float-settings",
  match = { class = "^(pavucontrol|nm-connection-editor|blueman-manager)$" },
  float = true,
})

-- neovide 的窗口尺寸：**交给上面的 persistent_size 记忆**（2026-09-17 改；原来这里固定 size = "1600 1000"）。
-- 起因：从 yazi 里 Enter 打开的 neovide 不记住尺寸。A/B 实测根因不是记忆没生效，而是静态 size 规则
--   **会压过 persistent_size**：eval 追加一条更靠后的 1200x800 规则 → 开成 1200x800 并且关窗时入了记忆表；
--   再 `hyprctl reload` 清掉 eval 规则（本条的 1600x1000 回来）→ 重开又变回 1600x1000（连开两次同样）。
--   ⇒ **尺寸规则和尺寸记忆不能并存**，所以这里把 size 整个去掉，让记忆说了算。
-- 其它背景（2026-09-16 记下的，仍然成立）：neovide 0.16.2 自己那两条路在这台机上都不行 ——
--   * `--size` / config.toml 的 size：只在窗口映射前 request_inner_size 一次，Wayland 下被忽略
--     （实测 --size 400x300 照样开成 800x600，1600x1000 也一样）；
--   * `--grid`：参数组有冲突 bug，一用就报 "cannot be used with '--size'" 直接退出。
-- 现在没有任何尺寸规则：第一次开由 neovide 自己请求（`~/.local/share/neovide/neovide-settings.json`
-- 里存着它自己的 grid_size），之后你手动调成什么尺寸、关掉再开就是什么尺寸。neovide 的窗口标题恒为
-- "[No Name]"（不含文件名），所以记忆的键对所有文件是同一个 —— 换文件打开也照样回到你上次的尺寸。
-- 想退回固定尺寸：加一条 `hl.window_rule({ name = "neovide-size", match = { class = "^neovide$" },
-- size = "1600 1000" })` —— 但那样记忆会再次失效（有尺寸规则时尺寸规则赢）。
-- （这条规则本身已经删掉了：它现在没有任何 effect，留着只是噪音。）
