local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Config = require(
    ReplicatedStorage
        :WaitForChild("MPS")
        :WaitForChild("Modules")
        :WaitForChild("SongPerformanceConfig")
)
local RewardConfig = require(
    ReplicatedStorage
        :WaitForChild("MPS")
        :WaitForChild("Modules")
        :WaitForChild("SongRewardConfig")
)
local CareerConfig = require(
    ReplicatedStorage
        :WaitForChild("MPS")
        :WaitForChild("Modules")
        :WaitForChild("CareerProgressionConfig")
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
local pushRemote = ReplicatedStorage
    :WaitForChild("MPS")
    :WaitForChild("Remotes")
    :WaitForChild("SongPerformancePush")
local SongPerformanceService = {}
local function stableHash(text)
    text = tostring(text or "")
    local hash = 2166136261
    for index = 1, #text do
        hash = bit32.bxor(hash, string.byte(text, index))
        hash = (hash * 16777619) % 4294967296
    end
    return hash
end
local function potentialForRelease(releaseId)
    local hash = stableHash(releaseId)
    local normalized = (hash % 10001) / 10000
    return Config.MinPotential
        + ((Config.MaxPotential - Config.MinPotential) * normalized)
end
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
local function ensurePerformance(release, now)
    local changed = false
    if type(release.Performance) ~= "table" then
        release.Performance = {}
        changed = true
    end
    local performance = release.Performance
    local releaseId = tostring(release.ReleaseId or release.ProjectId or "")
    if tonumber(performance.Version) ~= Config.Version then
        performance.Version = Config.Version
        changed = true
    end
    if type(performance.Streams) ~= "number" then
        performance.Streams = math.max(0, math.floor(tonumber(performance.Streams) or 0))
        changed = true
    else
        performance.Streams = math.max(0, math.floor(performance.Streams))
    end
    if type(performance.RecentStreams) ~= "number" then
        performance.RecentStreams = 0
        changed = true
    end
    if type(performance.StreamsPerMinute) ~= "number" then
        performance.StreamsPerMinute = 0
        changed = true
    end
    if type(performance.PeakStreamsPerMinute) ~= "number" then
        performance.PeakStreamsPerMinute = 0
        changed = true
    end
    if type(performance.Momentum) ~= "number" then
        performance.Momentum = Config.StartingMomentum
        changed = true
    end
    performance.Momentum = math.clamp(
        performance.Momentum,
        Config.MinMomentum,
        Config.MaxMomentum
    )
    if type(performance.Potential) ~= "number" then
        performance.Potential = potentialForRelease(releaseId)
        changed = true
    end
    performance.Potential = math.clamp(
        performance.Potential,
        Config.MinPotential,
        Config.MaxPotential
    )
    if type(performance.FractionalCarry) ~= "number" then
        performance.FractionalCarry = 0
        changed = true
    end
    if type(performance.HighestMilestone) ~= "number" then
        performance.HighestMilestone = 0
        changed = true
    end
    if type(performance.LastCalculatedAt) ~= "number"
        or performance.LastCalculatedAt <= 0
    then
        performance.LastCalculatedAt = now
        changed = true
    end
    if type(performance.StartedAt) ~= "number" or performance.StartedAt <= 0 then
        performance.StartedAt = now
        changed = true
    end
    if type(performance.LastUpdatedAt) ~= "number" then
        performance.LastUpdatedAt = now
        changed = true
    end
    if type(performance.AgeFactor) ~= "number" then
        performance.AgeFactor = Config.GetAgeFactor(performance.StartedAt, now)
        changed = true
    end
    local expectedLabel = Config.GetMomentumLabel(performance.Momentum)
    if performance.MomentumLabel ~= expectedLabel then
        performance.MomentumLabel = expectedLabel
        changed = true
    end
    return performance, changed
end
local function ensureRewards(release, performance, now)
    local changed = false
    if type(release.Rewards) ~= "table" then
        release.Rewards = {}
        changed = true
    end
    local rewards = release.Rewards
    if tonumber(rewards.Version) ~= RewardConfig.Version then
        rewards.Version = RewardConfig.Version
        changed = true
    end
    if type(rewards.SettledStreams) ~= "number" then
        if RewardConfig.BackfillExistingStreams then
            rewards.SettledStreams = 0
        else
            rewards.SettledStreams = math.max(
                0,
                math.floor(tonumber(performance.Streams) or 0)
            )
        end
        changed = true
    end
    rewards.SettledStreams = math.max(0, math.floor(rewards.SettledStreams))
    if type(rewards.CashEarned) ~= "number" then
        rewards.CashEarned = 0
        changed = true
    end
    rewards.CashEarned = RewardConfig.RoundCash(rewards.CashEarned)
    if type(rewards.FansEarned) ~= "number" then
        rewards.FansEarned = 0
        changed = true
    end
    rewards.FansEarned = math.max(0, math.floor(rewards.FansEarned))
    if type(rewards.ReputationEarned) ~= "number" then
        rewards.ReputationEarned = 0
        changed = true
    end
    rewards.ReputationEarned = math.max(0, math.floor(rewards.ReputationEarned))
    if type(rewards.XPEarned) ~= "number" then
        rewards.XPEarned = 0
        changed = true
    end
    rewards.XPEarned = math.max(0, math.floor(rewards.XPEarned))
    if type(rewards.CashCarry) ~= "number" then
        rewards.CashCarry = 0
        changed = true
    end
    if type(rewards.FanCarry) ~= "number" then
        rewards.FanCarry = 0
        changed = true
    end
    if type(rewards.ReputationCarry) ~= "number" then
        rewards.ReputationCarry = 0
        changed = true
    end
    if type(rewards.XPCarry) ~= "number" then
        rewards.XPCarry = 0
        changed = true
    end
    if type(rewards.LastSettledAt) ~= "number" then
        rewards.LastSettledAt = now
        changed = true
    end
    return rewards, changed
end
local function calculateTargetMomentum(release, performance, now)
    local releaseId = tostring(release.ReleaseId or release.ProjectId or "")
    local seed = stableHash(releaseId)
    local phase = ((now + (seed % 997)) % 7200) / 7200
    local wave = math.sin(phase * math.pi * 2)
    local secondWave = math.sin((phase * math.pi * 4) + ((seed % 31) / 10))
    local ageFactor = Config.GetAgeFactor(performance.StartedAt, now)
    local agePenalty = (1 - ageFactor) * Config.AgeMomentumPenalty
    local potentialContribution = (performance.Potential - 1) * 70
    local target = Config.StartingMomentum
        + potentialContribution
        + (wave * 11)
        + (secondWave * 5)
        - agePenalty
    return math.clamp(target, Config.MinMomentum, Config.MaxMomentum)
end
local function calculateRate(performance, now)
    local ageFactor = Config.GetAgeFactor(performance.StartedAt, now)
    local momentumFactor = 0.52 + ((performance.Momentum / 100) * 1.08)
    local rate = Config.BaseStreamsPerMinute
        * momentumFactor
        * performance.Potential
        * ageFactor
    return math.max(0, rate), ageFactor
end
local function highestCrossedMilestone(previousStreams, newStreams, previousHighest)
    local crossed = nil
    for _, milestone in ipairs(Config.StreamMilestones) do
        if milestone > previousHighest
            and previousStreams < milestone
            and newStreams >= milestone
        then
            crossed = milestone
        end
    end
    return crossed
end
local function settleRewards(performance, rewards, now)
    local currentStreams = math.max(
        0,
        math.floor(tonumber(performance.Streams) or 0)
    )
    local settledStreams = math.max(
        0,
        math.floor(tonumber(rewards.SettledStreams) or 0)
    )
    if currentStreams <= settledStreams then
        return {
            Streams = 0,
            Cash = 0,
            Fans = 0,
            Reputation = 0,
            XP = 0,
        }, false
    end
    local newStreams = currentStreams - settledStreams
    local exactCash = (newStreams * RewardConfig.CashPerStream)
        + math.max(0, tonumber(rewards.CashCarry) or 0)
    local payoutCents = math.max(0, math.floor((exactCash * 100) + 0.000001))
    local cash = payoutCents / 100
    rewards.CashCarry = math.max(0, exactCash - cash)
    local exactFans = (newStreams * RewardConfig.FansPerStream)
        + math.max(0, tonumber(rewards.FanCarry) or 0)
    local fans = math.max(0, math.floor(exactFans))
    rewards.FanCarry = math.max(0, exactFans - fans)
    local exactReputation = (newStreams * RewardConfig.ReputationPerStream)
        + math.max(0, tonumber(rewards.ReputationCarry) or 0)
    local reputation = math.max(0, math.floor(exactReputation))
    rewards.ReputationCarry = math.max(0, exactReputation - reputation)
    local exactXP = (newStreams * RewardConfig.XPPerStream)
        + math.max(0, tonumber(rewards.XPCarry) or 0)
    local xp = math.max(0, math.floor(exactXP))
    rewards.XPCarry = math.max(0, exactXP - xp)
    rewards.SettledStreams = currentStreams
    rewards.CashEarned = RewardConfig.RoundCash(
        (tonumber(rewards.CashEarned) or 0) + cash
    )
    rewards.FansEarned = math.max(
        0,
        math.floor((tonumber(rewards.FansEarned) or 0) + fans)
    )
    rewards.ReputationEarned = math.max(
        0,
        math.floor((tonumber(rewards.ReputationEarned) or 0) + reputation)
    )
    rewards.XPEarned = math.max(
        0,
        math.floor((tonumber(rewards.XPEarned) or 0) + xp)
    )
    rewards.LastSettledAt = now
    return {
        Streams = newStreams,
        Cash = cash,
        Fans = fans,
        Reputation = reputation,
        XP = xp,
    }, true
end
local function publicPerformance(performance)
    return {
        Version = performance.Version,
        Streams = math.max(0, math.floor(tonumber(performance.Streams) or 0)),
        RecentStreams = math.max(0, math.floor(tonumber(performance.RecentStreams) or 0)),
        StreamsPerMinute = math.max(0, tonumber(performance.StreamsPerMinute) or 0),
        PeakStreamsPerMinute = math.max(0, tonumber(performance.PeakStreamsPerMinute) or 0),
        Momentum = math.clamp(
            tonumber(performance.Momentum) or 0,
            Config.MinMomentum,
            Config.MaxMomentum
        ),
        MomentumLabel = tostring(
            performance.MomentumLabel
                or Config.GetMomentumLabel(performance.Momentum)
        ),
        AgeFactor = math.clamp(tonumber(performance.AgeFactor) or 1, 0, 1),
        StartedAt = math.max(0, math.floor(tonumber(performance.StartedAt) or 0)),
        LastUpdatedAt = math.max(0, math.floor(tonumber(performance.LastUpdatedAt) or 0)),
        HighestMilestone = math.max(
            0,
            math.floor(tonumber(performance.HighestMilestone) or 0)
        ),
    }
end
local function publicRewards(rewards)
    return {
        Version = rewards.Version,
        SettledStreams = math.max(0, math.floor(tonumber(rewards.SettledStreams) or 0)),
        CashEarned = RewardConfig.RoundCash(rewards.CashEarned),
        FansEarned = math.max(0, math.floor(tonumber(rewards.FansEarned) or 0)),
        ReputationEarned = math.max(
            0,
            math.floor(tonumber(rewards.ReputationEarned) or 0)
        ),
        XPEarned = math.max(
            0,
            math.floor(tonumber(rewards.XPEarned) or 0)
        ),
        LastSettledAt = math.max(0, math.floor(tonumber(rewards.LastSettledAt) or 0)),
    }
end
local function publicTotals(profile)
    local progression = CareerConfig.GetProgress(profile.Career.XP)
    local totalStreams = 0
    local releaseCount = 0
    for _, release in ipairs(profile.Music.Releases or {}) do
        releaseCount += 1
        local performance = release.Performance
        if type(performance) == "table" then
            totalStreams += math.max(
                0,
                math.floor(tonumber(performance.Streams) or 0)
            )
        end
    end
    return {
        Cash = RewardConfig.RoundCash(profile.Economy.Cash),
        LifetimeEarnings = RewardConfig.RoundCash(profile.Economy.LifetimeEarnings),
        Fans = math.max(0, math.floor(tonumber(profile.Career.Fans) or 0)),
        Reputation = math.max(0, math.floor(tonumber(profile.Career.Reputation) or 0)),
        Level = progression.Level,
        XP = progression.TotalXP,
        XPCurrent = progression.CurrentXP,
        XPToNext = progression.XPToNext,
        XPProgress = progression.Fraction,
        TotalStreams = totalStreams,
        Releases = releaseCount,
    }
end
function SongPerformanceService:UpdatePlayer(player)
    if not player or not player.Parent then
        return false, "PLAYER_GONE"
    end
    local now = os.time()
    local updates = {}
    local milestoneEvents = {}
    local unlockEvents = {}
    local totals = nil
    local anyChanged = false
    local levelBefore = nil
    local levelAfter = nil
    local success, err = ProfileService:Mutate(player, function(profile)
        local reconciled = ProgressionService:Reconcile(profile)
        if reconciled then
            anyChanged = true
        end
        levelBefore = math.max(1, math.floor(tonumber(profile.Career.Level) or 1))
        local releases = profile.Music and profile.Music.Releases
        if type(releases) ~= "table" or #releases == 0 then
            levelAfter = levelBefore
            totals = publicTotals(profile)
            return
        end
        for _, release in ipairs(releases) do
            local releaseId = tostring(release.ReleaseId or "")
            if releaseId ~= "" then
                local performance, performanceReconciled = ensurePerformance(release, now)
                local rewards, rewardsReconciled = ensureRewards(release, performance, now)
                local previousStreams = math.max(
                    0,
                    math.floor(tonumber(performance.Streams) or 0)
                )
                local elapsed = now - math.floor(performance.LastCalculatedAt)
                elapsed = math.clamp(elapsed, 0, Config.MaxCatchupSeconds)
                local changed = performanceReconciled or rewardsReconciled
                if elapsed > 0 then
                    local targetMomentum = calculateTargetMomentum(
                        release,
                        performance,
                        now
                    )
                    local oldMomentum = performance.Momentum
                    local response = math.clamp(
                        Config.MomentumResponse * math.max(1, elapsed / Config.TickSeconds),
                        0,
                        0.55
                    )
                    performance.Momentum = oldMomentum
                        + ((targetMomentum - oldMomentum) * response)
                    performance.Momentum = math.clamp(
                        performance.Momentum,
                        Config.MinMomentum,
                        Config.MaxMomentum
                    )
                    local rate, ageFactor = calculateRate(performance, now)
                    local exactStreams = ((rate * elapsed) / 60)
                        + performance.FractionalCarry
                    local streamDelta = math.max(0, math.floor(exactStreams))
                    performance.FractionalCarry = exactStreams - streamDelta
                    performance.Streams = previousStreams + streamDelta
                    performance.RecentStreams = streamDelta
                    performance.StreamsPerMinute = rate
                    performance.PeakStreamsPerMinute = math.max(
                        performance.PeakStreamsPerMinute,
                        rate
                    )
                    performance.AgeFactor = ageFactor
                    performance.MomentumLabel = Config.GetMomentumLabel(
                        performance.Momentum
                    )
                    performance.LastCalculatedAt = now
                    performance.LastUpdatedAt = now
                    changed = true
                end
                local payout, payoutChanged = settleRewards(performance, rewards, now)
                if payoutChanged then
                    profile.Economy.Cash = RewardConfig.RoundCash(
                        profile.Economy.Cash + payout.Cash
                    )
                    profile.Economy.LifetimeEarnings = RewardConfig.RoundCash(
                        profile.Economy.LifetimeEarnings + payout.Cash
                    )
                    profile.Career.Fans += payout.Fans
                    profile.Career.Reputation += payout.Reputation
                    local progressionResult = ProgressionService:ApplyXP(
                        profile,
                        payout.XP
                    )
                    for _, unlock in ipairs(progressionResult.NewUnlocks or {}) do
                        table.insert(unlockEvents, unlock)
                    end
                    changed = true
                end
                local crossed = highestCrossedMilestone(
                    previousStreams,
                    performance.Streams,
                    performance.HighestMilestone
                )
                if crossed then
                    performance.HighestMilestone = crossed
                    changed = true
                    table.insert(milestoneEvents, {
                        ReleaseId = releaseId,
                        Name = tostring(release.Name or "Untitled Beat"),
                        Milestone = crossed,
                        Streams = performance.Streams,
                        Rewards = publicRewards(rewards),
                    })
                end
                if changed then
                    anyChanged = true
                    table.insert(updates, {
                        ReleaseId = releaseId,
                        SourceProjectId = release.SourceProjectId or release.ProjectId,
                        Name = tostring(release.Name or "Untitled Beat"),
                        Performance = publicPerformance(performance),
                        Rewards = publicRewards(rewards),
                    })
                end
            end
        end
        levelAfter = math.max(
            1,
            math.floor(tonumber(profile.Career.Level) or levelBefore or 1)
        )
        totals = publicTotals(profile)
    end)
    if not success then
        return false, tostring(err)
    end
    if anyChanged and player.Parent then
        pushRemote:FireClient(player, {
            ServerTime = now,
            Releases = deepCopy(updates),
            Totals = deepCopy(totals),
        })
    end
    if levelBefore and levelAfter and levelAfter > levelBefore then
        local levelsGained = levelAfter - levelBefore
        EventService:Emit(player, "Career.LevelUp", {
            Title = "Career Level " .. tostring(levelAfter),
            Body = levelsGained > 1
                and ("You jumped " .. tostring(levelsGained) .. " levels.")
                or "Your music career leveled up.",
            SourceType = "Career",
            SourceId = tostring(levelAfter),
            Data = {
                OldLevel = levelBefore,
                NewLevel = levelAfter,
                XP = totals and totals.XP or 0,
            },
        })
    end
    for _, unlock in ipairs(unlockEvents) do
        EventService:Emit(player, "World.Unlock", {
            Title = "Unlocked: " .. tostring(unlock.Name or unlock.Id),
            Body = tostring(unlock.Description or "A new career unlock is available."),
            SourceType = "CareerUnlock",
            SourceId = tostring(unlock.Id),
            Data = deepCopy(unlock),
        })
    end
    for _, milestone in ipairs(milestoneEvents) do
        local formatted = tostring(milestone.Milestone)
        if milestone.Milestone >= 1000000 then
            formatted = tostring(math.floor(milestone.Milestone / 1000000)) .. "M"
        elseif milestone.Milestone >= 1000 then
            formatted = tostring(math.floor(milestone.Milestone / 1000)) .. "K"
        end
        local rewardText = "$"
            .. string.format("%.2f", milestone.Rewards.CashEarned or 0)
            .. " earned // "
            .. tostring(milestone.Rewards.FansEarned or 0)
            .. " fans"
        local emitted, emitError = EventService:Emit(
            player,
            "Music.StreamMilestone",
            {
                Title = formatted .. " streams: " .. milestone.Name,
                Body = rewardText,
                SourceType = "SongRelease",
                SourceId = milestone.ReleaseId,
                Data = {
                    ReleaseId = milestone.ReleaseId,
                    Name = milestone.Name,
                    Milestone = milestone.Milestone,
                    Streams = milestone.Streams,
                    CashEarned = milestone.Rewards.CashEarned,
                    FansEarned = milestone.Rewards.FansEarned,
                    ReputationEarned = milestone.Rewards.ReputationEarned,
                    XPEarned = milestone.Rewards.XPEarned,
                },
            }
        )
        if not emitted then
            warn(
                "Stream milestone event failed for "
                    .. player.Name
                    .. ": "
                    .. tostring(emitError)
            )
        end
    end
    return true, updates, totals
end
function SongPerformanceService:GetReleasePerformance(player, releaseId)
    local profile = ProfileService:Get(player)
    for _, release in ipairs(profile.Music.Releases or {}) do
        if tostring(release.ReleaseId or "") == tostring(releaseId or "") then
            local performance = release.Performance
            if type(performance) ~= "table" then
                return nil
            end
            return publicPerformance(performance)
        end
    end
    return nil
end
function SongPerformanceService:GetReleaseRewards(player, releaseId)
    local profile = ProfileService:Get(player)
    for _, release in ipairs(profile.Music.Releases or {}) do
        if tostring(release.ReleaseId or "") == tostring(releaseId or "") then
            local rewards = release.Rewards
            if type(rewards) ~= "table" then
                return nil
            end
            return publicRewards(rewards)
        end
    end
    return nil
end
return SongPerformanceService
