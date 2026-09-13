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
    surface2 = "#{{ surface2.hex }}",
    surface1 = "#{{ surface1.hex }}",
    surface0 = "#{{ surface0.hex }}",
    base = "#{{ base.hex }}",
    mantle = "#{{ mantle.hex }}",
    crust = "#{{ crust.hex }}",
  },
}
