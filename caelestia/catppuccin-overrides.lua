-- ═══════════════════════════════════════════════════════════════════════════════
-- Neovim 的调色板 —— 这份是【模板】，由 Caelestia 用当前壁纸现算的配色渲染
--
--   模板源文件：/etc/nixos/caelestia/catppuccin-overrides.lua（本文件，声明式）
--   模板副本：  ~/.config/caelestia/templates/catppuccin-overrides.lua
--   渲染结果：  ~/.local/state/caelestia/theme/catppuccin-overrides.lua
--   读取方：    ~/.config/nvim/init.lua（喂给 catppuccin 的 color_overrides）
--
-- 为什么是 catppuccin 的键名：Caelestia 的配色里本来就带一整套 catppuccin 风格的名字
-- （rosewater…crust，共 26 个，取自 scheme.json），catppuccin-nvim 的 color_overrides
-- 用的正是这套键名，所以可以一一对上，不用做任何映射转换。
--
-- 渲染规则：两层花括号包住「颜色名.hex」，换成不带 # 的十六进制。这里必须自己补上 #，
-- 因为 catppuccin 内部按 "#RRGGBB" 取第 6/7 位（在 kitty 里它会把蓝色通道 ±1，
-- 免得 nvim 背景和终端背景完全同色被 kitty 当透明处理），拿到 6 位裸十六进制会算出错误颜色。
-- ⚠️ 渲染是纯文本替换，注释里的占位符也会被换掉，示例别写真的花括号。
-- ═══════════════════════════════════════════════════════════════════════════════
return {
  mode = "{{ mode }}", -- dark / light：init.lua 用它选 mocha 还是 latte

  palette = {
    rosewater = "#{{ rosewater.hex }}",
    flamingo = "#{{ flamingo.hex }}",
    pink = "#{{ pink.hex }}",
    mauve = "#{{ mauve.hex }}",
    red = "#{{ red.hex }}",
    maroon = "#{{ maroon.hex }}",
    peach = "#{{ peach.hex }}",
    yellow = "#{{ yellow.hex }}",
    green = "#{{ green.hex }}",
    teal = "#{{ teal.hex }}",
    sky = "#{{ sky.hex }}",
    sapphire = "#{{ sapphire.hex }}",
    blue = "#{{ blue.hex }}",
    lavender = "#{{ lavender.hex }}",
    text = "#{{ text.hex }}",
    subtext1 = "#{{ subtext1.hex }}",
    subtext0 = "#{{ subtext0.hex }}",
    overlay2 = "#{{ overlay2.hex }}",
    overlay1 = "#{{ overlay1.hex }}",
    overlay0 = "#{{ overlay0.hex }}",
    -- surface0/1/2 = Caelestia 自带的「对称灰阶」（surface 向 outline 混 14% / 29% / 43%：
    -- 越往后越靠近中间灰 —— dark 更亮、light 更暗，两套模式的幅度一样，这正是我们要的方向）。
    -- 2026-09-17 背景抬了一档（见下面 base），这一组跟着抬一档：否则 base 会高过 surface0，
    -- 补全菜单、各类浮层底色反而比编辑区更暗（原来 base 是最暗的那一档，才排得下这三级）。
    surface2 = "#{{ overlay0.hex }}",
    surface1 = "#{{ surface2.hex }}",
    surface0 = "#{{ surface1.hex }}",
    -- 背景：surfaceContainerHighest（dark #1f272b / light #dbe4ea）。
    -- 原来是 surfaceContainer（tone12：dark #141a1e / light #e9eff3）。换到容器阶梯最高一档，
    -- 是为了「dark 亮一点、light 暗一点」—— 阶梯往上走同时满足两者（同一个名字在两种模式下
    -- 共用一个档位；模板层没有条件判断，只能这样挑）。实测 L*：dark 8.8 → 15.0、light 94.1 → 90.1。
    -- 想再明显一档：换成 surface1（dark #292e31 / light #ccd1d4，±10 L*；那 surface0/1/2 还要再抬）。
    -- 想退回原样：base/mantle/crust 各降一档，surface0/1/2 也降回去。
    base = "#{{ surfaceContainerHighest.hex }}",
    mantle = "#{{ surfaceContainerHigh.hex }}", -- 侧栏/状态行底：紧贴背景“远”一档（dark 更暗 / light 更亮）
    crust = "#{{ surfaceContainer.hex }}",      -- 再远一档（旧方案里是最外圈的 surfaceContainerLowest）
  },
}
