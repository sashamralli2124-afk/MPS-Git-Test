local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(
    ReplicatedStorage
        :WaitForChild("MPS")
        :WaitForChild("Modules")
        :WaitForChild("CareerProgressionConfig")
)
local CareerProgressionService = {}
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
function CareerProgressionService:Reconcile(profile)
    if type(profile) ~= "table" then
        return false
    end
    local changed = false
    if type(profile.Career) ~= "table" then
        profile.Career = {}
        changed = true
    end
    if type(profile.Progression) ~= "table" then
        profile.Progression = {}
        changed = true
    end
    if type(profile.Progression.Unlocks) ~= "table" then
        profile.Progression.Unlocks = {}
        changed = true
    end
    local career = profile.Career
    local sanitizedXP = math.max(0, math.floor(tonumber(career.XP) or 0))
    if career.XP ~= sanitizedXP then
        career.XP = sanitizedXP
        changed = true
    end
    local sanitizedFans = math.max(0, math.floor(tonumber(career.Fans) or 0))
    if career.Fans ~= sanitizedFans then
        career.Fans = sanitizedFans
        changed = true
    end
    local sanitizedReputation = math.max(
        0,
        math.floor(tonumber(career.Reputation) or 0)
    )
    if career.Reputation ~= sanitizedReputation then
        career.Reputation = sanitizedReputation
        changed = true
    end
    local sanitizedMomentum = math.max(0, tonumber(career.Momentum) or 0)
    if career.Momentum ~= sanitizedMomentum then
        career.Momentum = sanitizedMomentum
        changed = true
    end
    local expectedLevel = Config.GetLevelFromXP(career.XP)
    if career.Level ~= expectedLevel then
        career.Level = expectedLevel
        changed = true
    end
    return changed
end
function CareerProgressionService:EvaluateUnlocks(profile)
    self:Reconcile(profile)
    local unlocks = profile.Progression.Unlocks
    local level = profile.Career.Level
    local newUnlocks = {}
    for _, definition in ipairs(Config.Unlocks) do
        local unlockId = tostring(definition.Id or "")
        local requiredLevel = math.max(
            1,
            math.floor(tonumber(definition.Level) or 1)
        )
        if unlockId ~= ""
            and level >= requiredLevel
            and unlocks[unlockId] == nil
        then
            local entry = {
                Id = unlockId,
                Name = tostring(definition.Name or unlockId),
                Description = tostring(definition.Description or ""),
                Level = requiredLevel,
                UnlockedAt = os.time(),
                Source = "CareerLevel",
            }
            unlocks[unlockId] = deepCopy(entry)
            table.insert(newUnlocks, entry)
        end
    end
    return newUnlocks
end
function CareerProgressionService:ApplyXP(profile, amount)
    self:Reconcile(profile)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    local oldLevel = profile.Career.Level
    if amount > 0 then
        profile.Career.XP += amount
    end
    profile.Career.Level = Config.GetLevelFromXP(profile.Career.XP)
    local newUnlocks = self:EvaluateUnlocks(profile)
    local progress = Config.GetProgress(profile.Career.XP)
    return {
        XPAdded = amount,
        OldLevel = oldLevel,
        NewLevel = profile.Career.Level,
        LeveledUp = profile.Career.Level > oldLevel,
        NewUnlocks = newUnlocks,
        Progress = progress,
    }
end
function CareerProgressionService:GetPublic(profile)
    self:Reconcile(profile)
    local progress = Config.GetProgress(profile.Career.XP)
    return {
        Level = progress.Level,
        XP = progress.TotalXP,
        XPCurrent = progress.CurrentXP,
        XPToNext = progress.XPToNext,
        XPProgress = progress.Fraction,
        Fans = profile.Career.Fans,
        Reputation = profile.Career.Reputation,
        Momentum = profile.Career.Momentum,
        Unlocks = deepCopy(profile.Progression.Unlocks),
    }
end
return CareerProgressionService
