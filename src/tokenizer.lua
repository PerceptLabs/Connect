local M = {}

function M.estimate_tokens(text)
   if not text then return 0 end
   local len = #text
   return math.ceil(len / 2.8) -- Conservative heuristic
end

return M
