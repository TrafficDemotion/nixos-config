-- ═══════════════════════════════════════════════════════════════════════════
-- paan 的 Neovim 基本配置
--
-- 这个文件是声明式的：home.nix 的 programs.neovim.initLua 用
-- builtins.readFile ./nvim/init.lua 读它，生成的 ~/.config/nvim/init.lua
-- 是指向 /nix/store 的【只读软链】。
--   * 改配置 = 改这个文件，然后：sudo nixos-rebuild switch --flake /etc/nixos#nixos
--   * 插件同样由 Nix 提供（home.nix 的 programs.neovim.plugins），
--     没有 lazy.nvim 之类的运行时插件管理器，不联网拉插件、不做 :TSInstall 现编。
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
opt.sidescrolloff = 8
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

-- ── 颜色主题：Catppuccin Mocha（和 kitty 的配色同一套）─────────────────────
-- 2026-09-15 按用户要求回滚：不再读 Caelestia 渲染的壁纸取色，固定用 catppuccin 自带的
-- Mocha（旧的动态方案见 nvim/init.lua.bak-20260913-caelestia-colours）。
require("catppuccin").setup({
  flavour = "mocha",
  integrations = {
    telescope = true,
    neotree = true,
    which_key = true,
  },
})
vim.cmd.colorscheme("catppuccin")

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

-- ── 文件浏览器：neo-tree（左侧树）─────────────────────────────────────────
require("neo-tree").setup({
  close_if_last_window = true,
  popup_border_style = "rounded",
  enable_git_status = true,
  filesystem = {
    filtered_items = { hide_dotfiles = false, hide_gitignored = false },
    follow_current_file = { enabled = true }, -- 光标换文件时树自动定位
    -- netrw 上面已全局关掉，这里再关掉 neo-tree 自带的 netrw 劫持：
    -- 它在被劫持的目录 buffer 上会留下 E216（无害但脏），改用下面的 VimEnter 按需打开。
    hijack_netrw_behavior = "disabled",
  },
  window = { width = 34 },
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

-- ── 常用快捷键 ────────────────────────────────────────────────────────────
map("n", "<Esc>", "<cmd>nohlsearch<cr>", { desc = "Clear search highlight" })
map({ "n", "i", "v" }, "<C-s>", "<cmd>w<cr>", { desc = "Save" })
map("n", "<leader>w", "<cmd>w<cr>", { desc = "Save" })
map("n", "<leader>q", "<cmd>q<cr>", { desc = "Quit" })
-- 窗口之间跳转 / 调大小（Ctrl 系；SUPER+hjkl 归 Hyprland 管）
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
