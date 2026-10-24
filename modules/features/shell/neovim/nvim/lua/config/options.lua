-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

vim.g.mapleader = " "
vim.g.maplocalleader = ";"

vim.g.snacks_animate = false

vim.opt.wrap = true

vim.opt.list = true
vim.opt.listchars = { tab = "» ", trail = "·", nbsp = "␣" }

vim.opt.number = true
vim.opt.relativenumber = false

vim.opt.title = true
vim.opt.autoindent = true
vim.opt.smartindent = true
vim.opt.breakindent = true

vim.opt.expandtab = true -- convert tabs to spaces
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.softtabstop = 2

vim.opt.hlsearch = true
vim.opt.backup = false

vim.opt.cmdheight = 0
vim.opt.laststatus = 0
vim.opt.scrolloff = 10
vim.opt.inccommand = "split"

vim.opt.ignorecase = true

vim.opt.path:append({ "**" })
vim.opt.wildignore:append({ "*/node_modules/*" })

-- ignore files vim doesnt use
vim.opt.wildignore:append(".git,.hg,.svn")
vim.opt.wildignore:append("*.aux,*.out,*.toc")
vim.opt.wildignore:append("*.o,*.obj,*.exe,*.dll,*.manifest,*.rbc,*.class")
vim.opt.wildignore:append("*.ai,*.bmp,*.gif,*.ico,*.jpg,*.jpeg,*.png,*.psd,*.webp")
vim.opt.wildignore:append("*.avi,*.divx,*.mp4,*.webm,*.mov,*.m2ts,*.mkv,*.vob,*.mpg,*.mpeg")
vim.opt.wildignore:append("*.mp3,*.oga,*.ogg,*.wav,*.flac")
vim.opt.wildignore:append("*.eot,*.otf,*.ttf,*.woff")
vim.opt.wildignore:append("*.doc,*.pdf,*.cbr,*.cbz")
vim.opt.wildignore:append("*.zip,*.tar.gz,*.tar.bz2,*.rar,*.tar.xz,*.kgb")
vim.opt.wildignore:append("*.swp,*.lock,.DS_Store,._*")

vim.opt.splitkeep = "cursor"

-- Add asterisks in block comments
vim.opt.formatoptions:append({ "r" })

-- wsl cliboard support --
if vim.fn.has("wsl") == 1 then
  vim.g.clipboard = {
    name = "WslClipboard",
    copy = {
      ["+"] = "/mnt/c/Windows/System32/clip.exe",
      ["*"] = "/mnt/c/Windows/System32/clip.exe",
    },
    paste = {
      ["+"] = '/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoLogo -NoProfile -c [Console]::Out.Write($(Get-Clipboard -Raw).ToString().Replace("`r",""))',
      ["*"] = '/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoLogo -NoProfile -c [Console]::Out.Write($(Get-Clipboard -Raw).ToString().Replace("`r",""))',
    },
    cache_enabled = 0,
  }
  vim.opt.clipboard = "unnamedplus"
end
