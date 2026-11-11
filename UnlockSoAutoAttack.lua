if _G.AutoAttackConnection then
    _G.AutoAttackConnection:Disconnect()
    _G.AutoAttackConnection = nil
end
_G.AutoAttackRunning = false
task.wait(0.1)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local Bindable = ReplicatedStorage:WaitForChild("Bindable")
local SendPet = Bindable:WaitForChild("SendPet")
local WithdrawPets = Bindable:WaitForChild("WithdrawPets")

local active = false
local anchorPos = nil
local currentTarget = nil
local maxRadius = 220
local stopDistance = 8

local function notify(msg, state)
    pcall(function()
        LocalPlayer.PlayerGui.MainGui.SendMessage:Fire(msg, state, false)
    end)
end

local function isValidEnemy(enemy)
    return enemy
        and enemy.Parent
        and enemy.PrimaryPart
        and CollectionService:HasTag(enemy, "Attackable")
        and not CollectionService:HasTag(enemy, "Untouchable")
end

local function arePetsOnTarget(target)
    local petsFolder = LocalPlayer:FindFirstChild("Pets")
    if not petsFolder then return false end

    local total = 0
    local onTarget = 0

    for _, slot in ipairs(petsFolder:GetChildren()) do
        local pet = slot:IsA("ObjectValue") and slot.Value
        if pet and pet.Parent and pet:FindFirstChild("Data") and pet.Data:FindFirstChild("Attacking") then
            total = total + 1
            if pet.Data.Attacking.Value == target then
                onTarget = onTarget + 1
            end
        end
    end

    if total == 0 then return true end
    return onTarget >= math.max(1, math.floor(total * 0.5))
end

local function getClosestEnemy()
    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return nil end

    local center = anchorPos or root.Position
    local best = nil
    local shortest = math.huge

    for _, enemy in ipairs(CollectionService:GetTagged("Attackable")) do
        if isValidEnemy(enemy) then
            local distArea = (enemy.PrimaryPart.Position - center).Magnitude
            if distArea <= maxRadius then
                local distPlayer = (enemy.PrimaryPart.Position - root.Position).Magnitude
                if distPlayer < shortest then
                    shortest = distPlayer
                    best = enemy
                end
            end
        end
    end

    return best
end

local function walkToTarget(enemy)
    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not root or not hum or not isValidEnemy(enemy) then return end

    local ePos = enemy.PrimaryPart.Position
    local diff = (root.Position - ePos) * Vector3.new(1, 0, 1)
    local dir = diff.Magnitude > 0.1 and diff.Unit or Vector3.new(0, 0, 1)
    local goal = ePos + (dir * stopDistance)

    if (root.Position - ePos).Magnitude > (stopDistance + 2) then
        hum:MoveTo(goal)
    end
end

_G.AutoAttackConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.X then
        active = not active
        if active then
            local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            anchorPos = root and root.Position or nil
            currentTarget = nil
            notify("AUTO ATTACK: ON", true)
        else
            currentTarget = nil
            pcall(function()
                WithdrawPets:Fire()
            end)
            notify("AUTO ATTACK: OFF", false)
        end
    end
end)

_G.AutoAttackRunning = true

task.spawn(function()
    while _G.AutoAttackRunning do
        if active then
            if not isValidEnemy(currentTarget) then
                currentTarget = getClosestEnemy()
                if currentTarget then
                    walkToTarget(currentTarget)
                    task.wait(0.15)
                    pcall(function()
                        SendPet:Fire(currentTarget, true, false)
                    end)
                end
            else
                walkToTarget(currentTarget)
                if not arePetsOnTarget(currentTarget) then
                    pcall(function()
                        SendPet:Fire(currentTarget, true, false)
                    end)
                end
            end
        end
        task.wait(0.2)
    end
end)
