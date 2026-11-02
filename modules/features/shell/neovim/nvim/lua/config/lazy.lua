-- LazyVim Bootstrap
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  -- bootstrap lazy.nvim
  -- stylua: ignore
  vim.fn.system({ "git", "clone", "--filter=blob:none", "https://github.com/folke/lazy.nvim.git", "--branch=stable", lazypath })
end
vim.opt.rtp:prepend(vim.env.LAZY or lazypath)

-- Check for Node.js (required by Mason LSPs for JS/TS/JSON/YAML/Tailwind/PHP)
if vim.fn.executable("node") == 0 then
  vim.schedule(function()
    vim.notify(
      "Node.js not found. LSP servers for TypeScript, JSON, Tailwind,"
        .. " PHP, YAML, and Prettier will fail to install via Mason."
        .. " Install with: sudo apt install nodejs npm",
      vim.log.levels.WARN,
      { title = "Mason LSP Warning" }
    )
  end)
end

require("lazy").setup({
  spec = {
    -- 1. Base LazyVim distribution
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },

    -- 2. Core Full-Stack & Mobile Ecosystem
    -- Provides robust LSP and snippets for React, React Native, Expo, and Node.js
    { import = "lazyvim.plugins.extras.lang.typescript" },

    -- Provides intelephense for robust Laravel and backend PHP support
    { import = "lazyvim.plugins.extras.lang.php" },

    -- Essential for managing package.json, mobile config files, and API responses
    { import = "lazyvim.plugins.extras.lang.json" },

    -- YAML: GitHub Actions, docker-compose, etc.
    { import = "lazyvim.plugins.extras.lang.yaml" },

    -- 3. UI/UX & Formatting
    -- Adds auto-sorting and inline color highlighting for component design
    { import = "lazyvim.plugins.extras.lang.tailwind" },

    -- Industry-standard formatting for JavaScript, TypeScript, and CSS
    { import = "lazyvim.plugins.extras.formatting.prettier" },

    -- Disable spectre (redundant with grug-far.nvim)
    { "nvim-pack/nvim-spectre", enabled = false },

    -- 4. Utility extras
    -- Jump/motion: press <leader>s then the target character
    { import = "lazyvim.plugins.extras.editor.leap" },

    -- Auto-session restore per project directory
    { import = "lazyvim.plugins.extras.util.project" },

    -- 5. Import your custom plugins (including themes and UI tweaks)
    { import = "plugins" },
  },
  defaults = {
    -- By default, only LazyVim plugins will be lazy-loaded.
    lazy = false,
    version = false, -- always use the latest git commit
  },
  install = { colorscheme = { "catppuccin" } },
  checker = { enabled = true }, -- automatically check for plugin updates
})
