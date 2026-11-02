local has_fd = vim.fn.executable("fd") == 1
local has_rg = vim.fn.executable("rg") == 1

return {
  "ibhagwan/fzf-lua",
  opts = function()
    local o = {
      winopts = {
        width = 0.8,
        height = 0.8,
        preview = {
          horizontal = "right:60%",
        },
      },
    }

    if has_fd then
      o.files = {
        fd_opts = "--hidden --no-ignore-vcs --strip-cwd-prefix",
      }
    end

    if has_rg then
      o.grep = {
        rg_opts = "--hidden --no-ignore-vcs --column --line-number --smart-case",
      }
    end

    return o
  end,
}
