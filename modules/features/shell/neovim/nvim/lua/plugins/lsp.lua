return {
  {
    "mason-org/mason.nvim",
    opts = {},
  },

  {
    "mason-org/mason-lspconfig.nvim",
    dependencies = {
      "mason-org/mason.nvim",
      "neovim/nvim-lspconfig",
    },
    opts = {
      automatic_enable = {
        exclude = { "qmlls" },
      },

      ensure_installed = {
        "lua_ls",

        "html",
        "cssls",
        "ts_ls",
        "tailwindcss",
        "eslint",
        "jsonls",
        "emmet_language_server",
      },
    },
  },

  {
    "neovim/nvim-lspconfig",
    config = function()
      -- Lua
      vim.lsp.config("lua_ls", {
        settings = {
          Lua = {
            diagnostics = {
              globals = { "vim" },
            },
          },
        },
      })

      -- QML
      vim.lsp.config("qmlls", {
        cmd = { "qmlls" },
        filetypes = { "qml", "qmljs" },
      })

      vim.lsp.enable("qmlls")
    end,
  },
}
