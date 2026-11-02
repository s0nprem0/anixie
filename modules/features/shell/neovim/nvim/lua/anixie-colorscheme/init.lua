local M = {}

local function read_file(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()
  return content
end

local function read_palette()
  local state_dir = vim.fn.expand("~/.local/state/anixie/theme")
  local palette_path = state_dir .. "/live/palette.json"
  local content = read_file(palette_path)
  if not content then
    return nil
  end
  local ok, palette = pcall(vim.json.decode, content)
  if not ok or type(palette) ~= "table" then
    return nil
  end
  return palette
end

function M.load()
  vim.cmd("highlight clear")
  if vim.fn.exists("syntax_on") == 1 then
    vim.cmd("syntax reset")
  end
  vim.o.background = "dark"
  vim.o.termguicolors = true
  vim.g.colors_name = "anixie"

  local p = read_palette()
  if not p then
    return
  end

  local bg = p.background or "#1e1e2e"
  local fg = p.foreground or "#cdd6f4"
  local surface = p.surface or "#313244"
  local surface_container = p.surfaceContainer or "#45475a"
  local surface_variant = p.surfaceVariant or "#585b70"
  local muted = p.muted or "#6c7086"
  local outline = p.outline or "#6c7086"
  local primary = p.primary or "#89b4fa"
  local accent = p.accent or "#89dceb"
  local accent_alt = p.accentAlt or "#cba6f7"
  local secondary = p.secondary or "#cba6f7"
  local tertiary = p.tertiary or "#f9e2af"
  local success = p.success or "#a6e3a1"
  local yellow = p.yellow or "#f9e2af"
  local danger = p.danger or "#f38ba8"
  local error = p.error or "#f38ba8"

  local function hl(group, opts)
    vim.api.nvim_set_hl(0, group, opts)
  end

  -- UI
  hl("Normal", { fg = fg, bg = bg })
  hl("NormalFloat", { fg = fg, bg = surface })
  hl("FloatBorder", { fg = outline, bg = surface })
  hl("Cursor", { fg = bg, bg = primary })
  hl("CursorLine", { bg = surface })
  hl("CursorColumn", { bg = surface })
  hl("LineNr", { fg = muted })
  hl("CursorLineNr", { fg = primary, bold = true })
  hl("SignColumn", { bg = bg })
  hl("VertSplit", { fg = surface_variant })
  hl("WinSeparator", { fg = surface_variant })
  hl("StatusLine", { fg = fg, bg = surface })
  hl("StatusLineNC", { fg = muted, bg = surface })
  hl("TabLine", { fg = muted, bg = surface })
  hl("TabLineSel", { fg = fg, bg = surface_container })
  hl("TabLineFill", { bg = surface })
  hl("Pmenu", { fg = fg, bg = surface })
  hl("PmenuSel", { fg = bg, bg = primary })
  hl("PmenuSbar", { bg = surface_container })
  hl("PmenuThumb", { bg = primary })
  hl("Search", { fg = bg, bg = yellow })
  hl("IncSearch", { fg = bg, bg = primary })
  hl("Visual", { bg = surface_variant })
  hl("MatchParen", { fg = accent, bold = true })
  hl("Folded", { fg = muted, bg = surface })
  hl("FoldColumn", { fg = muted, bg = bg })
  hl("NonText", { fg = muted })
  hl("SpecialKey", { fg = muted })
  hl("Whitespace", { fg = surface_variant })
  hl("Directory", { fg = primary })
  hl("Title", { fg = primary, bold = true })
  hl("ErrorMsg", { fg = error })
  hl("WarningMsg", { fg = yellow })
  hl("MoreMsg", { fg = success })
  hl("Question", { fg = accent })

  -- Syntax
  hl("Comment", { fg = muted, italic = true })
  hl("Constant", { fg = accent_alt })
  hl("String", { fg = success })
  hl("Character", { fg = success })
  hl("Number", { fg = accent_alt })
  hl("Boolean", { fg = accent_alt })
  hl("Float", { fg = accent_alt })
  hl("Identifier", { fg = fg })
  hl("Function", { fg = accent })
  hl("Statement", { fg = primary })
  hl("Conditional", { fg = primary })
  hl("Repeat", { fg = primary })
  hl("Label", { fg = primary })
  hl("Operator", { fg = muted })
  hl("Keyword", { fg = primary, italic = true })
  hl("Exception", { fg = primary })
  hl("PreProc", { fg = accent })
  hl("Include", { fg = accent })
  hl("Define", { fg = accent })
  hl("Macro", { fg = accent })
  hl("PreCondit", { fg = accent })
  hl("Type", { fg = tertiary })
  hl("StorageClass", { fg = tertiary })
  hl("Structure", { fg = tertiary })
  hl("Typedef", { fg = tertiary })
  hl("Special", { fg = accent_alt })
  hl("SpecialChar", { fg = accent_alt })
  hl("Tag", { fg = primary })
  hl("Delimiter", { fg = muted })
  hl("SpecialComment", { fg = muted, italic = true })
  hl("Debug", { fg = danger })
  hl("Underlined", { underline = true })
  hl("Error", { fg = error })
  hl("Todo", { fg = bg, bg = yellow, bold = true })

  -- LSP
  hl("DiagnosticError", { fg = error })
  hl("DiagnosticWarn", { fg = yellow })
  hl("DiagnosticInfo", { fg = accent })
  hl("DiagnosticHint", { fg = success })
  hl("DiagnosticUnderlineError", { undercurl = true, sp = error })
  hl("DiagnosticUnderlineWarn", { undercurl = true, sp = yellow })
  hl("DiagnosticUnderlineInfo", { undercurl = true, sp = accent })
  hl("DiagnosticUnderlineHint", { undercurl = true, sp = success })

  -- Git
  hl("GitSignsAdd", { fg = success })
  hl("GitSignsChange", { fg = yellow })
  hl("GitSignsDelete", { fg = danger })
  hl("DiffAdd", { bg = surface_container })
  hl("DiffChange", { bg = surface })
  hl("DiffDelete", { fg = danger, bg = surface })
  hl("DiffText", { bg = surface_variant })

  -- Treesitter (common groups)
  hl("@comment", { link = "Comment" })
  hl("@string", { link = "String" })
  hl("@number", { link = "Number" })
  hl("@boolean", { link = "Boolean" })
  hl("@function", { link = "Function" })
  hl("@keyword", { link = "Keyword" })
  hl("@type", { link = "Type" })
  hl("@variable", { fg = fg })
  hl("@property", { fg = fg })
  hl("@parameter", { fg = fg })
  hl("@operator", { link = "Operator" })
  hl("@punctuation", { link = "Delimiter" })
  hl("@constant", { link = "Constant" })
  hl("@constructor", { fg = accent })

  -- Snacks
  hl("SnacksNormal", { fg = fg, bg = surface })
  hl("SnacksBorder", { fg = outline, bg = surface })

  -- FzfLua
  hl("FzfLuaNormal", { fg = fg, bg = surface })
  hl("FzfLuaBorder", { fg = outline, bg = surface })
  hl("FzfLuaCursorLine", { bg = surface_container })
end

-- Auto-reload when theme changes
vim.api.nvim_create_autocmd("Signal", {
  pattern = "USR1",
  callback = function()
    if vim.g.colors_name == "anixie" then
      M.load()
    end
  end,
})

return M
