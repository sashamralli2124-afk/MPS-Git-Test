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
local ProgressionService = require(
    ServerScriptService
        :WaitForChild("MPS")
        :WaitForChild("Modules")
        :WaitForChild("CareerProgressionService")
)
local RewardService = {}
local function trim(array, maximum)
    while #array > maximum do
        table.remove(array)
    end
end
function RewardService:Grant(player, transaction)
    if type(transaction) ~= "table" then
        return false, "TRANSACTION_REQUIRED"
    end
    local transactionId = transaction.TransactionId
    if type(transactionId) ~= "string" or transactionId == "" then
        return false, "TRANSACTION_ID_REQUIRED"
    end
    local cash = math.max(0, tonumber(transaction.Cash) or 0)
    local fans = math.max(0, math.floor(tonumber(transaction.Fans) or 0))
    local xp = math.max(0, math.floor(tonumber(transaction.XP) or 0))
    local momentum = math.max(0, tonumber(transaction.Momentum) or 0)
    local reputation = math.max(0, math.floor(tonumber(transaction.Reputation) or 0))
    local duplicate = false
    local resultTotals = nil
    local levelBefore = nil
    local levelAfter = nil
    local newUnlocks = {}
    local success, err = ProfileService:Mutate(player, function(profile)
        ProgressionService:Reconcile(profile)
        for _, entry in ipairs(profile.Network.RewardLedger) do
            if entry.TransactionId == transactionId then
                duplicate = true
                return
            end
        end
        levelBefore = math.max(1, math.floor(tonumber(profile.Career.Level) or 1))
        profile.Economy.Cash += cash
        profile.Economy.LifetimeEarnings += cash
        profile.Career.Fans += fans
        profile.Career.Momentum += momentum
        profile.Career.Reputation += reputation
        local progressionResult = ProgressionService:ApplyXP(profile, xp)
        levelAfter = progressionResult.NewLevel
        newUnlocks = progressionResult.NewUnlocks or {}
        table.insert(profile.Network.RewardLedger, 1, {
            TransactionId = transactionId,
            Reason = tostring(transaction.Reason or "Reward"),
            SourceType = tostring(transaction.SourceType or ""),
            SourceId = tostring(transaction.SourceId or ""),
            Cash = cash,
            Fans = fans,
            XP = xp,
            Momentum = momentum,
            Reputation = reputation,
            Timestamp = os.time(),
        })
        trim(profile.Network.RewardLedger, Registry.Limits.MaxRewardLedger)
        resultTotals = {
            Cash = profile.Economy.Cash,
            Fans = profile.Career.Fans,
            XP = profile.Career.XP,
            Momentum = profile.Career.Momentum,
            Reputation = profile.Career.Reputation,
            Level = profile.Career.Level,
        }
    end)
    if not success then
        return false, err
    end
    if duplicate then
        return true, {
            Duplicate = true,
        }
    end
    if levelBefore and levelAfter and levelAfter > levelBefore then
        EventService:Emit(player, "Career.LevelUp", {
            Title = "Career Level " .. tostring(levelAfter),
            Body = "Your music career leveled up.",
            SourceType = "Career",
            SourceId = tostring(levelAfter),
            Data = {
                OldLevel = levelBefore,
                NewLevel = levelAfter,
                XP = resultTotals and resultTotals.XP or 0,
            },
        })
    end
    for _, unlock in ipairs(newUnlocks) do
        EventService:Emit(player, "World.Unlock", {
            Title = "Unlocked: " .. tostring(unlock.Name or unlock.Id),
            Body = tostring(unlock.Description or "A new career unlock is available."),
            SourceType = "CareerUnlock",
            SourceId = tostring(unlock.Id),
            Data = unlock,
        })
    end
    EventService:Emit(player, "Reward.Granted", {
        Title = tostring(transaction.Title or "Reward received"),
        Body = tostring(transaction.Body or transaction.Reason or ""),
        SourceType = tostring(transaction.SourceType or ""),
        SourceId = tostring(transaction.SourceId or ""),
        Reward = {
            Cash = cash,
            Fans = fans,
            XP = xp,
            Momentum = momentum,
            Reputation = reputation,
        },
    })
    ProfileService:SavePlayer(player, false)
    return true, {
        Duplicate = false,
        Granted = {
            Cash = cash,
            Fans = fans,
            XP = xp,
            Momentum = momentum,
            Reputation = reputation,
        },
        Totals = resultTotals,
    }
end
return RewardService
