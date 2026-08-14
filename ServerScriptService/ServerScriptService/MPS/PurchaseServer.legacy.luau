local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local request = ReplicatedStorage
	:WaitForChild("MPS")
	:WaitForChild("Remotes")
	:WaitForChild("PurchaseRequest")

local PurchaseService = require(
	ServerScriptService
		:WaitForChild("MPS")
		:WaitForChild("Modules")
		:WaitForChild("PurchaseService")
)

local lastRequestAt = {}

local function allowed(player)
	local now = os.clock()
	local last = lastRequestAt[player.UserId] or 0

	if now - last < 0.10 then
		return false
	end

	lastRequestAt[player.UserId] = now
	return true
end

request.OnServerInvoke = function(player, action, payload)
	if not allowed(player) then
		return {
			Success = false,
			Error = "RATE_LIMITED",
		}
	end

	if action == "GetState" then
		return {
			Success = true,
			State = PurchaseService:GetState(player),
		}
	end

	if action == "Buy" then
		local itemId = type(payload) == "table"
			and payload.ItemId
			or payload

		local success, resultOrError = PurchaseService:Buy(player, itemId)

		if not success then
			return {
				Success = false,
				Error = resultOrError,
				State = PurchaseService:GetState(player),
			}
		end

		return {
			Success = true,
			Result = resultOrError,
			State = resultOrError.State,
			Totals = resultOrError.Totals,
		}
	end

	return {
		Success = false,
		Error = "UNKNOWN_ACTION",
	}
end

Players.PlayerRemoving:Connect(function(player)
	lastRequestAt[player.UserId] = nil
end)

print("MPS purchase server ready")
