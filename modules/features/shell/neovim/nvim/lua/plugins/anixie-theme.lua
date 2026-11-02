return {
  {
    dir = vim.fn.stdpath("config") .. "/lua/anixie-colorscheme",
    name = "anixie",
    lazy = false,
    priority = 1000,
    config = function()
      local ok, theme = pcall(require, "anixie-colorscheme")
      if ok and theme.load then
        theme.load()
      end
    end,
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "anixie",
    },
  },
  {
    "catppuccin/nvim",
    enabled = false,
  },
}
