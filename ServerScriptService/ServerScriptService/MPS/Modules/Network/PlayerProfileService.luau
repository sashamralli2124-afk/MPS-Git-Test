local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Schema = require(
	ReplicatedStorage
		:WaitForChild("MPS")
		:WaitForChild("Modules")
		:WaitForChild("Network")
		:WaitForChild("PlayerProfileSchema")
)

local PlayerProfileService = {}

local PROFILE_STORE_NAME = "MPS_PlayerProfile_v1"
local LEGACY_SONG_STORE_NAME = "MPS_SongProjects_v1"

local profileStore = DataStoreService:GetDataStore(PROFILE_STORE_NAME)
local legacySongStore = DataStoreService:GetDataStore(LEGACY_SONG_STORE_NAME)

local cache = {}
local loaded = {}
local dirty = {}
local loading = {}

local function keyFor(userId)
	return "player_" .. tostring(userId)
end

local function legacySongKeyFor(userId)
	return "player_" .. tostring(userId)
end

function PlayerProfileService:GetPersistenceMode()
	if RunService:IsStudio() then
		return "SESSION"
	end

	return "DATASTORE"
end

function PlayerProfileService:IsLoaded(player)
	return loaded[player.UserId] == true
end

function PlayerProfileService:LoadPlayer(player)
	local userId = player.UserId

	if loaded[userId] and cache[userId] then
		return cache[userId]
	end

	while loading[userId] do
		task.wait()
	end

	if loaded[userId] and cache[userId] then
		return cache[userId]
	end

	loading[userId] = true

	local profile = nil

	if RunService:IsStudio() then
		profile = Schema.New()
	else
		local success, result = pcall(function()
			return profileStore:GetAsync(keyFor(userId))
		end)

		if success and type(result) == "table" then
			profile = result
		elseif not success then
			warn(
				"PlayerProfileService GetAsync failed for "
					.. player.Name
					.. ": "
					.. tostring(result)
			)
		end

		if type(profile) ~= "table" then
			profile = Schema.New()
		end
	end

	profile = Schema.Reconcile(profile)

	-- One-way migration path from the separate Phase 2 song store.
	-- This preserves old live song projects if any ever existed there.
	if not RunService:IsStudio()
		and profile.Meta.LegacySongProjectsImported ~= true
		and #profile.Music.Projects == 0
	then
		local success, legacy = pcall(function()
			return legacySongStore:GetAsync(legacySongKeyFor(userId))
		end)

		if success
			and type(legacy) == "table"
			and type(legacy.Projects) == "table"
			and #legacy.Projects > 0
		then
			profile.Music.Projects = Schema.DeepCopy(legacy.Projects)
			dirty[userId] = true

			print(
				"MPS imported "
					.. tostring(#legacy.Projects)
					.. " legacy song project(s) for "
					.. player.Name
			)
		end

		profile.Meta.LegacySongProjectsImported = true
		dirty[userId] = true
	end

	profile.Meta.UpdatedAt = os.time()

	cache[userId] = profile
	loaded[userId] = true
	loading[userId] = nil

	return profile
end

function PlayerProfileService:Get(player)
	return self:LoadPlayer(player)
end

function PlayerProfileService:MarkDirty(player)
	dirty[player.UserId] = true

	local profile = cache[player.UserId]

	if profile then
		profile.Meta.UpdatedAt = os.time()
	end
end

function PlayerProfileService:Mutate(player, callback)
	if type(callback) ~= "function" then
		return false, "CALLBACK_REQUIRED"
	end

	local profile = self:LoadPlayer(player)

	local success, result = pcall(function()
		return callback(profile)
	end)

	if not success then
		warn(
			"PlayerProfileService mutation failed for "
				.. player.Name
				.. ": "
				.. tostring(result)
		)

		return false, tostring(result)
	end

	self:MarkDirty(player)

	return true, result
end

function PlayerProfileService:SavePlayer(player, force)
	local userId = player.UserId
	local profile = cache[userId]

	if not profile then
		return true, "NO_PROFILE"
	end

	if not force and dirty[userId] ~= true then
		return true, "CLEAN"
	end

	profile.Meta.UpdatedAt = os.time()

	if RunService:IsStudio() then
		dirty[userId] = false
		return true, "SESSION"
	end

	local payload = Schema.DeepCopy(profile)

	local success, err = pcall(function()
		profileStore:UpdateAsync(keyFor(userId), function()
			return payload
		end)
	end)

	if not success then
		warn(
			"PlayerProfileService UpdateAsync failed for "
				.. player.Name
				.. ": "
				.. tostring(err)
		)

		return false, tostring(err)
	end

	dirty[userId] = false

	return true, "DATASTORE"
end

function PlayerProfileService:SaveDirtyPlayers()
	for _, player in ipairs(Players:GetPlayers()) do
		if dirty[player.UserId] == true then
			self:SavePlayer(player, false)
		end
	end
end

function PlayerProfileService:GetOwnSnapshot(player)
	local profile = self:LoadPlayer(player)

	return {
		Version = profile.Version,
		Meta = {
			CreatedAt = profile.Meta.CreatedAt,
			UpdatedAt = profile.Meta.UpdatedAt,
		},

		Music = Schema.DeepCopy(profile.Music),
		Career = Schema.DeepCopy(profile.Career),
		Economy = Schema.DeepCopy(profile.Economy),

		Network = {
			UnreadNotifications = profile.Network.UnreadNotifications,
		},

		Progression = Schema.DeepCopy(profile.Progression),
		Computer = Schema.DeepCopy(profile.Computer),
	}
end

function PlayerProfileService:ReleasePlayer(player)
	self:SavePlayer(player, true)

	cache[player.UserId] = nil
	loaded[player.UserId] = nil
	dirty[player.UserId] = nil
	loading[player.UserId] = nil
end

return PlayerProfileService
