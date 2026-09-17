-- ═══════════════════════════════════════════════════════════════════════════
-- paan 的 Neovim 基本配置
--
-- 这个文件是声明式的：home.nix 的 programs.neovim.initLua 用
-- builtins.readFile ./nvim/init.lua 读它，生成的 ~/.config/nvim/init.lua
-- 是指向 /nix/store 的【只读软链】。
--   * 改配置 = 改这个文件，然后：sudo nixos-rebuild switch --flake /etc/nixos#nixos
--   * 插件的【来源】还是 Nix（home.nix 顶部 let 里的 nvimPlugins 列表 → nixpkgs 的
--     vimPlugins），插件的【加载】交给 lazy.nvim：清单由 Nix 生成到
--     ~/.config/nvim/lua/nix-plugins.lua，本文件里 `require("lazy").setup(...)` 读它。
--     仍然是离线、可重现的路子：lazy 不下载也不更新插件（每条 spec 都带 dir =
--     /nix/store 路径），只用它的加载器与 :Lazy 界面。加插件 = 改 home.nix 再 rebuild。
-- ═══════════════════════════════════════════════════════════════════════════

local opt = vim.opt
local map = vim.keymap.set

-- ── 选项 ───────────────────────────────────────────────────────────────────
vim.g.mapleader = " "

opt.number = true             -- 行号
opt.relativenumber = true     -- 相对行号（当前行显示绝对值）
opt.mouse = "a"               -- 鼠标全模式可用
opt.clipboard = "unnamedplus" -- 复制/粘贴走系统剪贴板（wl-clipboard 在 PATH 里）
opt.termguicolors = true
opt.signcolumn = "yes"        -- 固定留出标记列，避免开关标记时整屏横向抖动
opt.cursorline = true
opt.scrolloff = 6
-- 横向最小留白：右侧的缩小地图（neominimap，float 布局、宽 20 列）会盖住窗口最后 20 列，
-- 上游建议 float 布局下把它放大（默认 8），否则光标贴到右边时文字会钻到缩略图底下。
opt.sidescrolloff = 36
opt.splitright = true
opt.splitbelow = true
opt.wrap = false
opt.expandtab = true          -- 缩进用空格
opt.tabstop = 4
opt.shiftwidth = 4
opt.softtabstop = 4
opt.autoindent = true
opt.smartindent = true
opt.ignorecase = true
opt.smartcase = true          -- 搜索里出现大写时自动区分大小写
opt.incsearch = true
opt.undofile = true           -- 关闭文件后仍可撤销（~/.local/state/nvim/undo）
opt.swapfile = false
opt.updatetime = 300
opt.timeoutlen = 400
opt.completeopt = "menuone,noselect"
opt.laststatus = 3            -- 全局 statusline（配合顶部 bufferline 更像 IDE）
opt.showmode = false          -- 模式交给 lualine 显示
opt.confirm = true
opt.pumheight = 10
opt.winborder = "rounded"     -- 悬浮窗圆角边框

-- nix / lua / 前端 / 配置文件统一 2 空格（其余语言按上面的 tabstop=4）
vim.api.nvim_create_autocmd("FileType", {
  pattern = {
    "nix", "lua", "yaml", "json", "jsonc", "toml", "html", "css", "scss",
    "javascript", "typescript", "javascriptreact", "typescriptreact",
    "vue", "markdown",
  },
  callback = function()
    vim.bo.tabstop, vim.bo.shiftwidth, vim.bo.softtabstop = 2, 2, 2
  end,
})

-- 关掉 netrw：目录浏览交给 neo-tree
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- ── 代码缩略图：neominimap（右侧的 minimap）──────────────────────────────
-- ⚠️ 这份配置必须写在下面 require("lazy").setup(...) 【之前】：
--   插件读的是 `vim.g.neominimap`（v3 起没有 setup() 函数 —— require("neominimap")
--   导出的全是已废弃的兼容壳），而且它的 config 模块只在第一次被 require 时
--   `vim.tbl_deep_extend("force", internal, vim.g.neominimap)` 读一次；lazy 会在
--   setup() 里同步加载所有 lazy = false 的插件（含 plugin/neominimap.lua，那里就读 config），
--   那时候要能看见这张表。
-- 插件本体：/etc/nixos/pkgs/neominimap.nix（nixpkgs 与 nixpkgs-unstable 里都没有，本地
--   vendored 的 buildVimPlugin 包定义），由 home.nix 顶部的 nvimPlugins 清单经 lazy 加载。
-- 渲染用【盲文点阵字符】U+2800–U+28FF（一个字符 = 2×4 个点），而 JetBrainsMono Nerd Font
--   没有这个区段（实测 fc-list ":charset=2800" 不含它）→ 两处都挂了回退字体 FreeMono：
--   kitty 侧 = home.nix 的 programs.kitty.settings.symbol_map；neovide 侧 = 上面 guifont 的逗号链。
-- 布局 = 上游默认的 float：贴窗口右侧、宽 20 列、上下整条 ⇒ 顶部把 sidescrolloff 调到了 36
--   （见那儿注释），否则光标贴右边时文字会钻到缩略图底下。
vim.g.neominimap = {
  -- 鼠标点缩略图直接跳到那一行（上游默认关）。auto_switch_focus = false =
  -- 点完焦点仍留在代码窗口（上游默认 true 会把焦点切到缩略图上，多一步切回来）。
  click = { enabled = true, auto_switch_focus = false },
  -- 其余全用上游默认：auto_enable = true / layout = "float" / minimap_width = 20 /
  -- treesitter.enabled = true（点阵按语法着色）/ git.enabled = true /
  -- diagnostic.enabled = true（本机没配 LSP，所以暂时看不到诊断色块）。
  -- 临时开关：:Neominimap Toggle（全局）/ :Neominimap BufToggle（当前文件）。
}

-- ── 插件管理：lazy.nvim ───────────────────────────────────────────────────
-- 插件清单不写在这里，而是由 Nix 生成到 ~/.config/nvim/lua/nix-plugins.lua
-- （源 = home.nix 的 nvimPlugins 列表 + 那段 xdg.configFile）：每条都是
--   { name = "...", dir = "/nix/store/...", lazy = false }
-- 所以 lazy 在这里只干三件事：把插件挂上 runtimepath、按 spec 决定加载时机、
-- 提供 :Lazy / :Lazy profile 界面 —— 不下载、不更新（插件本体由 Nix 提供）。
-- 必须放在下面所有 require("<插件>") 之前：setup() 会【同步】加载 lazy = false 的
-- 插件（lazy.core.loader 的 startup() 在 setup() 末尾跑），之后那些 require 才找得到模块。
-- lazy.nvim 自己由 home-manager 放进 packpath（programs.neovim.plugins），
-- 不需要官方文档里那段 `git clone` 的 bootstrap。
require("lazy").setup(require("nix-plugins"), {
  -- 插件全在 /nix/store 里、由 Nix 管，下面这些能力一律关掉，
  -- 免得 :Lazy 面板上出现注定失败或没意义的 install/update 提示。
  install = { missing = false },
  checker = { enabled = false },
  change_detection = { enabled = false },
})

-- ── 颜色主题：跟随 Caelestia 的壁纸取色（用 catppuccin 那套键名）───────────
-- 调色板由 Caelestia 从当前壁纸现算，渲染到
--   ~/.local/state/caelestia/theme/catppuccin-overrides.lua
-- （模板源文件 /etc/nixos/caelestia/catppuccin-overrides.lua，链路见那里的注释）。
-- 文件不存在时（还没渲染过）退回 catppuccin 自带的 Mocha，所以不会没有配色。
-- 换壁纸时 Caelestia 会重写这份文件，下面的 fs_event 监听会就地重载 —— 不用重开 nvim。
local theme_dir = vim.fs.joinpath(vim.fn.expand("~"), ".local/state/caelestia/theme")
local theme_file = "catppuccin-overrides.lua"

-- 读那份渲染好的调色板；不存在或读不出就返回 nil（调用方退回 catppuccin 内置 Mocha）
local function load_dyn_palette()
  local path = vim.fs.joinpath(theme_dir, theme_file)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  f:close()
  local ok, mod = pcall(dofile, path)
  if ok and type(mod) == "table" and type(mod.palette) == "table" then
    return mod
  end
  return nil
end

-- ── 区块边界 / 缩进线：在主题之上再盖几笔 ─────────────────────────────────
-- 这里管两类「用符号划出区块」的东西。两者都必须【在 colorscheme 之后】设置：
-- :colorscheme 内部会 hi clear，之前设过的自定义组会被清掉，所以下面这段由
-- apply_theme() 调用（换壁纸时也会重跑一遍，颜色跟着新调色板走）。
--
-- ① 窗口分隔线（左侧 neo-tree 栏与编辑区之间那条竖线）
--    nvim 0.11+ 的 fillchars 默认值本身就是制表符：vert │ / horiz ─ /
--    vertleft ┤ / vertright ├ / verthoriz ┼（后三种只在 laststatus=3 —— 本配置就是
--    —— 时才用得到），所以【符号不用自己设】，要改的是颜色：catppuccin 把
--    WinSeparator 设成 crust（本机 = #000000 纯黑），线其实一直在画，只是黑底上看不见。
--    下面统一改成 surface2（比背景亮一档的中间灰），在 base 底色和 mantle 侧栏底色上都看得清。
--    想更明显换 overlay0 / overlay1；想更淡换 surface1；想要更粗的框就在 fillchars 里
--    把 vert 换成 ┃（写法见 :h 'fillchars'，0.11 起才有 vertleft/vertright/verthoriz）。
--
-- ② 缩进对齐线（indent-blankline，模块名 ibl）的两档颜色
--    catppuccin 自带的 ibl 整合（integrations.indent_blankline）把 IblIndent 写死成
--    surface0（#1a1e21，几乎与背景同色）、IblScope 写死成 text（很亮），两档都不合适；
--    这里用和分隔线同一档的 surface2 + 稍亮一点的 overlay1（光标所在代码块那几条）。
local function apply_custom_hl(pal)
  local set = function(group, key)
    if pal[key] then
      vim.api.nvim_set_hl(0, group, { fg = pal[key] })
    end
  end
  set("WinSeparator", "surface2") -- 竖直边界线（以及 laststatus=3 下的 ┤├┼）
  set("MsgSeparator", "surface2") -- 命令行消息分隔条（默认 link 到 WinSeparator）
  set("NeoTreeWinSeparator", "surface2") -- neo-tree 侧栏自己那条边界线
  set("NeoTreeVertSplit", "surface2")
  set("IblIndent", "surface2") -- 缩进对齐线
  set("IblScope", "overlay1") -- 当前代码块的那几条
end

local function apply_theme()
  local dyn = load_dyn_palette()
  local flavour = (dyn and dyn.mode == "light") and "latte" or "mocha"
  require("catppuccin").setup({
    flavour = flavour,
    -- color_overrides[flavour] 盖在 catppuccin 内置调色板上（vim.tbl_deep_extend 的 "keep"）
    color_overrides = dyn and { [flavour] = dyn.palette } or {},
    integrations = {
      telescope = true,
      neotree = true,
      which_key = true,
    },
  })
  -- 显式点名 flavour：setup() 可以重复调用（它每次都用新的 user_conf 覆盖 options 并按内容哈希决定要不要重编），
  -- 所以换壁纸后直接重跑这一段就能就地换色。
  vim.cmd.colorscheme("catppuccin-" .. flavour)
  -- get_palette() 会带上 setup() 收到的 color_overrides（= 壁纸取色的那套），
  -- 所以这里拿到的就是当前生效的调色板。
  apply_custom_hl(require("catppuccin.palettes").get_palette(flavour))
end

apply_theme()

-- ── 换壁纸时自动跟随 ─────────────────────────────────────────────────────────
-- Caelestia 每次换壁纸/换配色方案都会重写上面那份 lua；这里监听它的【目录】而不是文件本身：
-- CLI 用 atomic rename 写（os.replace 换 inode），盯着文件路径会在第一次替换后跟丢。
do
  local handle = vim.uv.new_fs_event()
  local debounce = vim.uv.new_timer()
  if handle and debounce and vim.uv.fs_stat(theme_dir) then
    vim.uv.fs_event_start(handle, theme_dir, {}, function(err, name)
      if err or (name and name ~= theme_file) then
        return -- 目录里其它文件（如 kitty.conf）动了与我们无关
      end
      -- 一次写入可能触发多个事件，合并到 200ms 之后再重载
      debounce:start(200, 0, vim.schedule_wrap(apply_theme))
    end)
  end
end

-- ── Neovide（GUI 前端）──────────────────────────────────────────────────────
-- 只在 Neovide 里生效，终端里的 nvim 完全不受影响。
-- 分工：字体族 / 字号在下面这段里写（neovide 官方口径是 guifont）；窗口大小写在 Hyprland
-- 的窗口规则里（neovide 自己的 size/grid 在 Wayland 上不生效，见 hyprland.lua 的注释）；
-- ~/.config/neovide/config.toml（home.nix 的 programs.neovide.settings）只放首屏字体值。
if vim.g.neovide then
  -- 字体：neovide 文档（Configuration → Font）里“由 nvim 选项控制”的就是这一项 guifont ——
  -- 所以这里显式写一份；home.nix 的 programs.neovide.settings.font 里那份是 nvim 连上之前
  -- 的首屏值，两边保持一致（改字号记得一起改）。:h10 = 10pt（2026-09-16 从 12 → 11 → 10，
  -- 与 kitty 的 10pt 对齐；还想更小就改这里的数字，支持小数，如 :h9.5）。
  -- 逗号 = neovide 的字体回退链（官方支持 Primary,Fallback1,...）：FreeMono 是给
  -- 右侧缩略图（neominimap）用的 —— 它画的是盲文点阵 U+2800–U+28FF，JetBrainsMono
  -- Nerd Font 里没有这个区段（实测 fc-list ":charset=2800" 不含它），不挂回退就是豆腐块。
  vim.o.guifont = "JetBrainsMono Nerd Font,FreeMono:h10"
  -- 整体缩放（0.10.2 起支持）：不改变上面那份字体定义，只是把整个 GUI 乘一个系数。
  -- 屏幕是 2560x1440 / Hyprland scale 1.00，所以保持 1.0；觉得整体偏大偏小就 0.9 / 1.1，
  -- 运行时改这一行再 :source 本文件即生效（不用重启 neovide）。
  -- 窗口大小不在这里：neovide 自己的 --size/grid 在 Wayland 上不吃，尺寸写在
  -- ~/.config/hypr/hyprland.lua 的窗口规则 `neovide-size`（见那段的注释）。
  vim.g.neovide_scale_factor = 1.0
end

-- ── Treesitter ────────────────────────────────────────────────────────────
-- nvim 0.12 自带 c/lua/vim/vimdoc/query/markdown 的解析器与高亮；
-- 其它语言（nix/python/go/ts/...）的解析器由 Nix 的 nvim-treesitter.withPlugins 提供。
-- 注意：nvim 只对【自带】语言自动开高亮，nvim-treesitter 的 main 分支也只提供
-- 解析器/查询（plugin/nvim-treesitter.lua 里只有 :TSInstall 这类命令），
-- 所以按上游文档在 FileType 时自己 start 一次；已经开了的（自带语言）跳过。
require("nvim-treesitter").setup({})
vim.api.nvim_create_autocmd("FileType", {
  callback = function(args)
    local hl = vim.treesitter.highlighter
    if hl and hl.active and hl.active[args.buf] then
      return
    end
    pcall(vim.treesitter.start, args.buf)
  end,
})

-- ── statusline：lualine ───────────────────────────────────────────────────
-- theme = "auto" 按当前 colorscheme 现生成配色，因此自动跟随 catppuccin
require("lualine").setup({
  options = {
    theme = "auto",
    globalstatus = true,
    section_separators = { left = "", right = "" },
    component_separators = { left = "|", right = "|" },
  },
  sections = {
    lualine_a = { "mode" },
    lualine_b = { "branch", "diff", "diagnostics" },
    lualine_c = { { "filename", path = 1 } },
    lualine_x = { "filetype", "encoding", "fileformat" },
    lualine_y = { "progress" },
    lualine_z = { "location" },
  },
})

-- ── 顶部标签栏：bufferline ─────────────────────────────────────────────────
-- 配色用 catppuccin 自带的组件（上游文档指定的写法）
require("bufferline").setup({
  options = {
    mode = "buffers",
    show_close_icon = false,
    separator_style = "thin",
    always_show_bufferline = true,
    offsets = {
      { filetype = "neo-tree", text = "Explorer", text_align = "left", highlight = "Directory" },
    },
  },
  highlights = require("catppuccin.special.bufferline").get_theme(),
})
map("n", "<S-l>", "<cmd>BufferLineCycleNext<cr>", { desc = "Next buffer" })
map("n", "<S-h>", "<cmd>BufferLineCyclePrev<cr>", { desc = "Previous buffer" })
map("n", "<leader>bp", "<cmd>BufferLinePick<cr>", { desc = "Pick buffer" })
map("n", "<leader>bd", "<cmd>bdelete<cr>", { desc = "Close buffer" })
map("n", "<leader>bo", "<cmd>BufferLineCloseOthers<cr>", { desc = "Close other buffers" })

-- ── 会话：resession.nvim（记住上次的 split 布局 / 打开的文件）────────────────
-- 语义（2026-09-17 用户选定）：**只在「不带参数启动」时**自动恢复当前目录的会话，
-- 带文件参数就照旧只开那个文件 + 左侧树，不会把整个会话顶上来。退出时自动保存。
-- 这是上游 README「Create one session per directory」那一节的官方写法，逐字照搬三处：
--   * `dir = "dirsession"` —— 自动会话与手动 :Session 保存的分开存，互不污染；
--   * `StdinReadPre` 记 `using_stdin` —— `echo x | nvim` 这种不吃会话；
--   * VimEnter 上 `nested = true`（恢复会话本身会开窗/触发别的 autocmd）。
-- 存的东西 = nvim 自己的 :mksession（含 buffers、窗口布局与**窗口尺寸**、tabpages、
-- 工作目录），落在 `~/.local/state/nvim/sessions/`。会话里有 neo-tree 那个 nofile 侧栏时，
-- 靠 neo-tree 的 `auto_clean_after_session_restore = true`（见下面 neo-tree 那段）清掉。
-- 注意顺序：这个 VimEnter 必须**先于**下面「打开左侧树」那个注册，恢复完窗口再拉树。
local resession = require("resession")

resession.setup({})

vim.api.nvim_create_autocmd("StdinReadPre", {
  callback = function()
    vim.g.using_stdin = true
  end,
})

vim.api.nvim_create_autocmd("VimEnter", {
  nested = true,
  callback = function()
    if vim.fn.argc(-1) == 0 and not vim.g.using_stdin then
      resession.load(vim.fn.getcwd(), { dir = "dirsession", silence_errors = true })
    end
  end,
})

vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    resession.save(vim.fn.getcwd(), { dir = "dirsession", notify = false })
  end,
})

-- ── 左侧树宽度：记住上次的值 ────────────────────────────────────────────────
-- 上游没有任何持久化开关：neo-tree 的 `window` 只有 position/width/height/auto_expand_width/popup
-- （`lua/neo-tree/defaults.lua`，全仓库搜 persist/remember 无命中；它只在**本次会话内**把用户拖过的
-- 宽度记在 `state.window.last_user_width`），nvim 核心也只有 `:mksession` 那套整会话布局 —— 管不到
-- neo-tree 这种 nofile 侧栏。所以这里用一小块状态补齐：
--   ~/.local/state/nvim/neotree-width  ← 退出（VimLeavePre）时写下当时树的列数；
--                                        下次启动把它当 `window.width` 用（见下面 neo-tree 配置）。
-- 只管宽度；树开着还是关着、展开了哪些目录都不在这个范围里。
-- 想恢复「永远 34 列」：删掉这个文件再启动一次即可（或把下面 window.width 写死）。
local function neotree_state_path()
  return vim.fs.joinpath(vim.fn.stdpath("state"), "neotree-width")
end

local function read_saved_neotree_width()
  local f = io.open(neotree_state_path(), "r")
  if not f then
    return nil
  end
  local n = tonumber(f:read("*l"))
  f:close()
  if not n then
    return nil
  end
  -- 夹一下：太窄没意义，太宽会把编辑区挤没（也防这个文件被手改坏）
  return math.max(10, math.min(math.floor(n), math.max(10, math.floor(vim.o.columns * 0.5))))
end

local saved_tree_width = read_saved_neotree_width() or 34

-- ── 文件浏览器：neo-tree（左侧树）─────────────────────────────────────────
-- 形态：普通分栏侧栏（position 默认 "left"，宽度见下面 window）。占位、不盖代码。
-- 2026-09-17 用户要求：回到刚装 neo-tree 时那个 split window 的样子 —— 之前那套
-- 「左侧浮窗 + 跟随 winborder 的圆角四边框 + 标题嵌线」（提交 c038b06）整块撤掉，
-- apply_custom_hl 里的 FloatBorder/FloatTitle 两行也一并去掉（浮窗边框回默认色）。
require("neo-tree").setup({
  close_if_last_window = true,
  -- 会话恢复时把会话文件里那份「坏的」neo-tree 缓冲区清掉（nofile 侧栏会被 :mksession
  -- 原样记进会话，恢复出来是个不能用的树）。上面 resession 那段会恢复会话，所以打开它。
  auto_clean_after_session_restore = true,
  popup_border_style = "rounded",
  enable_git_status = true,
  filesystem = {
    filtered_items = { hide_dotfiles = false, hide_gitignored = false },
    follow_current_file = { enabled = true }, -- 光标换文件时树自动定位
    -- netrw 上面已全局关掉，这里再关掉 neo-tree 自带的 netrw 劫持：
    -- 它在被劫持的目录 buffer 上会留下 E216（无害但脏），改用下面的 VimEnter 按需打开。
    hijack_netrw_behavior = "disabled",
  },
  window = { width = saved_tree_width }, -- 左侧分栏宽度：上次退出时的值（见上面那段说明；没有记录时 = 34）
  default_component_configs = {
    indent = { with_expanders = true },
  },
})
map("n", "<leader>e", "<cmd>Neotree toggle<cr>", { desc = "File explorer" })
map("n", "<leader>E", "<cmd>Neotree reveal<cr>", { desc = "Reveal current file in explorer" })

-- 启动时自动展开左侧树（工作目录栏，像 VSCode 那样常驻，三种起法都开）：
--   `nvim`                    → 根 = 当前目录
--   `nvim <目录>`             → 根 = 该目录（并把工作目录切过去）
--   `nvim <文件>`             → 根 = 当前目录；文件不在当前目录底下时改用文件所在目录
--                               （否则 follow_current_file 会一直弹“文件不在 cwd”的确认框）
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    local arg = vim.fn.argv(0)
    local isdir = arg ~= "" and vim.fn.isdirectory(arg) == 1
    local cwd = vim.fn.getcwd()
    local dir

    if isdir then
      dir = vim.fn.fnamemodify(arg, ":p")
      -- `nvim <目录>` 时第一个 buffer 就是那个目录（netrw 已关、neo-tree 的劫持也关了，没人接管它）：
      -- 换成空 buffer 并把目录 buffer 删掉，免得 bufferline 上多出一条。
      -- （工作目录不用自己切：neo-tree 默认 bind_to_cwd = true，树根变化时它会自己 tcd 过去）
      vim.cmd("enew")
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        local name = vim.api.nvim_buf_get_name(b)
        if name ~= "" and vim.fn.isdirectory(name) == 1 then
          vim.api.nvim_buf_delete(b, { force = true })
        end
      end
    else
      dir = cwd
      if arg ~= "" then
        local file = vim.fn.fnamemodify(arg, ":p")
        if vim.fn.stridx(file, cwd .. "/") ~= 0 then
          dir = vim.fn.fnamemodify(file, ":h")
        end
      end
    end

    vim.cmd("Neotree show dir=" .. vim.fn.fnameescape(dir))
  end,
})

-- 退出时把左侧树的当前宽度记到状态文件（下次启动拿它当 window.width，见上面那段说明）。
-- 用 VimLeavePre 而不是 VimLeave：这个时机窗口还在（VimLeave 时已经关掉了）。
-- 树当时是关着的话就不写，保留上一次的记录。
vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == "neo-tree" then
        vim.fn.mkdir(vim.fn.stdpath("state"), "p")
        local f = io.open(neotree_state_path(), "w")
        if f then
          f:write(("%d\n"):format(vim.api.nvim_win_get_width(w)))
          f:close()
        end
        break
      end
    end
  end,
})

-- ── 查找：Telescope（搜文件用 fd、搜文本用 ripgrep，两个都在 PATH 里）──────
require("telescope").setup({
  defaults = {
    path_display = { "smart" },
    file_ignore_patterns = { "^%.git/" },
    layout_strategy = "horizontal",
  },
  pickers = {
    find_files = { hidden = true },
  },
})
map("n", "<leader>ff", "<cmd>Telescope find_files<cr>", { desc = "Find files" })
map("n", "<leader>fg", "<cmd>Telescope live_grep<cr>", { desc = "Live grep" })
map("n", "<leader>fw", "<cmd>Telescope grep_string<cr>", { desc = "Grep word under cursor" })
map("n", "<leader>fb", "<cmd>Telescope buffers<cr>", { desc = "Open buffers" })
map("n", "<leader>fr", "<cmd>Telescope oldfiles<cr>", { desc = "Recent files" })
map("n", "<leader>fc", "<cmd>Telescope commands<cr>", { desc = "Commands" })
map("n", "<leader>fh", "<cmd>Telescope help_tags<cr>", { desc = "Help tags" })

-- ── 快捷键提示：which-key（按 <leader> 停一下会列出可用键）────────────────
require("which-key").setup({ preset = "classic", delay = 300 })
require("which-key").add({
  { "<leader>b", group = "Buffer" },
  { "<leader>f", group = "Find" },
})

-- ── 缩进对齐线：indent-blankline（模块名 ibl，v3）──────────────────────────
-- 插件由 Nix 提供（home.nix 顶部的 nvimPlugins 列表 → 由 lazy 加载），
-- 这里只写配置；颜色不在这里 —— 见上面 apply_custom_hl 的 IblIndent / IblScope
-- （要用跟壁纸走的那套调色板，所以跟主题一起重设）。
-- 上游默认（v3.9.1）：indent.char = "▎"（左侧 1/8 方块）、scope 打开且带首尾标记；
-- 这里改成细实线 "│"（与窗口分隔线用同一个符号，「用符号划区块」更统一），
-- scope 保留但去掉首尾标记 —— 缩进线 + 分隔线本身就够了，不需要额外装饰。
-- 渲染走 extmark 的 virt_text（ibl/init.lua: nvim_buf_set_extmark + virt_text_pos="overlay"），
-- 与 list/listchars 无关，所以不会把 listchars 那套制表符视觉开关带进来。
require("ibl").setup({
  indent = { char = "│" },
  scope = { enabled = true, show_start = false, show_end = false },
  -- 这些窗口里画缩进线只是噪声（列表/弹层/终端并不表示代码缩进）；
  -- buftypes（terminal/nofile/prompt/quickfix）上游默认已排除，这里只补 filetypes。
  exclude = {
    filetypes = { "neo-tree", "wk", "help", "lazy", "mason", "telescope", "NvimTree" },
  },
})

-- ── 自动配对：nvim-autopairs ───────────────────────────────────────────────
-- 输入 ( [ { " ' 时自动补上右半边、光标停在中间；再敲一次同样的右括号 = 直接跳过它。
-- 插件由 Nix 提供（home.nix 顶部的 nvimPlugins 列表），这里用上游默认值：
-- 默认已在 TelescopePrompt / vim 里关掉，不需要额外设置。
-- 想调节见 `:h nvim-autopairs`：map_cr = true（在括号里按回车自动换行缩进）、
-- fast_wrap（把已有的一段文字用括号包起来）、disable_filetype / disable_in_macro 等。
require("nvim-autopairs").setup({})

-- ── 常用快捷键 ────────────────────────────────────────────────────────────
map("n", "<Esc>", "<cmd>nohlsearch<cr>", { desc = "Clear search highlight" })
map({ "n", "i", "v" }, "<C-s>", "<cmd>w<cr>", { desc = "Save" })
map("n", "<leader>w", "<cmd>w<cr>", { desc = "Save" })
map("n", "<leader>q", "<cmd>q<cr>", { desc = "Quit" })
-- 窗口之间跳转 / 调大小（Ctrl 系；Hyprland 侧的字母 hjkl 键位已于 2026-09-16 全部取消）
map("n", "<C-h>", "<C-w>h", { desc = "Left window" })
map("n", "<C-j>", "<C-w>j", { desc = "Down window" })
map("n", "<C-k>", "<C-w>k", { desc = "Up window" })
map("n", "<C-l>", "<C-w>l", { desc = "Right window" })
map("n", "<C-Up>", "<cmd>resize +2<cr>", { desc = "Taller window" })
map("n", "<C-Down>", "<cmd>resize -2<cr>", { desc = "Shorter window" })
map("n", "<C-Left>", "<cmd>vertical resize -2<cr>", { desc = "Narrower window" })
map("n", "<C-Right>", "<cmd>vertical resize +2<cr>", { desc = "Wider window" })
-- 缩进后保持选中；可视模式上下移动选中行
map("v", "<", "<gv", { desc = "Decrease indent" })
map("v", ">", ">gv", { desc = "Increase indent" })
map("v", "J", ":m '>+1<cr>gv=gv", { desc = "Move selection down" })
map("v", "K", ":m '<-2<cr>gv=gv", { desc = "Move selection up" })
