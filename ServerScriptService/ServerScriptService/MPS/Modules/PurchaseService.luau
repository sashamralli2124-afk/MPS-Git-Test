local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Catalog = require(
	ReplicatedStorage
		:WaitForChild("MPS")
		:WaitForChild("Modules")
		:WaitForChild("PurchaseCatalog")
)

local CareerConfig = require(
	ReplicatedStorage
		:WaitForChild("MPS")
		:WaitForChild("Modules")
		:WaitForChild("CareerProgressionConfig")
)

local RewardConfig = require(
	ReplicatedStorage
		:WaitForChild("MPS")
		:WaitForChild("Modules")
		:WaitForChild("SongRewardConfig")
)

local ProfileService = require(
	ServerScriptService
		:WaitForChild("MPS")
		:WaitForChild("Modules")
		:WaitForChild("Network")
		:WaitForChild("PlayerProfileService")
)

local purchasePush = ReplicatedStorage
	:WaitForChild("MPS")
	:WaitForChild("Remotes")
	:WaitForChild("PurchasePush")

local careerPush = ReplicatedStorage
	:WaitForChild("MPS")
	:WaitForChild("Remotes")
	:WaitForChild("SongPerformancePush")

local PurchaseService = {}

local busy = {}

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end

	local result = {}

	for key, child in pairs(value) do
		result[deepCopy(key)] = deepCopy(child)
	end

	return result
end

local function roundCash(value)
	if type(RewardConfig.RoundCash) == "function" then
		return RewardConfig.RoundCash(value)
	end

	value = math.max(0, tonumber(value) or 0)
	return math.floor((value * 100) + 0.5) / 100
end

local function reconcile(profile)
	if type(profile.Progression) ~= "table" then
		profile.Progression = {}
	end

	if type(profile.Progression.Unlocks) ~= "table" then
		profile.Progression.Unlocks = {}
	end

	if type(profile.Progression.Purchases) ~= "table" then
		profile.Progression.Purchases = {}
	end

	if type(profile.Economy) ~= "table" then
		profile.Economy = {}
	end

	profile.Economy.Cash = roundCash(profile.Economy.Cash)
	profile.Economy.LifetimeEarnings = roundCash(profile.Economy.LifetimeEarnings)
	profile.Economy.LifetimeSpending = roundCash(profile.Economy.LifetimeSpending)

	if type(profile.Career) ~= "table" then
		profile.Career = {}
	end

	profile.Career.XP = math.max(
		0,
		math.floor(tonumber(profile.Career.XP) or 0)
	)

	profile.Career.Level = CareerConfig.GetLevelFromXP(profile.Career.XP)
end

local function publicTotals(profile)
	local progress = CareerConfig.GetProgress(profile.Career.XP)
	local totalStreams = 0
	local releaseCount = 0

	for _, release in ipairs(profile.Music.Releases or {}) do
		releaseCount += 1

		if type(release.Performance) == "table" then
			totalStreams += math.max(
				0,
				math.floor(tonumber(release.Performance.Streams) or 0)
			)
		end
	end

	return {
		Cash = roundCash(profile.Economy.Cash),
		LifetimeEarnings = roundCash(profile.Economy.LifetimeEarnings),
		LifetimeSpending = roundCash(profile.Economy.LifetimeSpending),
		Fans = math.max(0, math.floor(tonumber(profile.Career.Fans) or 0)),
		Reputation = math.max(
			0,
			math.floor(tonumber(profile.Career.Reputation) or 0)
		),
		Level = progress.Level,
		XP = progress.TotalXP,
		XPCurrent = progress.CurrentXP,
		XPToNext = progress.XPToNext,
		XPProgress = progress.Fraction,
		TotalStreams = totalStreams,
		Releases = releaseCount,
	}
end

local function publicPurchases(profile)
	return deepCopy(profile.Progression.Purchases)
end

local function buildState(profile)
	reconcile(profile)

	local level = profile.Career.Level
	local cash = roundCash(profile.Economy.Cash)
	local purchases = publicPurchases(profile)
	local items = {}

	for _, definition in ipairs(Catalog.GetAll()) do
		local owned = purchases[definition.Id] ~= nil
		local requiredLevel = math.max(
			1,
			math.floor(tonumber(definition.RequiredLevel) or 1)
		)
		local price = roundCash(definition.Price)

		table.insert(items, {
			Id = definition.Id,
			Name = definition.Name,
			Description = definition.Description,
			Category = definition.Category,
			Price = price,
			RequiredLevel = requiredLevel,
			UnlockId = definition.UnlockId,
			Order = definition.Order,
			Owned = owned,
			CanLevel = level >= requiredLevel,
			CanAfford = cash + 0.0001 >= price,
		})
	end

	return {
		Version = 1,
		Cash = cash,
		Level = level,
		LifetimeSpending = roundCash(profile.Economy.LifetimeSpending),
		Purchases = purchases,
		Items = items,
	}
end

function PurchaseService:GetState(player)
	local profile = ProfileService:Get(player)
	reconcile(profile)
	return buildState(profile)
end

function PurchaseService:Owns(player, itemId)
	local profile = ProfileService:Get(player)
	reconcile(profile)

	return profile.Progression.Purchases[tostring(itemId or "")] ~= nil
end

function PurchaseService:HasUnlock(player, unlockId)
	local profile = ProfileService:Get(player)
	reconcile(profile)

	return profile.Progression.Unlocks[tostring(unlockId or "")] ~= nil
end

function PurchaseService:Buy(player, itemId)
	if busy[player.UserId] then
		return false, "PURCHASE_BUSY"
	end

	busy[player.UserId] = true

	local definition = Catalog.Get(itemId)

	if not definition then
		busy[player.UserId] = nil
		return false, "ITEM_NOT_FOUND"
	end

	local itemKey = tostring(definition.Id or "")
	local unlockId = tostring(definition.UnlockId or "")
	local price = roundCash(definition.Price)
	local requiredLevel = math.max(
		1,
		math.floor(tonumber(definition.RequiredLevel) or 1)
	)

	local purchaseRecord = nil
	local totals = nil
	local finalState = nil
	local failure = nil

	local success, err = ProfileService:Mutate(player, function(profile)
		reconcile(profile)

		if profile.Progression.Purchases[itemKey] ~= nil then
			failure = "ALREADY_OWNED"
			return
		end

		if profile.Career.Level < requiredLevel then
			failure = "LEVEL_REQUIRED"
			return
		end

		if profile.Economy.Cash + 0.0001 < price then
			failure = "NOT_ENOUGH_CASH"
			return
		end

		profile.Economy.Cash = roundCash(profile.Economy.Cash - price)
		profile.Economy.LifetimeSpending = roundCash(
			profile.Economy.LifetimeSpending + price
		)

		purchaseRecord = {
			ItemId = itemKey,
			Name = tostring(definition.Name or itemKey),
			Category = tostring(definition.Category or "General"),
			PricePaid = price,
			PurchasedAt = os.time(),
			UnlockId = unlockId,
			Source = "CashPurchase",
		}

		profile.Progression.Purchases[itemKey] = deepCopy(purchaseRecord)

		if unlockId ~= "" and profile.Progression.Unlocks[unlockId] == nil then
			profile.Progression.Unlocks[unlockId] = {
				Id = unlockId,
				Name = tostring(definition.Name or itemKey),
				Description = tostring(definition.Description or ""),
				UnlockedAt = purchaseRecord.PurchasedAt,
				Source = "Purchase",
				SourceId = itemKey,
			}
		end

		totals = publicTotals(profile)
		finalState = buildState(profile)
	end)

	busy[player.UserId] = nil

	if not success then
		return false, tostring(err or "PURCHASE_MUTATION_FAILED")
	end

	if failure then
		return false, failure
	end

	ProfileService:SavePlayer(player, false)

	if player.Parent then
		purchasePush:FireClient(player, {
			Type = "Purchased",
			Item = deepCopy(purchaseRecord),
			State = deepCopy(finalState),
			Totals = deepCopy(totals),
		})

		-- Reuse the existing career totals pipeline so the always-visible HUD,
		-- Career app and Music summary all see cash change immediately.
		careerPush:FireClient(player, {
			Releases = {},
			Totals = deepCopy(totals),
			Reason = "Purchase",
		})
	end

	return true, {
		Item = deepCopy(purchaseRecord),
		State = deepCopy(finalState),
		Totals = deepCopy(totals),
	}
end

return PurchaseService
