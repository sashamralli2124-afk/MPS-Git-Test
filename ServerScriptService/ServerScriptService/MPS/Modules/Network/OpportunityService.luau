local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Registry = require(
	ReplicatedStorage
		:WaitForChild("MPS")
		:WaitForChild("Modules")
		:WaitForChild("Network")
		:WaitForChild("NetworkRegistry")
)

local ProfileService = require(
	ServerScriptService
		:WaitForChild("MPS")
		:WaitForChild("Modules")
		:WaitForChild("Network")
		:WaitForChild("PlayerProfileService")
)

local EventService = require(
	ServerScriptService
		:WaitForChild("MPS")
		:WaitForChild("Modules")
		:WaitForChild("Network")
		:WaitForChild("NetworkEventService")
)

local OpportunityService = {}

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end

	local copy = {}

	for key, child in pairs(value) do
		copy[deepCopy(key)] = deepCopy(child)
	end

	return copy
end

local function trim(array, maximum)
	while #array > maximum do
		table.remove(array)
	end
end

function OpportunityService:Create(player, payload)
	payload = type(payload) == "table" and payload or {}

	local opportunity = {
		OpportunityId = HttpService:GenerateGUID(false),
		Type = tostring(payload.Type or "General"),
		Title = tostring(payload.Title or "New Opportunity"),
		Description = tostring(payload.Description or ""),
		Status = "Open",
		CreatedAt = os.time(),
		ExpiresAt = math.max(0, math.floor(tonumber(payload.ExpiresAt) or 0)),
		SourceType = tostring(payload.SourceType or ""),
		SourceId = tostring(payload.SourceId or ""),
		Rewards = type(payload.Rewards) == "table" and deepCopy(payload.Rewards) or {},
		Data = type(payload.Data) == "table" and deepCopy(payload.Data) or {},
	}

	local success, err = ProfileService:Mutate(player, function(profile)
		table.insert(profile.Network.Opportunities, 1, opportunity)
		trim(profile.Network.Opportunities, Registry.Limits.MaxOpportunities)
	end)

	if not success then
		return false, err
	end

	EventService:Emit(player, "Opportunity.Created", {
		Title = opportunity.Title,
		Body = opportunity.Description,
		SourceType = opportunity.SourceType,
		SourceId = opportunity.OpportunityId,
		Data = {
			OpportunityType = opportunity.Type,
		},
	})

	return true, deepCopy(opportunity)
end

function OpportunityService:SetStatus(player, opportunityId, status)
	if type(opportunityId) ~= "string" then
		return false, "BAD_OPPORTUNITY_ID"
	end

	local allowed = {
		Open = true,
		Accepted = true,
		Completed = true,
		Declined = true,
		Expired = true,
	}

	if allowed[status] ~= true then
		return false, "BAD_STATUS"
	end

	local found = nil

	local success, err = ProfileService:Mutate(player, function(profile)
		for _, opportunity in ipairs(profile.Network.Opportunities) do
			if opportunity.OpportunityId == opportunityId then
				opportunity.Status = status
				opportunity.UpdatedAt = os.time()
				found = opportunity
				break
			end
		end
	end)

	if not success then
		return false, err
	end

	if not found then
		return false, "NOT_FOUND"
	end

	EventService:Emit(player, "Opportunity.Updated", {
		Title = found.Title,
		Body = "Status: " .. status,
		SourceType = found.SourceType,
		SourceId = opportunityId,
		Data = {
			Status = status,
		},
	})

	return true, deepCopy(found)
end

function OpportunityService:List(player)
	local profile = ProfileService:Get(player)
	return deepCopy(profile.Network.Opportunities)
end

return OpportunityService
