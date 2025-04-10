-- lua/jujutsu/utils.lua
-- Utility functions

local Utils = {}

-- Helper function to extract a change ID from a line
function Utils.extract_change_id(line)
	if not line then return nil end

	-- Look for an email address and get the word before it (which should be the change ID)
	local id = line:match("([a-z]+)%s+[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+%.[a-zA-Z0-9-.]+")

	-- Check if it's a valid 8-letter change ID
	if id and #id == 8 then
		return id
	end

	return nil
end

return Utils
