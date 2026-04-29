if vim.g.loaded_min_pi_ai == 1 then
  return
end
vim.g.loaded_min_pi_ai = 1

require("min_pi_ai").setup({})
