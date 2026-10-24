return {
  "vyfor/cord.nvim",
  enabled = vim.fn.has("wsl") ~= 1,
  event = "VeryLazy",
  config = function()
    require("cord").setup({
      display = {
        view = "auto",
        theme = "catppuccin",
        flavor = "dark",
        show_cursor = true,
      },

      idle = {
        enabled = true,
        timeout = 300000,
      },

      buttons = {
        {
          label = "View Repository",
          url = function(opts)
            return opts.repo_url
          end,
        },
      },

      text = {
        editing = function(opts)
          local text = "Editing " .. opts.filename
          if vim.bo.modified then
            text = text .. " [+]"
          end
          return text
        end,
        viewing = function(opts)
          return "Viewing " .. opts.filename
        end,
        workspace = function(opts)
          return "In " .. opts.workspace
        end,
      },
    })
  end,
}
