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
-- 模式和刷新率都不写死，用 EDID 的首选模式 2560x1440@60，这样插上真显示器时
-- 还能自己改成 144/180Hz；scale 必须写死 1，否则 auto 会按 DPI 猜出非 1 的缩放。
hl.monitor({
  output = "HDMI-A-1",
  mode = "preferred",
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
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
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
  hl.exec_cmd("nm-applet --indicator") -- 托盘网络图标
  hl.exec_cmd("hyprpolkitagent") -- polkit 认证弹窗
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
-- 素材：AOSP/LineageOS 的 UI 音，ffmpeg 转 48k 立体声（命令见 README「UI 交互音效」），
-- 文件由 home.nix 的 xdg.dataFile 声明 → ~/.local/share/sfx/（在 nix store 里）：
--   window-open.wav      新窗口                        peak -3 dB
--   window-close.wav     关窗口                        peak -6 dB
--   workspace-switch.wav 切工作区 / 打开外壳面板        peak -9 dB
--   camera-shutter.wav   截图（Print / Super+Shift+S）  peak -5 dB
--   lock.wav             锁屏（Super+L）                peak -5 dB
-- 播放用 pw-play（PipeWire 自带；本机没有 pulseaudio/paplay）。
-- ⚠️ 单条 ≈100–140 ms（实测 pw-play 的起流开销，空闲与否都一样，不是音箱唤醒慢）——
--    这就是「事件已发生、声音慢半拍」的来源，也是这条路线延迟的下限。想更快只能让声音
--    在外壳进程内播（QtMultimedia 的 SoundEffect），那要改 QML 且给壳加 qtmultimedia 依赖。
-- ⚠️ 这里只覆盖「Hyprland 能看到的事」：窗口/工作区事件 + **键盘触发的**外壳面板。
--    鼠标点栏上的图标、点启动器里的条目、通知弹出 —— Hyprland 一概看不见，要那些只能改 QML。
-- 关掉：把 sfxEnabled 改成 false（整段就静默了）。
local sfxEnabled = true
local sfxDir = "/home/paan/.local/share/sfx/"

local function playSfx(file)
  if sfxEnabled then
    hl.exec_cmd("pw-play " .. sfxDir .. file)
  end
end

-- 「先出声、再干活」：同一次按键里既放音又派发原动作。
-- hl.dispatch() 是官方 API（`hl.meta.lua` 的 `HL.dispatch fun(dispatcher|function)`），
-- 实测它既接受 dispatcher 也接受函数，函数体里那句 pw-play 会照常执行。
local function bindSfx(file, dispatcher)
  return function()
    playSfx(file)
    hl.dispatch(dispatcher)
  end
end

-- ── 窗口 / 工作区（Hyprland 事件回调）──
hl.on("window.open", function(_) playSfx("window-open.wav") end) -- 新窗口
hl.on("window.close", function(_) playSfx("window-close.wav") end) -- 关窗口
hl.on("workspace.active", function(_) playSfx("workspace-switch.wav") end) -- 切工作区

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
hl.bind("SUPER + SUPER_L", bindSfx("workspace-switch.wav", hl.dsp.global("caelestia:launcher")), { release = true }) -- 单按 Win 键 = 启动器
hl.bind(mainMod .. " + K", bindSfx("workspace-switch.wav", hl.dsp.global("caelestia:showall"))) -- 仪表盘（显示所有面板）
hl.bind(mainMod .. " + N", bindSfx("workspace-switch.wav", hl.dsp.global("caelestia:sidebar"))) -- 侧边栏
hl.bind("CTRL + ALT + Delete", bindSfx("workspace-switch.wav", hl.dsp.global("caelestia:session"))) -- 电源菜单
hl.bind(mainMod .. " + L", bindSfx("lock.wav", hl.dsp.global("caelestia:lock"))) -- 锁屏（Caelestia 内置，背景已改壁纸；解锁没有事件可挂）
hl.bind("CTRL + ALT + C", hl.dsp.global("caelestia:clearNotifs"), { locked = true })

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
hl.bind(mainMod .. " + ALT + Space", hl.dsp.window.float({ action = "toggle" }))
hl.bind("ALT + TAB", hl.dsp.window.cycle_next(), { repeating = true })
hl.bind("SHIFT + ALT + TAB", hl.dsp.window.cycle_next({ next = false }), { repeating = true })

-- 缩放窗口
hl.bind(mainMod .. " + Equal", hl.dsp.window.resize({ x = 40, y = 0, relative = true }), { repeating = true })
hl.bind(mainMod .. " + Minus", hl.dsp.window.resize({ x = -40, y = 0, relative = true }), { repeating = true })
hl.bind(mainMod .. " + SHIFT + Equal", hl.dsp.window.resize({ x = 0, y = 40, relative = true }), { repeating = true })
hl.bind(mainMod .. " + SHIFT + Minus", hl.dsp.window.resize({ x = 0, y = -40, relative = true }), { repeating = true })

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
hl.bind("Print", bindSfx("camera-shutter.wav", hl.dsp.exec_cmd("caelestia screenshot")), { locked = true })
hl.bind(mainMod .. " + SHIFT + S", bindSfx("camera-shutter.wav", hl.dsp.global("caelestia:screenshotFreeze")))
hl.bind(mainMod .. " + SHIFT + ALT + S", bindSfx("camera-shutter.wav", hl.dsp.global("caelestia:screenshot")))
hl.bind("CTRL + ALT + R", hl.dsp.exec_cmd("caelestia record"))

-- 剪贴板 / emoji（Caelestia CLI + fuzzel）
hl.bind(mainMod .. " + V", bindSfx("workspace-switch.wav", hl.dsp.exec_cmd("pkill fuzzel || caelestia clipboard")))
hl.bind(mainMod .. " + Period", bindSfx("workspace-switch.wav", hl.dsp.exec_cmd("pkill fuzzel || caelestia emoji -p")))

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
