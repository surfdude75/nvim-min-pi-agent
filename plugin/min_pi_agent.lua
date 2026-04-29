if vim.g.loaded_min_pi_agent == 1 then
  return
end
vim.g.loaded_min_pi_agent = 1

require("min_pi_agent").setup({})
