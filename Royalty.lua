--!strict
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")

local LocalPlayer = Players.LocalPlayer

-- ============================================================================
-- 1. GERENCIADOR DE ESCOPO E CICLO DE VIDA (SCOPE / MAID)
-- ============================================================================
local Scope = {}
Scope.__index = Scope

function Scope.new()
    return setmetatable({
        _tasks = {},
        _destroyed = false
    }, Scope)
end

function Scope:Add(taskItem: any): any
    if self._destroyed then
        Scope._cleanItem(taskItem)
        return taskItem
    end
    table.insert(self._tasks, taskItem)
    return taskItem
end

function Scope:Connect(signal: RBXScriptSignal, fn: (...any) -> ()): RBXScriptConnection
    local conn = signal:Connect(fn)
    return self:Add(conn)
end

function Scope:NewChild(): any
    local child = Scope.new()
    self:Add(child)
    return child
end

function Scope._cleanItem(item: any)
    local itemType = typeof(item)
    if itemType == "RBXScriptConnection" then
        if item.Connected then
            item:Disconnect()
        end
    elseif itemType == "Instance" then
        pcall(function()
            item:Destroy()
        end)
    elseif itemType == "function" then
        pcall(item)
    elseif itemType == "thread" then
        pcall(task.cancel, item)
    elseif itemType == "table" then
        if type(item.Destroy) == "function" then
            pcall(function()
                item:Destroy()
            end)
        elseif type(item.Cancel) == "function" then
            pcall(function()
                item:Cancel()
            end)
        end
    end
end

function Scope:Clean()
    for i = #self._tasks, 1, -1 do
        local item = self._tasks[i]
        self._tasks[i] = nil
        Scope._cleanItem(item)
    end
end

function Scope:Destroy()
    if self._destroyed then return end
    self._destroyed = true
    self:Clean()
end

-- ============================================================================
-- 2. DEFINIÇÃO DA BIBLIOTECA E DESIGN SYSTEM (ROYALTY)
-- ============================================================================
local Royalty = {}
Royalty.__index = Royalty
Royalty.Name = "Royalty"
Royalty.Version = "2.0.0"

Royalty.Themes = {
    Dark = {
        Name = "Dark",
        Accent = Color3.fromRGB(94, 129, 244),
        Background = Color3.fromRGB(15, 16, 21),
        Sidebar = Color3.fromRGB(20, 22, 29),
        Surface = Color3.fromRGB(24, 27, 36),
        SurfaceElevated = Color3.fromRGB(31, 35, 47),
        SurfaceHover = Color3.fromRGB(37, 42, 56),
        Border = Color3.fromRGB(48, 53, 69),
        BorderSubtle = Color3.fromRGB(36, 40, 52),
        Text = Color3.fromRGB(242, 244, 248),
        SubText = Color3.fromRGB(168, 174, 190),
        Muted = Color3.fromRGB(112, 118, 136),
        Success = Color3.fromRGB(52, 199, 123),
        Warning = Color3.fromRGB(245, 166, 35),
        Error = Color3.fromRGB(239, 83, 80)
    },
    Light = {
        Name = "Light",
        Accent = Color3.fromRGB(59, 102, 228),
        Background = Color3.fromRGB(244, 246, 250),
        Sidebar = Color3.fromRGB(235, 238, 245),
        Surface = Color3.fromRGB(255, 255, 255),
        SurfaceElevated = Color3.fromRGB(240, 243, 249),
        SurfaceHover = Color3.fromRGB(229, 234, 244),
        Border = Color3.fromRGB(208, 214, 226),
        BorderSubtle = Color3.fromRGB(224, 228, 238),
        Text = Color3.fromRGB(22, 25, 34),
        SubText = Color3.fromRGB(78, 85, 102),
        Muted = Color3.fromRGB(128, 136, 155),
        Success = Color3.fromRGB(34, 163, 96),
        Warning = Color3.fromRGB(217, 130, 18),
        Error = Color3.fromRGB(214, 58, 55)
    }
}

Royalty.Tokens = {
    CornerRadius = {
        Window = UDim.new(0, 10),
        Section = UDim.new(0, 8),
        Control = UDim.new(0, 6),
        Pill = UDim.new(1, 0)
    },
    Font = {
        Bold = Enum.Font.GothamBold,
        Semibold = Enum.Font.GothamSemibold,
        Medium = Enum.Font.GothamMedium,
        Regular = Enum.Font.Gotham,
        Mono = Enum.Font.Code
    },
    TextSize = {
        WindowTitle = 15,
        PageTitle = 16,
        SectionTitle = 12,
        Control = 13,
        Description = 12,
        Small = 11
    },
    Animation = {
        Fast = 0.12,
        Normal = 0.18,
        Slow = 0.24,
        EasingStyle = Enum.EasingStyle.Quart,
        EasingDirection = Enum.EasingDirection.Out
    }
}

-- Estado de instância da biblioteca
Royalty._scope = Scope.new()
Royalty.Flags = {}
Royalty.Windows = {}
Royalty.Theme = table.clone(Royalty.Themes.Dark)
Royalty.ReducedMotion = false
Royalty.NotificationsEnabled = true
Royalty._themeListeners = {}
Royalty._activeTweens = setmetatable({}, { __mode = "k" })
Royalty._memoryStorage = {}
Royalty.StorageAdapter = nil

-- ============================================================================
-- 3. UTILITÁRIOS DE SEGURANÇA, CRIAÇÃO, TEMA E ANIMAÇÃO
-- ============================================================================
local function safeCall(label: string, fn: ((...any) -> ...any)?, ...: any): (boolean, any)
    if type(fn) ~= "function" then
        return true, nil
    end
    local args = table.pack(...)
    local ok, result = xpcall(function()
        return fn(table.unpack(args, 1, args.n))
    end, function(err)
        return debug.traceback(tostring(err), 2)
    end)
    if not ok then
        warn(string.format("[Royalty] Erro no callback '%s':\n%s", label, tostring(result)))
    end
    return ok, result
end

local function resolveParent(customParent: Instance?): Instance
    if typeof(customParent) == "Instance" then
        return customParent
    end
    local okHui, hui = pcall(function()
        return (gethui :: any) and (gethui :: any)()
    end)
    if okHui and typeof(hui) == "Instance" then
        return hui
    end
    local okCore, coreGui = pcall(function()
        return game:GetService("CoreGui")
    end)
    if okCore and coreGui then
        local canWrite = pcall(function()
            local probe = Instance.new("Folder")
            probe.Parent = coreGui
            probe:Destroy()
        end)
        if canWrite then
            return coreGui
        end
    end
    return LocalPlayer:WaitForChild("PlayerGui")
end

local function create(className: string, props: { [string]: any }?, children: { Instance }?): any
    local inst = Instance.new(className)
    if props then
        for k, v in pairs(props) do
            if k ~= "Parent" then
                (inst :: any)[k] = v
            end
        end
    end
    if children then
        for _, child in ipairs(children) do
            child.Parent = inst
        end
    end
    if props and props.Parent ~= nil then
        inst.Parent = props.Parent
    end
    return inst
end

function Royalty:Animate(instance: Instance, duration: number, props: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween?
    if not instance then return nil end

    local bucket = self._activeTweens[instance]
    if not bucket then
        bucket = {}
        self._activeTweens[instance] = bucket
    end

    for propName, _ in pairs(props) do
        local prevTween = bucket[propName]
        if prevTween then
            pcall(function()
                prevTween:Cancel()
            end)
            bucket[propName] = nil
        end
    end

    local actualDuration = self.ReducedMotion and 0 or (duration or self.Tokens.Animation.Normal)
    if actualDuration <= 0 then
        for propName, val in pairs(props) do
            pcall(function()
                (instance :: any)[propName] = val
            end)
        end
        return nil
    end

    local tweenObj = TweenService:Create(
        instance,
        TweenInfo.new(
            actualDuration,
            style or self.Tokens.Animation.EasingStyle,
            direction or self.Tokens.Animation.EasingDirection
        ),
        props
    )

    for propName, _ in pairs(props) do
        bucket[propName] = tweenObj
    end

    tweenObj.Completed:Connect(function()
        if self._activeTweens[instance] then
            for propName, _ in pairs(props) do
                if self._activeTweens[instance][propName] == tweenObj then
                    self._activeTweens[instance][propName] = nil
                end
            end
        end
    end)

    tweenObj:Play()
    return tweenObj
end

function Royalty:OnThemeChanged(scope: any, fn: (theme: { [string]: any }) -> ())
    local entry = { Scope = scope, Callback = fn }
    table.insert(self._themeListeners, entry)
    fn(self.Theme)
    if scope and type(scope.Add) == "function" then
        scope:Add(function()
            local idx = table.find(self._themeListeners, entry)
            if idx then
                table.remove(self._themeListeners, idx)
            end
        end)
    end
end

function Royalty:BindThemeProperty(scope: any, instance: Instance, property: string, tokenName: string)
    self:OnThemeChanged(scope, function(theme)
        if instance and instance.Parent ~= nil then
            local color = theme[tokenName]
            if color then
                self:Animate(instance, self.Tokens.Animation.Fast, { [property] = color })
            end
        end
    end)
    if self.Theme[tokenName] then
        (instance :: any)[property] = self.Theme[tokenName]
    end
end

function Royalty:_notifyThemeListeners()
    for i = #self._themeListeners, 1, -1 do
        local listener = self._themeListeners[i]
        if listener.Scope and listener.Scope._destroyed then
            table.remove(self._themeListeners, i)
        else
            safeCall("ThemeListener", listener.Callback, self.Theme)
        end
    end
end

function Royalty:SetTheme(themeNameOrTable: string | { [string]: any })
    local sourceTheme = nil
    if type(themeNameOrTable) == "string" then
        sourceTheme = self.Themes[themeNameOrTable]
    elseif type(themeNameOrTable) == "table" then
        sourceTheme = themeNameOrTable
    end

    if not sourceTheme then
        warn("[Royalty] Tema inválido informado em SetTheme: " .. tostring(themeNameOrTable))
        return
    end

    local currentAccent = self.Theme.Accent
    for k, v in pairs(sourceTheme) do
        self.Theme[k] = v
    end
    if type(themeNameOrTable) == "string" and currentAccent then
        self.Theme.Accent = currentAccent
    end

    self:_notifyThemeListeners()
end

function Royalty:SetAccentColor(newColor: Color3)
    if typeof(newColor) ~= "Color3" then
        warn("[Royalty] SetAccentColor requer um valor Color3.")
        return
    end
    self.Theme.Accent = newColor
    self:_notifyThemeListeners()
end

function Royalty:SetReducedMotion(enabled: boolean)
    self.ReducedMotion = (enabled == true)
    self.Flags["Royalty_ReducedMotion"] = self.ReducedMotion
end

local function formatKeyName(keyEnum: any): string
    if not keyEnum then return "None" end
    local name = tostring(keyEnum.Name or keyEnum)
    local shortNames = {
        RightShift = "RShift",
        LeftShift = "LShift",
        RightControl = "RCtrl",
        LeftControl = "LCtrl",
        RightAlt = "RAlt",
        LeftAlt = "LAlt",
        MouseButton1 = "MB1",
        MouseButton2 = "MB2",
        MouseButton3 = "MB3",
        Backspace = "Back",
        CapsLock = "Caps",
        Insert = "Ins",
        Delete = "Del",
        PageUp = "PgUp",
        PageDown = "PgDn",
        Return = "Enter"
    }
    return shortNames[name] or name
end

local function colorToHex(c: Color3): string
    return string.format(
        "#%02X%02X%02X",
        math.clamp(math.floor(c.R * 255 + 0.5), 0, 255),
        math.clamp(math.floor(c.G * 255 + 0.5), 0, 255),
        math.clamp(math.floor(c.B * 255 + 0.5), 0, 255)
    )
end

local function hexToColor(hex: string): Color3?
    local cleaned = string.gsub(hex, "^#", "")
    cleaned = string.gsub(cleaned, "%s+", "")
    if #cleaned ~= 6 or not string.match(cleaned, "^[0-9a-fA-F]+$") then
        return nil
    end
    local r = tonumber(string.sub(cleaned, 1, 2), 16)
    local g = tonumber(string.sub(cleaned, 3, 4), 16)
    local b = tonumber(string.sub(cleaned, 5, 6), 16)
    if not r or not g or not b then
        return nil
    end
    return Color3.fromRGB(r, g, b)
end

-- ============================================================================
-- 4. GERENCIAMENTO DE PERSISTÊNCIA (ADAPTADOR OPCIONAL + MEMÓRIA)
-- ============================================================================
function Royalty:SetStorageAdapter(adapter: { Save: (key: string, data: { [string]: any }) -> (boolean, string?), Load: (key: string) -> (boolean, any) }?)
    self.StorageAdapter = adapter
end

function Royalty:_serializeFlags(): { [string]: any }
    local out = {}
    for k, v in pairs(self.Flags) do
        local t = typeof(v)
        if t == "boolean" or t == "number" or t == "string" then
            out[k] = { Type = t, Value = v }
        elseif t == "Color3" then
            out[k] = { Type = "Color3", Value = colorToHex(v) }
        elseif t == "EnumItem" then
            out[k] = { Type = "EnumItem", EnumType = tostring(v.EnumType), Name = v.Name }
        elseif t == "table" then
            local copy = {}
            for tk, tv in pairs(v) do
                if type(tk) == "string" or type(tk) == "number" then
                    if type(tv) == "boolean" or type(tv) == "string" or type(tv) == "number" then
                        copy[tk] = tv
                    end
                end
            end
            out[k] = { Type = "table", Value = copy }
        end
    end
    return out
end

function Royalty:SaveConfiguration(profileName: string?): (boolean, string)
    local key = profileName or "Default"
    local payload = self:_serializeFlags()

    if self.StorageAdapter and type(self.StorageAdapter.Save) == "function" then
        local ok, status, err = safeCall("StorageAdapter.Save", self.StorageAdapter.Save, key, payload)
        if not ok or status == false then
            return false, tostring(err or "Falha ao gravar no StorageAdapter.")
        end
        return true, string.format("Perfil '%s' salvo via adaptador.", key)
    end

    self._memoryStorage[key] = payload
    return true, string.format("Perfil '%s' salvo na memória da sessão.", key)
end

function Royalty:LoadConfiguration(profileName: string?): (boolean, string)
    local key = profileName or "Default"
    local payload = nil

    if self.StorageAdapter and type(self.StorageAdapter.Load) == "function" then
        local ok, status, data = safeCall("StorageAdapter.Load", self.StorageAdapter.Load, key)
        if not ok or status == false or type(data) ~= "table" then
            return false, string.format("Não foi possível carregar o perfil '%s' do adaptador.", key)
        end
        payload = data
    else
        payload = self._memoryStorage[key]
    end

    if type(payload) ~= "table" then
        return false, string.format("Perfil '%s' não encontrado.", key)
    end

    for flagName, entry in pairs(payload) do
        if type(entry) == "table" then
            local decoded = nil
            if entry.Type == "boolean" or entry.Type == "number" or entry.Type == "string" or entry.Type == "table" then
                decoded = entry.Value
            elseif entry.Type == "Color3" and type(entry.Value) == "string" then
                decoded = hexToColor(entry.Value)
            elseif entry.Type == "EnumItem" and entry.EnumType and entry.Name then
                pcall(function()
                    decoded = (Enum :: any)[entry.EnumType][entry.Name]
                end)
            end

            if decoded ~= nil then
                self.Flags[flagName] = decoded
                for _, win in ipairs(self.Windows) do
                    if win._controlsByFlag and win._controlsByFlag[flagName] then
                        pcall(function()
                            win._controlsByFlag[flagName]:Set(decoded)
                        end)
                    end
                end
            end
        end
    end

    return true, string.format("Perfil '%s' carregado com sucesso.", key)
end

-- ============================================================================
-- 5. CONTAINER RAIZ, BLUR COMPARTILHADO E SISTEMA DE NOTIFICAÇÕES
-- ============================================================================
function Royalty:_ensureRoot(customParent: Instance?)
    if self._rootGui and self._rootGui.Parent then
        return self._rootGui
    end

    local parentInst = resolveParent(customParent)
    local gui = create("ScreenGui", {
        Name = "RoyaltyUI_Host",
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        IgnoreGuiInset = true,
        Parent = parentInst
    })
    self._scope:Add(gui)
    self._rootGui = gui

    local blur = create("BlurEffect", {
        Name = "RoyaltyDepthBlur",
        Size = 0,
        Enabled = false,
        Parent = Lighting
    })
    self._scope:Add(blur)
    self._blurEffect = blur

    local notifHolder = create("Frame", {
        Name = "NotificationStack",
        Size = UDim2.new(0, 300, 1, -32),
        Position = UDim2.new(1, -316, 0, 16),
        BackgroundTransparency = 1,
        Parent = gui
    }, {
        create("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            VerticalAlignment = Enum.VerticalAlignment.Bottom,
            HorizontalAlignment = Enum.HorizontalAlignment.Right,
            Padding = UDim.new(0, 8)
        })
    })
    self._notifHolder = notifHolder

    return gui
end

function Royalty:_syncBlur()
    if not self._blurEffect or not self._blurEffect.Parent then return end
    local shouldBlur = false
    for _, win in ipairs(self.Windows) do
        if not win._destroyed and win.Visible and win.UseBlur then
            shouldBlur = true
            break
        end
    end

    if shouldBlur then
        self._blurEffect.Enabled = true
        self:Animate(self._blurEffect, self.Tokens.Animation.Normal, { Size = 10 })
    else
        local tw = self:Animate(self._blurEffect, self.Tokens.Animation.Fast, { Size = 0 })
        if tw then
            tw.Completed:Once(function()
                if self._blurEffect and self._blurEffect.Size <= 0.5 then
                    self._blurEffect.Enabled = false
                end
            end)
        else
            self._blurEffect.Enabled = false
        end
    end
end

function Royalty:Notify(cfg: { Title: string?, Content: string?, Duration: number?, Type: string? }?)
    if not self.NotificationsEnabled then return nil end
    cfg = cfg or {}
    self:_ensureRoot()

    local titleText = tostring(cfg.Title or "Royalty")
    local contentText = tostring(cfg.Content or "")
    local duration = math.clamp(tonumber(cfg.Duration) or 4, 1, 30)
    local nType = string.lower(tostring(cfg.Type or "info"))

    local notifScope = self._scope:NewChild()
    local dismissed = false

    local typeToken = "Accent"
    local badgeSymbol = "i"
    if nType == "success" then
        typeToken = "Success"
        badgeSymbol = "✓"
    elseif nType == "warning" then
        typeToken = "Warning"
        badgeSymbol = "!"
    elseif nType == "error" then
        typeToken = "Error"
        badgeSymbol = "×"
    end

    local wrapper = create("Frame", {
        Name = "ToastWrapper",
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Parent = self._notifHolder
    })
    notifScope:Add(wrapper)

    local card = create("Frame", {
        Name = "Card",
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Position = UDim2.new(0, 24, 0, 0),
        BackgroundColor3 = self.Theme.Surface,
        BackgroundTransparency = 1,
        ClipsDescendants = true,
        Parent = wrapper
    }, {
        create("UICorner", { CornerRadius = self.Tokens.CornerRadius.Section })
    })
    self:BindThemeProperty(notifScope, card, "BackgroundColor3", "Surface")

    local stroke = create("UIStroke", {
        Color = self.Theme.Border,
        Thickness = 1,
        Transparency = 1,
        Parent = card
    })
    self:BindThemeProperty(notifScope, stroke, "Color", "Border")

    local contentPad = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Parent = card
    }, {
        create("UIPadding", {
            PaddingTop = UDim.new(0, 10),
            PaddingBottom = UDim.new(0, 12),
            PaddingLeft = UDim.new(0, 12),
            PaddingRight = UDim.new(0, 12)
        }),
        create("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 4)
        })
    })

    local topRow = create("Frame", {
        LayoutOrder = 1,
        Size = UDim2.new(1, 0, 0, 18),
        BackgroundTransparency = 1,
        Parent = contentPad
    })

    local badge = create("TextLabel", {
        Size = UDim2.new(0, 18, 0, 18),
        BackgroundColor3 = self.Theme[typeToken],
        Text = badgeSymbol,
        TextColor3 = Color3.fromRGB(255, 255, 255),
        Font = self.Tokens.Font.Bold,
        TextSize = 11,
        Parent = topRow
    }, {
        create("UICorner", { CornerRadius = self.Tokens.CornerRadius.Pill })
    })
    self:BindThemeProperty(notifScope, badge, "BackgroundColor3", typeToken)

    local titleLbl = create("TextLabel", {
        Size = UDim2.new(1, -44, 1, 0),
        Position = UDim2.new(0, 26, 0, 0),
        BackgroundTransparency = 1,
        Text = titleText,
        TextColor3 = self.Theme.Text,
        Font = self.Tokens.Font.Semibold,
        TextSize = self.Tokens.TextSize.Control,
        TextTruncate = Enum.TextTruncate.AtEnd,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = topRow
    })
    self:BindThemeProperty(notifScope, titleLbl, "TextColor3", "Text")

    local closeBtn = create("TextButton", {
        Size = UDim2.new(0, 18, 0, 18),
        Position = UDim2.new(1, -18, 0, 0),
        BackgroundTransparency = 1,
        Text = "×",
        TextColor3 = self.Theme.Muted,
        Font = self.Tokens.Font.Bold,
        TextSize = 14,
        Parent = topRow
    })
    self:BindThemeProperty(notifScope, closeBtn, "TextColor3", "Muted")

    if contentText ~= "" then
        local bodyLbl = create("TextLabel", {
            LayoutOrder = 2,
            Size = UDim2.new(1, -26, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            Position = UDim2.new(0, 26, 0, 0),
            BackgroundTransparency = 1,
            Text = contentText,
            TextColor3 = self.Theme.SubText,
            Font = self.Tokens.Font.Regular,
            TextSize = self.Tokens.TextSize.Description,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = contentPad
        })
        self:BindThemeProperty(notifScope, bodyLbl, "TextColor3", "SubText")
    end

    local progressTrack = create("Frame", {
        Size = UDim2.new(1, 0, 0, 2),
        Position = UDim2.new(0, 0, 1, -2),
        BackgroundColor3 = self.Theme.BorderSubtle,
        BorderSizePixel = 0,
        Parent = card
    })
    self:BindThemeProperty(notifScope, progressTrack, "BackgroundColor3", "BorderSubtle")

    local progressFill = create("Frame", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = self.Theme[typeToken],
        BorderSizePixel = 0,
        Parent = progressTrack
    })
    self:BindThemeProperty(notifScope, progressFill, "BackgroundColor3", typeToken)

    -- Animação de entrada
    self:Animate(card, self.Tokens.Animation.Normal, {
        Position = UDim2.new(0, 0, 0, 0),
        BackgroundTransparency = 0
    })
    self:Animate(stroke, self.Tokens.Animation.Normal, { Transparency = 0 })

    if not self.ReducedMotion then
        TweenService:Create(
            progressFill,
            TweenInfo.new(duration, Enum.EasingStyle.Linear),
            { Size = UDim2.new(0, 0, 1, 0) }
        ):Play()
    end

    local function dismiss()
        if dismissed then return end
        dismissed = true
        local tw = self:Animate(card, self.Tokens.Animation.Fast, {
            Position = UDim2.new(0, 24, 0, 0),
            BackgroundTransparency = 1
        })
        self:Animate(stroke, self.Tokens.Animation.Fast, { Transparency = 1 })
        if tw then
            tw.Completed:Once(function()
                notifScope:Destroy()
            end)
        else
            notifScope:Destroy()
        end
    end

    notifScope:Connect(closeBtn.Activated, dismiss)
    local timerThread = task.delay(duration, dismiss)
    notifScope:Add(timerThread)

    return {
        Dismiss = dismiss
    }
end

-- ============================================================================
-- 6. CRIAÇÃO DE JANELA, LOADING SCREEN E NAVEGAÇÃO
-- ============================================================================
function Royalty:CreateWindow(cfg: { [string]: any }?)
    cfg = cfg or {}
    self:_ensureRoot(cfg.Parent)

    if cfg.Theme then
        self:SetTheme(cfg.Theme)
    end
    if typeof(cfg.Accent) == "Color3" then
        self:SetAccentColor(cfg.Accent)
    end
    if cfg.ReducedMotion ~= nil then
        self:SetReducedMotion(cfg.ReducedMotion == true)
    end

    local winScope = self._scope:NewChild()
    local titleText = tostring(cfg.Title or "Royalty")
    local subTitleText = tostring(cfg.SubTitle or "v2.0")
    local rawSize: UDim2 = typeof(cfg.Size) == "UDim2" and cfg.Size or UDim2.fromOffset(620, 420)
    local toggleKey = cfg.ToggleKey or Enum.KeyCode.RightShift
    local useBlur = (cfg.Blur == true)
    local uiScaleValue = math.clamp(tonumber(cfg.Scale) or 1, 0.75, 1.35)

    local Window = {
        Title = titleText,
        SubTitle = subTitleText,
        Tabs = {},
        ActiveTab = nil,
        Visible = true,
        ToggleKey = toggleKey,
        UseBlur = useBlur,
        Scale = uiScaleValue,
        _scope = winScope,
        _destroyed = false,
        _transitionId = 0,
        _controlsByFlag = {},
        _isBindingKey = false
    }
    table.insert(self.Windows, Window)

    -- Cálculo seguro de tamanho e centralização considerando a câmera atual
    local function computeCenteredBounds(requestedSize: UDim2): (UDim2, UDim2)
        local cam = workspace.CurrentCamera
        local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
        local w = requestedSize.X.Scale * vp.X + requestedSize.X.Offset
        local h = requestedSize.Y.Scale * vp.Y + requestedSize.Y.Offset
        w = math.clamp(w, 340, math.max(360, vp.X - 24))
        h = math.clamp(h, 260, math.max(280, vp.Y - 36))
        local finalSize = UDim2.fromOffset(math.floor(w), math.floor(h))
        local finalPos = UDim2.fromOffset(math.floor((vp.X - w) * 0.5), math.floor((vp.Y - h) * 0.5))
        return finalSize, finalPos
    end

    local initialSize, initialPos = computeCenteredBounds(rawSize)

    local Main = create("CanvasGroup", {
        Name = "RoyaltyWindow_" .. titleText,
        Size = initialSize,
        Position = initialPos,
        BackgroundColor3 = self.Theme.Background,
        GroupTransparency = 1,
        ClipsDescendants = true,
        Parent = self._rootGui
    }, {
        create("UICorner", { CornerRadius = self.Tokens.CornerRadius.Window })
    })
    winScope:Add(Main)
    self:BindThemeProperty(winScope, Main, "BackgroundColor3", "Background")

    local WinScale = create("UIScale", {
        Scale = self.ReducedMotion and uiScaleValue or (uiScaleValue * 0.96),
        Parent = Main
    })

    local MainStroke = create("UIStroke", {
        Color = self.Theme.Border,
        Thickness = 1,
        Parent = Main
    })
    self:BindThemeProperty(winScope, MainStroke, "Color", "Border")

    -- Sidebar
    local Sidebar = create("Frame", {
        Name = "Sidebar",
        Size = UDim2.new(0, 170, 1, 0),
        BackgroundColor3 = self.Theme.Sidebar,
        BorderSizePixel = 0,
        Parent = Main
    })
    self:BindThemeProperty(winScope, Sidebar, "BackgroundColor3", "Sidebar")

    local SidebarDivider = create("Frame", {
        Size = UDim2.new(0, 1, 1, 0),
        Position = UDim2.new(1, -1, 0, 0),
        BackgroundColor3 = self.Theme.BorderSubtle,
        BorderSizePixel = 0,
        Parent = Sidebar
    })
    self:BindThemeProperty(winScope, SidebarDivider, "BackgroundColor3", "BorderSubtle")

    -- Brand Header
    local BrandHeader = create("Frame", {
        Name = "BrandHeader",
        Size = UDim2.new(1, 0, 0, 58),
        BackgroundTransparency = 1,
        Parent = Sidebar
    })

    local BrandIndicator = create("Frame", {
        Size = UDim2.new(0, 8, 0, 22),
        Position = UDim2.new(0, 14, 0, 18),
        BackgroundColor3 = self.Theme.Accent,
        BorderSizePixel = 0,
        Parent = BrandHeader
    }, {
        create("UICorner", { CornerRadius = self.Tokens.CornerRadius.Pill })
    })
    self:BindThemeProperty(winScope, BrandIndicator, "BackgroundColor3", "Accent")

    local WinTitleLbl = create("TextLabel", {
        Size = UDim2.new(1, -38, 0, 20),
        Position = UDim2.new(0, 30, 0, 14),
        BackgroundTransparency = 1,
        Text = titleText,
        TextColor3 = self.Theme.Text,
        Font = self.Tokens.Font.Bold,
        TextSize = self.Tokens.TextSize.WindowTitle,
        TextTruncate = Enum.TextTruncate.AtEnd,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = BrandHeader
    })
    self:BindThemeProperty(winScope, WinTitleLbl, "TextColor3", "Text")

    local WinSubLbl = create("TextLabel", {
        Size = UDim2.new(1, -38, 0, 16),
        Position = UDim2.new(0, 30, 0, 33),
        BackgroundTransparency = 1,
        Text = subTitleText,
        TextColor3 = self.Theme.Muted,
        Font = self.Tokens.Font.Medium,
        TextSize = self.Tokens.TextSize.Small,
        TextTruncate = Enum.TextTruncate.AtEnd,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = BrandHeader
    })
    self:BindThemeProperty(winScope, WinSubLbl, "TextColor3", "Muted")

    local TabList = create("ScrollingFrame", {
        Name = "TabList",
        Size = UDim2.new(1, -16, 1, -102),
        Position = UDim2.new(0, 8, 0, 62),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = self.Theme.Border,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Parent = Sidebar
    }, {
        create("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 4)
        })
    })
    self:BindThemeProperty(winScope, TabList, "ScrollBarImageColor3", "Border")

    local FooterFrame = create("Frame", {
        Size = UDim2.new(1, 0, 0, 36),
        Position = UDim2.new(0, 0, 1, -36),
        BackgroundTransparency = 1,
        Parent = Sidebar
    })

    local FooterDivider = create("Frame", {
        Size = UDim2.new(1, -24, 0, 1),
        Position = UDim2.new(0, 12, 0, 0),
        BackgroundColor3 = self.Theme.BorderSubtle,
        BorderSizePixel = 0,
        Parent = FooterFrame
    })
    self:BindThemeProperty(winScope, FooterDivider, "BackgroundColor3", "BorderSubtle")

    local FooterKeyLabel = create("TextLabel", {
        Size = UDim2.new(1, -24, 1, -2),
        Position = UDim2.new(0, 12, 0, 2),
        BackgroundTransparency = 1,
        Text = "Alternar UI: [" .. formatKeyName(toggleKey) .. "]",
        TextColor3 = self.Theme.Muted,
        Font = self.Tokens.Font.Medium,
        TextSize = self.Tokens.TextSize.Small,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = FooterFrame
    })
    self:BindThemeProperty(winScope, FooterKeyLabel, "TextColor3", "Muted")

    -- Área Principal de Conteúdo e Cabeçalho da Página
    local ContentArea = create("Frame", {
        Name = "ContentArea",
        Size = UDim2.new(1, -170, 1, 0),
        Position = UDim2.new(0, 170, 0, 0),
        BackgroundTransparency = 1,
        Parent = Main
    })

    local TopHeaderBar = create("Frame", {
        Name = "TopHeaderBar",
        Size = UDim2.new(1, 0, 0, 52),
        BackgroundTransparency = 1,
        Parent = ContentArea
    })

    local TopHeaderLine = create("Frame", {
        Size = UDim2.new(1, 0, 0, 1),
        Position = UDim2.new(0, 0, 1, -1),
        BackgroundColor3 = self.Theme.BorderSubtle,
        BorderSizePixel = 0,
        Parent = TopHeaderBar
    })
    self:BindThemeProperty(winScope, TopHeaderLine, "BackgroundColor3", "BorderSubtle")

    local ActivePageTitle = create("TextLabel", {
        Size = UDim2.new(0.5, -24, 1, 0),
        Position = UDim2.new(0, 18, 0, 0),
        BackgroundTransparency = 1,
        Text = "",
        TextColor3 = self.Theme.Text,
        Font = self.Tokens.Font.Bold,
        TextSize = self.Tokens.TextSize.PageTitle,
        TextTruncate = Enum.TextTruncate.AtEnd,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = TopHeaderBar
    })
    self:BindThemeProperty(winScope, ActivePageTitle, "TextColor3", "Text")

    -- Caixa de Busca Global na Página Ativa
    local SearchContainer = create("Frame", {
        Size = UDim2.new(0, 185, 0, 30),
        Position = UDim2.new(1, -200, 0.5, -15),
        BackgroundColor3 = self.Theme.Surface,
        Parent = TopHeaderBar
    }, {
        create("UICorner", { CornerRadius = self.Tokens.CornerRadius.Control })
    })
    self:BindThemeProperty(winScope, SearchContainer, "BackgroundColor3", "Surface")

    local SearchStroke = create("UIStroke", {
        Color = self.Theme.BorderSubtle,
        Thickness = 1,
        Parent = SearchContainer
    })
    self:BindThemeProperty(winScope, SearchStroke, "Color", "BorderSubtle")

    local SearchBox = create("TextBox", {
        Size = UDim2.new(1, -16, 1, 0),
        Position = UDim2.new(0, 8, 0, 0),
        BackgroundTransparency = 1,
        Text = "",
        PlaceholderText = "Buscar controle ou seção...",
        PlaceholderColor3 = self.Theme.Muted,
        TextColor3 = self.Theme.Text,
        Font = self.Tokens.Font.Regular,
        TextSize = self.Tokens.TextSize.Description,
        ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = SearchContainer
    })
    self:BindThemeProperty(winScope, SearchBox, "PlaceholderColor3", "Muted")
    self:BindThemeProperty(winScope, SearchBox, "TextColor3", "Text")

    local PagesHolder = create("Frame", {
        Name = "PagesHolder",
        Size = UDim2.new(1, 0, 1, -52),
        Position = UDim2.new(0, 0, 0, 52),
        BackgroundTransparency = 1,
        ClipsDescendants = true,
        Parent = ContentArea
    })

    local EmptySearchBanner = create("TextLabel", {
        Size = UDim2.new(1, -32, 0, 40),
        Position = UDim2.new(0, 16, 0, 24),
        BackgroundTransparency = 1,
        Visible = false,
        Text = "Nenhum controle encontrado para a busca atual.",
        TextColor3 = self.Theme.Muted,
        Font = self.Tokens.Font.Medium,
        TextSize = self.Tokens.TextSize.Control,
        Parent = PagesHolder
    })
    self:BindThemeProperty(winScope, EmptySearchBanner, "TextColor3", "Muted")

    -- ========================================================================
    -- ARRASTO DIRETO, SUAVE E COM LIMITES DE TELA (MOUSE + TOUCH)
    -- ========================================================================
    local dragging = false
    local dragInput = nil
    local dragStartPos = Vector2.zero
    local windowStartPos = initialPos

    local function beginDrag(input: InputObject)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            if UserInputService:GetFocusedTextBox() == SearchBox then
                return
            end
            dragging = true
            dragInput = input
            dragStartPos = Vector2.new(input.Position.X, input.Position.Y)
            windowStartPos = Main.Position
        end
    end

    winScope:Connect(BrandHeader.InputBegan, beginDrag)
    winScope:Connect(TopHeaderBar.InputBegan, beginDrag)

    winScope:Connect(UserInputService.InputChanged, function(input)
        if dragging and (input == dragInput or input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = Vector2.new(input.Position.X, input.Position.Y) - dragStartPos
            local cam = workspace.CurrentCamera
            local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
            local absSize = Main.AbsoluteSize

            local rawX = windowStartPos.X.Offset + delta.X
            local rawY = windowStartPos.Y.Offset + delta.Y

            -- Impede que a janela seja arrastada para fora da tela
            local minX = -math.floor(absSize.X * 0.65)
            local maxX = math.floor(vp.X - absSize.X * 0.35)
            local minY = 0
            local maxY = math.floor(vp.Y - 48)

            Main.Position = UDim2.fromOffset(
                math.clamp(rawX, minX, maxX),
                math.clamp(rawY, minY, maxY)
            )
        end
    end)

    winScope:Connect(UserInputService.InputEnded, function(input)
        if input == dragInput or input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
            dragInput = nil
        end
    end)

    -- Filtro de Busca em Tempo Real
    local function applySearchFilter()
        local activeTab = Window.ActiveTab
        if not activeTab then return end
        local query = string.lower(string.gsub(SearchBox.Text, "^%s*(.-)%s*$", "%1"))

        if query == "" then
            EmptySearchBanner.Visible = false
            for _, sec in ipairs(activeTab.Sections) do
                sec.Frame.Visible = true
                for _, item in ipairs(sec.Items) do
                    item.Instance.Visible = true
                end
            end
            activeTab:_updateColumns()
            return
        end

        local anyMatchInTab = false
        for _, sec in ipairs(activeTab.Sections) do
            local secMatches = string.find(string.lower(sec.Name), query, 1, true) ~= nil
            local anyItemMatches = false

            for _, item in ipairs(sec.Items) do
                if secMatches then
                    item.Instance.Visible = true
                    anyItemMatches = true
                else
                    local match = string.find(string.lower(item.SearchText), query, 1, true) ~= nil
                    item.Instance.Visible = match
                    if match then
                        anyItemMatches = true
                    end
                end
            end

            sec.Frame.Visible = secMatches or anyItemMatches
            if sec.Frame.Visible then
                anyMatchInTab = true
            end
        end

        EmptySearchBanner.Visible = not anyMatchInTab
        activeTab:_updateColumns()
    end

    winScope:Connect(SearchBox:GetPropertyChangedSignal("Text"), applySearchFilter)
    winScope:Connect(SearchBox.Focused, function()
        Royalty:Animate(SearchStroke, Royalty.Tokens.Animation.Fast, { Color = Royalty.Theme.Accent })
    end)
    winScope:Connect(SearchBox.FocusLost, function()
        Royalty:Animate(SearchStroke, Royalty.Tokens.Animation.Fast, { Color = Royalty.Theme.BorderSubtle })
    end)

    -- ========================================================================
    -- MÉTODOS DE JANELA (TOGGLE COM TRANSIÇÃO REAL, SCALE, DESTROY)
    -- ========================================================================
    function Window:SetScale(newScale: number)
        self.Scale = math.clamp(tonumber(newScale) or 1, 0.75, 1.35)
        Royalty.Flags["Royalty_UIScale"] = self.Scale
        if self.Visible then
            Royalty:Animate(WinScale, Royalty.Tokens.Animation.Fast, { Scale = self.Scale })
        end
    end

    function Window:SetToggleKey(newKey: Enum.KeyCode?)
        self.ToggleKey = newKey
        FooterKeyLabel.Text = "Alternar UI: [" .. formatKeyName(newKey) .. "]"
        Royalty.Flags["Royalty_ToggleKey"] = newKey
    end

    function Window:Toggle(forcedState: boolean?)
        if self._destroyed then return end
        local targetState = (forcedState ~= nil) and (forcedState == true) or (not self.Visible)
        if self.Visible == targetState and self._transitionId > 0 then
            return
        end

        self.Visible = targetState
        self._transitionId += 1
        local currentTransition = self._transitionId

        Royalty:_syncBlur()

        if targetState then
            Main.Visible = true
            if Royalty.ReducedMotion then
                Main.GroupTransparency = 0
                WinScale.Scale = self.Scale
            else
                WinScale.Scale = self.Scale * 0.96
                Royalty:Animate(Main, Royalty.Tokens.Animation.Normal, { GroupTransparency = 0 })
                Royalty:Animate(WinScale, Royalty.Tokens.Animation.Normal, { Scale = self.Scale })
            end
        else
            if Royalty.ReducedMotion then
                Main.GroupTransparency = 1
                Main.Visible = false
            else
                local fadeOut = Royalty:Animate(Main, Royalty.Tokens.Animation.Fast, { GroupTransparency = 1 })
                Royalty:Animate(WinScale, Royalty.Tokens.Animation.Fast, { Scale = self.Scale * 0.96 })
                if fadeOut then
                    fadeOut.Completed:Once(function()
                        if self._transitionId == currentTransition and not self.Visible and Main and Main.Parent then
                            Main.Visible = false
                        end
                    end)
                else
                    Main.Visible = false
                end
            end
        end
    end

    function Window:Destroy()
        if self._destroyed then return end
        self._destroyed = true
        self.Visible = false

        local idx = table.find(Royalty.Windows, self)
        if idx then
            table.remove(Royalty.Windows, idx)
        end

        Royalty:_syncBlur()
        self._scope:Destroy()
    end

    winScope:Connect(UserInputService.InputBegan, function(input, gameProcessed)
        if gameProcessed or UserInputService:GetFocusedTextBox() ~= nil then
            return
        end
        if Window._isBindingKey then
            return
        end
        if Window.ToggleKey and input.KeyCode == Window.ToggleKey then
            Window:Toggle()
        end
    end)

    -- ========================================================================
    -- TELA DE CARREGAMENTO OPCIONAL (SOMENTE QUANDO HÁ TAREFAS REAIS)
    -- ========================================================================
    local initTasks = cfg.InitTasks
    local showLoading = (cfg.LoadingScreen ~= false) and (type(initTasks) == "table" and #initTasks > 0 or type(initTasks) == "function")

    if showLoading then
        local LoadingOverlay = create("Frame", {
            Name = "LoadingOverlay",
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundColor3 = self.Theme.Background,
            ZIndex = 50,
            Active = true,
            Parent = Main
        })
        self:BindThemeProperty(winScope, LoadingOverlay, "BackgroundColor3", "Background")

        local LoadTitle = create("TextLabel", {
            Size = UDim2.new(1, -48, 0, 24),
            Position = UDim2.new(0, 24, 0.5, -52),
            BackgroundTransparency = 1,
            ZIndex = 51,
            Text = titleText,
            TextColor3 = self.Theme.Text,
            Font = self.Tokens.Font.Bold,
            TextSize = 18,
            Parent = LoadingOverlay
        })
        self:BindThemeProperty(winScope, LoadTitle, "TextColor3", "Text")

        local LoadStatus = create("TextLabel", {
            Size = UDim2.new(1, -48, 0, 18),
            Position = UDim2.new(0, 24, 0.5, -24),
            BackgroundTransparency = 1,
            ZIndex = 51,
            Text = "Inicializando recursos...",
            TextColor3 = self.Theme.SubText,
            Font = self.Tokens.Font.Regular,
            TextSize = self.Tokens.TextSize.Description,
            Parent = LoadingOverlay
        })
        self:BindThemeProperty(winScope, LoadStatus, "TextColor3", "SubText")

        local BarTrack = create("Frame", {
            Size = UDim2.new(0, 260, 0, 6),
            Position = UDim2.new(0.5, -130, 0.5, 6),
            BackgroundColor3 = self.Theme.SurfaceElevated,
            BorderSizePixel = 0,
            ZIndex = 51,
            ClipsDescendants = true,
            Parent = LoadingOverlay
        }, {
            create("UICorner", { CornerRadius = self.Tokens.CornerRadius.Pill })
        })

        local BarFill = create("Frame", {
            Size = UDim2.new(0, 0, 1, 0),
            BackgroundColor3 = self.Theme.Accent,
            BorderSizePixel = 0,
            ZIndex = 52,
            Parent = BarTrack
        }, {
            create("UICorner", { CornerRadius = self.Tokens.CornerRadius.Pill })
        })
        self:BindThemeProperty(winScope, BarFill, "BackgroundColor3", "Accent")

        local SkipBtn = create("TextButton", {
            Size = UDim2.new(0, 120, 0, 28),
            Position = UDim2.new(0.5, -60, 0.5, 28),
            BackgroundColor3 = self.Theme.SurfaceElevated,
            ZIndex = 51,
            Visible = (cfg.AllowSkipLoading == true),
            Text = "Ignorar",
            TextColor3 = self.Theme.SubText,
            Font = self.Tokens.Font.Medium,
            TextSize = self.Tokens.TextSize.Small,
            Parent = LoadingOverlay
        }, {
            create("UICorner", { CornerRadius = self.Tokens.CornerRadius.Control }),
            create("UIStroke", { Color = self.Theme.Border, Thickness = 1 })
        })

        local overlayClosed = false
        local function closeLoadingOverlay()
            if overlayClosed or not LoadingOverlay or not LoadingOverlay.Parent then return end
            overlayClosed = true
            local tw = self:Animate(LoadingOverlay, self.Tokens.Animation.Normal, { BackgroundTransparency = 1 })
            for _, desc in ipairs(LoadingOverlay:GetDescendants()) do
                if desc:IsA("TextLabel") or desc:IsA("TextButton") then
                    self:Animate(desc, self.Tokens.Animation.Fast, { TextTransparency = 1, BackgroundTransparency = 1 })
                elseif desc:IsA("Frame") then
                    self:Animate(desc, self.Tokens.Animation.Fast, { BackgroundTransparency = 1 })
                end
            end
            if tw then
                tw.Completed:Once(function()
                    if LoadingOverlay and LoadingOverlay.Parent then
                        LoadingOverlay:Destroy()
                    end
                end)
            else
                LoadingOverlay:Destroy()
            end
        end

        winScope:Connect(SkipBtn.Activated, closeLoadingOverlay)

        local loadThread = task.spawn(function()
            if type(initTasks) == "table" then
                local total = #initTasks
                for idx, taskEntry in ipairs(initTasks) do
                    if overlayClosed or Window._destroyed then return end
                    local taskName = type(taskEntry) == "table" and tostring(taskEntry.Name or ("Etapa " .. idx)) or ("Etapa " .. idx)
                    local taskFn = type(taskEntry) == "table" and taskEntry.Task or taskEntry

                    LoadStatus.Text = string.format("%s (%d/%d)", taskName, idx, total)
                    local ok, err = safeCall("InitTask:" .. taskName, taskFn)
                    if not ok then
                        LoadStatus.Text = "Erro em '" .. taskName .. "'. Clique para continuar."
                        LoadStatus.TextColor3 = self.Theme.Error
                        SkipBtn.Text = "Continuar"
                        SkipBtn.Visible = true
                        return
                    end
                    local ratio = math.clamp(idx / total, 0, 1)
                    self:Animate(BarFill, self.Tokens.Animation.Fast, { Size = UDim2.new(ratio, 0, 1, 0) })
                end
                closeLoadingOverlay()
            elseif type(initTasks) == "function" then
                -- Indicador indeterminado real (sem fingir porcentagem)
                BarFill.Size = UDim2.new(0.35, 0, 1, 0)
                local pulseRunning = true
                task.spawn(function()
                    while pulseRunning and not overlayClosed and not Window._destroyed do
                        local t1 = self:Animate(BarFill, 0.55, { Position = UDim2.new(0.65, 0, 0, 0) })
                        if t1 then t1.Completed:Wait() else task.wait(0.2) end
                        local t2 = self:Animate(BarFill, 0.55, { Position = UDim2.new(0, 0, 0, 0) })
                        if t2 then t2.Completed:Wait() else task.wait(0.2) end
                    end
                end)

                local ok = safeCall("InitTasks", initTasks, function(statusText: string)
                    if LoadStatus and LoadStatus.Parent then
                        LoadStatus.Text = tostring(statusText)
                    end
                end)
                pulseRunning = false
                if not ok then
                    LoadStatus.Text = "Falha na inicialização. Clique para abrir a interface."
                    LoadStatus.TextColor3 = self.Theme.Error
                    SkipBtn.Text = "Abrir UI"
                    SkipBtn.Visible = true
                    return
                end
                closeLoadingOverlay()
            end
        end)
        winScope:Add(loadThread)
    end

    -- Entrada inicial da janela
    self._transitionId = 1
    Main.Visible = true
    self:_syncBlur()
    if self.ReducedMotion then
        Main.GroupTransparency = 0
        WinScale.Scale = uiScaleValue
    else
        self:Animate(Main, self.Tokens.Animation.Normal, { GroupTransparency = 0 })
        self:Animate(WinScale, self.Tokens.Animation.Normal, { Scale = uiScaleValue })
    end

    -- ========================================================================
    -- 7. CRIAÇÃO DE ABAS, SEÇÕES E CONTROLES
    -- ========================================================================
    function Window:AddTab(tabName: string)
        tabName = tostring(tabName or "Tab")
        local tabScope = winScope:NewChild()

        local Tab = {
            Name = tabName,
            Active = false,
            Sections = {},
            _scope = tabScope
        }

        local TabBtn = create("TextButton", {
            Name = tabName .. "_TabBtn",
            Size = UDim2.new(1, 0, 0, 34),
            BackgroundColor3 = Royalty.Theme.Surface,
            BackgroundTransparency = 1,
            AutoButtonColor = false,
            Text = "",
            Parent = TabList
        }, {
            create("UICorner", { CornerRadius = Royalty.Tokens.CornerRadius.Control })
        })
        Royalty:BindThemeProperty(tabScope, TabBtn, "BackgroundColor3", "Surface")

        local ActiveBar = create("Frame", {
            Size = UDim2.new(0, 3, 0, 0),
            Position = UDim2.new(0, 0, 0.5, 0),
            AnchorPoint = Vector2.new(0, 0.5),
            BackgroundColor3 = Royalty.Theme.Accent,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Parent = TabBtn
        }, {
            create("UICorner", { CornerRadius = Royalty.Tokens.CornerRadius.Pill })
        })
        Royalty:BindThemeProperty(tabScope, ActiveBar, "BackgroundColor3", "Accent")

        local TabTitle = create("TextLabel", {
            Size = UDim2.new(1, -24, 1, 0),
            Position = UDim2.new(0, 14, 0, 0),
            BackgroundTransparency = 1,
            Text = tabName,
            TextColor3 = Royalty.Theme.SubText,
            Font = Royalty.Tokens.Font.Medium,
            TextSize = Royalty.Tokens.TextSize.Control,
            TextTruncate = Enum.TextTruncate.AtEnd,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = TabBtn
        })

        local PageScroll = create("ScrollingFrame", {
            Name = tabName .. "_Page",
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Visible = false,
            ScrollBarThickness = 3,
            ScrollBarImageColor3 = Royalty.Theme.Border,
            CanvasSize = UDim2.new(0, 0, 0, 0),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            Parent = PagesHolder
        }, {
            create("UIPadding", {
                PaddingTop = UDim.new(0, 12),
                PaddingBottom = UDim.new(0, 16),
                PaddingLeft = UDim.new(0, 14),
                PaddingRight = UDim.new(0, 14)
            })
        })
        Royalty:BindThemeProperty(tabScope, PageScroll, "ScrollBarImageColor3", "Border")

        local ColumnsContainer = create("Frame", {
            Name = "ColumnsContainer",
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            Parent = PageScroll
        })

        local LeftColumn = create("Frame", {
            Name = "LeftColumn",
            Size = UDim2.new(0.5, -6, 0, 0),
            Position = UDim2.new(0, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            Parent = ColumnsContainer
        }, {
            create("UIListLayout", {
                SortOrder = Enum.SortOrder.LayoutOrder,
                Padding = UDim.new(0, 10)
            })
        })

        local RightColumn = create("Frame", {
            Name = "RightColumn",
            Size = UDim2.new(0.5, -6, 0, 0),
            Position = UDim2.new(0.5, 6, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            Parent = ColumnsContainer
        }, {
            create("UIListLayout", {
                SortOrder = Enum.SortOrder.LayoutOrder,
                Padding = UDim.new(0, 10)
            })
        })

        -- Adaptação responsiva de colunas (1 coluna se tela estreita ou se só uma coluna tiver seções visíveis)
        function Tab:_updateColumns()
            local hasLeft, hasRight = false, false
            for _, sec in ipairs(self.Sections) do
                if sec.Frame.Visible then
                    if sec.Side == "right" then
                        hasRight = true
                    else
                        hasLeft = true
                    end
                end
            end

            local pageWidth = PageScroll.AbsoluteSize.X
            local stackSingleColumn = (pageWidth > 0 and pageWidth < 360) or (hasLeft and not hasRight) or (hasRight and not hasLeft)

            if stackSingleColumn then
                if hasLeft and not hasRight then
                    LeftColumn.Visible = true
                    RightColumn.Visible = false
                    LeftColumn.Size = UDim2.new(1, 0, 0, 0)
                    LeftColumn.Position = UDim2.new(0, 0, 0, 0)
                elseif hasRight and not hasLeft then
                    LeftColumn.Visible = false
                    RightColumn.Visible = true
                    RightColumn.Size = UDim2.new(1, 0, 0, 0)
                    RightColumn.Position = UDim2.new(0, 0, 0, 0)
                else
                    LeftColumn.Visible = true
                    RightColumn.Visible = true
                    LeftColumn.Size = UDim2.new(1, 0, 0, 0)
                    LeftColumn.Position = UDim2.new(0, 0, 0, 0)
                    RightColumn.Size = UDim2.new(1, 0, 0, 0)
                    RightColumn.Position = UDim2.new(0, 0, 0, LeftColumn.AbsoluteSize.Y + 10)
                end
            else
                LeftColumn.Visible = true
                RightColumn.Visible = true
                LeftColumn.Size = UDim2.new(0.5, -6, 0, 0)
                LeftColumn.Position = UDim2.new(0, 0, 0, 0)
                RightColumn.Size = UDim2.new(0.5, -6, 0, 0)
                RightColumn.Position = UDim2.new(0.5, 6, 0, 0)
            end
        end

        tabScope:Connect(PageScroll:GetPropertyChangedSignal("AbsoluteSize"), function()
            Tab:_updateColumns()
        end)

        Royalty:OnThemeChanged(tabScope, function(theme)
            TabTitle.TextColor3 = Tab.Active and theme.Text or theme.SubText
        end)

        function Tab:Activate()
            if Window.ActiveTab == self then return end

            for _, other in ipairs(Window.Tabs) do
                other.Active = false
                other.Page.Visible = false
                other.Title.Font = Royalty.Tokens.Font.Medium
                Royalty:Animate(other.Btn, Royalty.Tokens.Animation.Fast, { BackgroundTransparency = 1 })
                Royalty:Animate(other.Title, Royalty.Tokens.Animation.Fast, { TextColor3 = Royalty.Theme.SubText })
                Royalty:Animate(other.ActiveBar, Royalty.Tokens.Animation.Fast, {
                    Size = UDim2.new(0, 3, 0, 0),
                    BackgroundTransparency = 1
                })
            end

            self.Active = true
            Window.ActiveTab = self
            ActivePageTitle.Text = self.Name

            TabTitle.Font = Royalty.Tokens.Font.Semibold
            Royalty:Animate(TabBtn, Royalty.Tokens.Animation.Fast, { BackgroundTransparency = 0 })
            Royalty:Animate(TabTitle, Royalty.Tokens.Animation.Fast, { TextColor3 = Royalty.Theme.Text })
            Royalty:Animate(ActiveBar, Royalty.Tokens.Animation.Normal, {
                Size = UDim2.new(0, 3, 0, 18),
                BackgroundTransparency = 0
            })

            PageScroll.Visible = true
            self:_updateColumns()
            applySearchFilter()

            if not Royalty.ReducedMotion then
                ColumnsContainer.Position = UDim2.new(0, 0, 0, 6)
                Royalty:Animate(ColumnsContainer, Royalty.Tokens.Animation.Fast, {
                    Position = UDim2.new(0, 0, 0, 0)
                })
            else
                ColumnsContainer.Position = UDim2.new(0, 0, 0, 0)
            end
        end

        tabScope:Connect(TabBtn.MouseEnter, function()
            if not Tab.Active then
                Royalty:Animate(TabBtn, Royalty.Tokens.Animation.Fast, { BackgroundTransparency = 0.5 })
            end
        end)
        tabScope:Connect(TabBtn.MouseLeave, function()
            if not Tab.Active then
                Royalty:Animate(TabBtn, Royalty.Tokens.Animation.Fast, { BackgroundTransparency = 1 })
            end
        end)
        tabScope:Connect(TabBtn.Activated, function()
            Tab:Activate()
        end)

        Tab.Btn = TabBtn
        Tab.Title = TabTitle
        Tab.ActiveBar = ActiveBar
        Tab.Page = PageScroll
        table.insert(Window.Tabs, Tab)

        if #Window.Tabs == 1 then
            Tab:Activate()
        end

        -- ====================================================================
        -- SEÇÕES E CONTROLES
        -- ====================================================================
        function Tab:AddSection(sectionName: string, side: string?)
            sectionName = tostring(sectionName or "Section")
            local normalizedSide = (side and string.lower(tostring(side)) == "right") and "right" or "left"
            local parentColumn = (normalizedSide == "right") and RightColumn or LeftColumn
            local secScope = tabScope:NewChild()

            local Section = {
                Name = sectionName,
                Side = normalizedSide,
                Items = {},
                _scope = secScope
            }

            local SecFrame = create("Frame", {
                Name = sectionName .. "_Section",
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundColor3 = Royalty.Theme.Surface,
                Parent = parentColumn
            }, {
                create("UICorner", { CornerRadius = Royalty.Tokens.CornerRadius.Section }),
                create("UIPadding", {
                    PaddingTop = UDim.new(0, 10),
                    PaddingBottom = UDim.new(0, 12),
                    PaddingLeft = UDim.new(0, 12),
                    PaddingRight = UDim.new(0, 12)
                }),
                create("UIListLayout", {
                    SortOrder = Enum.SortOrder.LayoutOrder,
                    Padding = UDim.new(0, 8)
                })
            })
            Royalty:BindThemeProperty(secScope, SecFrame, "BackgroundColor3", "Surface")

            local SecStroke = create("UIStroke", {
                Color = Royalty.Theme.BorderSubtle,
                Thickness = 1,
                Parent = SecFrame
            })
            Royalty:BindThemeProperty(secScope, SecStroke, "Color", "BorderSubtle")

            local HeaderHolder = create("Frame", {
                LayoutOrder = 0,
                Size = UDim2.new(1, 0, 0, 20),
                BackgroundTransparency = 1,
                Parent = SecFrame
            })

            local SecTitle = create("TextLabel", {
                Size = UDim2.new(1, 0, 0, 16),
                BackgroundTransparency = 1,
                Text = sectionName,
                TextColor3 = Royalty.Theme.Text,
                Font = Royalty.Tokens.Font.Bold,
                TextSize = Royalty.Tokens.TextSize.SectionTitle,
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = HeaderHolder
            })
            Royalty:BindThemeProperty(secScope, SecTitle, "TextColor3", "Text")

            local HeaderLine = create("Frame", {
                Size = UDim2.new(1, 0, 0, 1),
                Position = UDim2.new(0, 0, 1, -1),
                BackgroundColor3 = Royalty.Theme.BorderSubtle,
                BorderSizePixel = 0,
                Parent = HeaderHolder
            })
            Royalty:BindThemeProperty(secScope, HeaderLine, "BackgroundColor3", "BorderSubtle")

            Section.Frame = SecFrame
            table.insert(Tab.Sections, Section)
            Tab:_updateColumns()

            local itemOrder = 0
            local function registerSectionItem(inst: Instance, searchLabel: string)
                itemOrder += 1
                (inst :: any).LayoutOrder = itemOrder
                table.insert(Section.Items, {
                    Instance = inst,
                    SearchText = searchLabel
                })
            end

            -- ----------------------------------------------------------------
            -- 1. LABEL
            -- ----------------------------------------------------------------
            function Section:AddLabel(textOrCfg: string | { Text: string?, Description: string? })
                local ctrlScope = secScope:NewChild()
                local mainText = type(textOrCfg) == "table" and tostring(textOrCfg.Text or "") or tostring(textOrCfg or "")
                local descText = type(textOrCfg) == "table" and textOrCfg.Description and tostring(textOrCfg.Description) or nil

                local Holder = create("Frame", {
                    Size = UDim2.new(1, 0, 0, 0),
                    AutomaticSize = Enum.AutomaticSize.Y,
                    BackgroundTransparency = 1,
                    Parent = SecFrame
                }, {
                    create("UIListLayout", {
                        SortOrder = Enum.SortOrder.LayoutOrder,
                        Padding = UDim.new(0, 2)
                    })
                })
                registerSectionItem(Holder, mainText .. " " .. (descText or ""))

                local Lbl = create("TextLabel", {
                    LayoutOrder = 1,
                    Size = UDim2.new(1, 0, 0, 0),
                    AutomaticSize = Enum.AutomaticSize.Y,
                    BackgroundTransparency = 1,
                    Text = mainText,
                    TextColor3 = Royalty.Theme.SubText,
                    Font = Royalty.Tokens.Font.Regular,
                    TextSize = Royalty.Tokens.TextSize.Description,
                    TextWrapped = true,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = Holder
                })
                Royalty:BindThemeProperty(ctrlScope, Lbl, "TextColor3", "SubText")

                local DescLbl = nil
                if descText and descText ~= "" then
                    DescLbl = create("TextLabel", {
                        LayoutOrder = 2,
                        Size = UDim2.new(1, 0, 0, 0),
                        AutomaticSize = Enum.AutomaticSize.Y,
                        BackgroundTransparency = 1,
                        Text = descText,
                        TextColor3 = Royalty.Theme.Muted,
                        Font = Royalty.Tokens.Font.Regular,
                        TextSize = Royalty.Tokens.TextSize.Small,
                        TextWrapped = true,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        Parent = Holder
                    })
                    Royalty:BindThemeProperty(ctrlScope, DescLbl, "TextColor3", "Muted")
                end

                local LabelObj = {}
                function LabelObj:Set(newText: string)
                    mainText = tostring(newText or "")
                    Lbl.Text = mainText
                end
                function LabelObj:Get(): string
                    return mainText
                end
                return LabelObj
            end

            -- ----------------------------------------------------------------
            -- 2. DIVIDER
            -- ----------------------------------------------------------------
            function Section:AddDivider()
                local ctrlScope = secScope:NewChild()
                local Div = create("Frame", {
                    Size = UDim2.new(1, 0, 0, 1),
                    BackgroundColor3 = Royalty.Theme.BorderSubtle,
                    BorderSizePixel = 0,
                    Parent = SecFrame
                })
                Royalty:BindThemeProperty(ctrlScope, Div, "BackgroundColor3", "BorderSubtle")
                registerSectionItem(Div, "")
                return Div
            end

            -- ----------------------------------------------------------------
            -- 3. BUTTON
            -- ----------------------------------------------------------------
            function Section:AddButton(bCfg: { Name: string?, Description: string?, Disabled: boolean?, Callback: (() -> ())? }?)
                bCfg = bCfg or {}
                local ctrlScope = secScope:NewChild()
                local bName = tostring(bCfg.Name or "Button")
                local bDesc = bCfg.Description and tostring(bCfg.Description) or nil
                local disabled = (bCfg.Disabled == true)
                local loading = false
                local callback = bCfg.Callback

                local BtnFrame = create("TextButton", {
                    Size = UDim2.new(1, 0, 0, 0),
                    AutomaticSize = Enum.AutomaticSize.Y,
                    BackgroundColor3 = Royalty.Theme.SurfaceElevated,
                    AutoButtonColor = false,
                    Text = "",
                    Parent = SecFrame
                }, {
                    create("UICorner", { CornerRadius = Royalty.Tokens.CornerRadius.Control }),
                    create("UIPadding", {
                        PaddingTop = UDim.new(0, 8),
                        PaddingBottom = UDim.new(0, 8),
                        PaddingLeft = UDim.new(0, 10),
                        PaddingRight = UDim.new(0, 10)
                    })
                })
                registerSectionItem(BtnFrame, bName .. " " .. (bDesc or ""))

                local BtnStroke = create("UIStroke", {
                    Color = Royalty.Theme.Border,
                    Thickness = 1,
                    Parent = BtnFrame
                })
                Royalty:BindThemeProperty(ctrlScope, BtnStroke, "Color", "Border")

                local TextStack = create("Frame", {
                    Size = UDim2.new(1, -24, 0, 0),
                    AutomaticSize = Enum.AutomaticSize.Y,
                    BackgroundTransparency = 1,
                    Parent = BtnFrame
                }, {
                    create("UIListLayout", {
                        SortOrder = Enum.SortOrder.LayoutOrder,
                        Padding = UDim.new(0, 2)
                    })
                })

                local TitleLbl = create("TextLabel", {
                    LayoutOrder = 1,
                    Size = UDim2.new(1, 0, 0, 16),
                    BackgroundTransparency = 1,
                    Text = bName,
                    TextColor3 = disabled and Royalty.Theme.Muted or Royalty.Theme.Text,
                    Font = Royalty.Tokens.Font.Medium,
                    TextSize = Royalty.Tokens.TextSize.Control,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = TextStack
                })

                if bDesc and bDesc ~= "" then
                    local DescLbl = create("TextLabel", {
                        LayoutOrder = 2,
                        Size = UDim2.new(1, 0, 0, 0),
                        AutomaticSize = Enum.AutomaticSize.Y,
                        BackgroundTransparency = 1,
                        Text = bDesc,
                        TextColor3 = Royalty.Theme.Muted,
                        Font = Royalty.Tokens.Font.Regular,
                        TextSize = Royalty.Tokens.TextSize.Small,
                        TextWrapped = true,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        Parent = TextStack
                    })
                    Royalty:BindThemeProperty(ctrlScope, DescLbl, "TextColor3", "Muted")
                end

                local ActionBadge = create("TextLabel", {
                    Size = UDim2.new(0, 20, 0, 16),
                    Position = UDim2.new(1, -20, 0.5, -8),
                    BackgroundTransparency = 1,
                    Text = "→",
                    TextColor3 = Royalty.Theme.SubText,
                    Font = Royalty.Tokens.Font.Bold,
                    TextSize = 13,
                    TextXAlignment = Enum.TextXAlignment.Right,
                    Parent = BtnFrame
                })

                local hovered = false
                local function refreshVisual()
                    local targetBg = (hovered and not disabled and not loading) and Royalty.Theme.SurfaceHover or Royalty.Theme.SurfaceElevated
                    local targetText = (disabled or loading) and Royalty.Theme.Muted or Royalty.Theme.Text
                    local targetBadge = loading and Royalty.Theme.Accent or (hovered and not disabled and Royalty.Theme.Text or Royalty.Theme.SubText)
                    ActionBadge.Text = loading and "..." or "→"
                    Royalty:Animate(BtnFrame, Royalty.Tokens.Animation.Fast, { BackgroundColor3 = targetBg })
                    Royalty:Animate(TitleLbl, Royalty.Tokens.Animation.Fast, { TextColor3 = targetText })
                    Royalty:Animate(ActionBadge, Royalty.Tokens.Animation.Fast, { TextColor3 = targetBadge })
                end

                Royalty:OnThemeChanged(ctrlScope, function()
                    refreshVisual()
                end)

                ctrlScope:Connect(BtnFrame.MouseEnter, function()
                    hovered = true
                    refreshVisual()
                end)
                ctrlScope:Connect(BtnFrame.MouseLeave, function()
                    hovered = false
                    refreshVisual()
                end)

                ctrlScope:Connect(BtnFrame.Activated, function()
                    if disabled or loading then return end
                    Royalty:Animate(BtnStroke, 0.08, { Color = Royalty.Theme.Accent })
                    task.delay(0.14, function()
                        if BtnStroke and BtnStroke.Parent then
                            Royalty:Animate(BtnStroke, Royalty.Tokens.Animation.Fast, { Color = Royalty.Theme.Border })
                        end
                    end)
                    task.spawn(function()
                        safeCall("Button:" .. bName, callback)
                    end)
                end)

                local ButtonObj = {}
                function ButtonObj:SetText(newTitle: string)
                    bName = tostring(newTitle or "")
                    TitleLbl.Text = bName
                end
                function ButtonObj:SetDisabled(state: boolean)
                    disabled = (state == true)
                    refreshVisual()
                end
                function ButtonObj:SetLoading(state: boolean)
                    loading = (state == true)
                    refreshVisual()
                end
                return ButtonObj
            end

            -- ----------------------------------------------------------------
            -- 4. TOGGLE
            -- ----------------------------------------------------------------
            function Section:AddToggle(tCfg: { Name: string?, Description: string?, Default: boolean?, Disabled: boolean?, Flag: string?, CallOnInit: boolean?, Callback: ((state: boolean) -> ())? }?)
                tCfg = tCfg or {}
                local ctrlScope = secScope:NewChild()
                local tName = tostring(tCfg.Name or "Toggle")
                local tDesc = tCfg.Description and tostring(tCfg.Description) or nil
                local state = (tCfg.Default == true)
                local disabled = (tCfg.Disabled == true)
                local flag = tostring(tCfg.Flag or tName)
                local callOnInit = (tCfg.CallOnInit ~= false)
                local callback = tCfg.Callback

                Royalty.Flags[flag] = state
                local ToggleObj = { Value = state, Disabled = disabled }
                Window._controlsByFlag[flag] = ToggleObj

                local RowBtn = create("TextButton", {
                    Size = UDim2.new(1, 0, 0, 0),
                    AutomaticSize = Enum.AutomaticSize.Y,
                    BackgroundTransparency = 1,
                    AutoButtonColor = false,
                    Text = "",
                    Parent = SecFrame
                }, {
                    create("UIPadding", {
                        PaddingTop = UDim.new(0, 2),
                        PaddingBottom = UDim.new(0, 2)
                    })
                })
                registerSectionItem(RowBtn, tName .. " " .. (tDesc or ""))

                local TextStack = create("Frame", {
                    Size = UDim2.new(1, -56, 0, 0),
                    AutomaticSize = Enum.AutomaticSize.Y,
                    BackgroundTransparency = 1,
                    Parent = RowBtn
                }, {
                    create("UIListLayout", {
                        SortOrder = Enum.SortOrder.LayoutOrder,
                        Padding = UDim.new(0, 2)
                    })
                })

                local TitleLbl = create("TextLabel", {
                    LayoutOrder = 1,
                    Size = UDim2.new(1, 0, 0, 18),
                    BackgroundTransparency = 1,
                    Text = tName,
                    TextColor3 = Royalty.Theme.Text,
                    Font = Royalty.Tokens.Font.Medium,
                    TextSize = Royalty.Tokens.TextSize.Control,
                    TextWrapped = true,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = TextStack
                })

                if tDesc and tDesc ~= "" then
                    local DescLbl = create("TextLabel", {
                        LayoutOrder = 2,
                        Size = UDim2.new(1, 0, 0, 0),
                        AutomaticSize = Enum.AutomaticSize.Y,
                        BackgroundTransparency = 1,
                        Text = tDesc,
                        TextColor3 = Royalty.Theme.Muted,
                        Font = Royalty.Tokens.Font.Regular,
                        TextSize = Royalty.Tokens.TextSize.Small,
                        TextWrapped = true,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        Parent = TextStack
                    })
                    Royalty:BindThemeProperty(ctrlScope, DescLbl, "TextColor3", "Muted")
                end

                local Track = create("Frame", {
                    Size = UDim2.new(0, 44, 0, 22),
                    Position = UDim2.new(1, -44, 0, 0),
                    BackgroundColor3 = state and Royalty.Theme.Accent or Royalty.Theme.SurfaceElevated,
                    BorderSizePixel = 0,
                    Parent = RowBtn
                }, {
                    create("UICorner", { CornerRadius = Royalty.Tokens.CornerRadius.Pill })
                })

                local TrackStroke = create("UIStroke", {
                    Color = state and Royalty.Theme.Accent or Royalty.Theme.Border,
                    Thickness = 1,
                    Parent = Track
                })

                -- Sinal visual textual ("ON" / "OFF") para não depender apenas da cor
                local StateLabel = create("TextLabel", {
                    Size = UDim2.new(0, 20, 1, 0),
                    Position = state and UDim2.new(0, 5, 0, 0) or UDim2.new(1, -24, 0, 0),
                    BackgroundTransparency = 1,
                    Text = state and "ON" or "OFF",
                    TextColor3 = state and Color3.fromRGB(255, 255, 255) or Royalty.Theme.Muted,
                    Font = Royalty.Tokens.Font.Bold,
                    TextSize = 8,
                    Parent = Track
                })

                local Knob = create("Frame", {
                    Size = UDim2.new(0, 16, 0, 16),
                    Position = state and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8),
                    BackgroundColor3 = Color3.fromRGB(255, 255, 255),
                    BorderSizePixel = 0,
                    Parent = Track
                }, {
                    create("UICorner", { CornerRadius = Royalty.Tokens.CornerRadius.Pill })
                })

                local function syncVisual()
                    local isOn = ToggleObj.Value
                    local isDis = ToggleObj.Disabled
                    StateLabel.Text = isOn and "ON" or "OFF"
                    StateLabel.Position = isOn and UDim2.new(0, 5, 0, 0) or UDim2.new(1, -24, 0, 0)
                    StateLabel.TextColor3 = isOn and Color3.fromRGB(255, 255, 255) or Royalty.Theme.Muted

                    Royalty:Animate(TitleLbl, Royalty.Tokens.Animation.Fast, {
                        TextColor3 = isDis and Royalty.Theme.Muted or (isOn and Royalty.Theme.Text or Royalty.Theme.SubText)
                    })
                    Royalty:Animate(Track, Royalty.Tokens.Animation.Fast, {
                        BackgroundColor3 = isOn and Royalty.Theme.Accent or Royalty.Theme.SurfaceElevated
                    })
                    Royalty:Animate(TrackStroke, Royalty.Tokens.Animation.Fast, {
                        Color = isOn and Royalty.Theme.Accent or Royalty.Theme.Border
                    })
                    Royalty:Animate(Knob, Royalty.Tokens.Animation.Fast, {
                        Position = isOn and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
                    })
                end

                Royalty:OnThemeChanged(ctrlScope, syncVisual)

                function ToggleObj:Set(newVal: boolean, silent: boolean?)
                    local boolVal = (newVal == true)
                    local changed = (self.Value ~= boolVal)
                    self.Value = boolVal
                    Royalty.Flags[flag] = boolVal
                    syncVisual()
                    if changed and not silent then
                        task.spawn(function()
                            safeCall("Toggle:" .. tName, callback, boolVal)
                        end)
                    end
                end

                function ToggleObj:Get(): boolean
                    return self.Value
                end

                function ToggleObj:SetDisabled(dis: boolean)
                    self.Disabled = (dis == true)
                    syncVisual()
                end

                ctrlScope:Connect(RowBtn.Activated, function()
                    if ToggleObj.Disabled then return end
                    ToggleObj:Set(not ToggleObj.Value)
                end)

                syncVisual()
                if state and callOnInit then
                    task.spawn(function()
                        safeCall("ToggleInit:" .. tName, callback, true)
                    end)
                end

                return ToggleObj
            end

            -- ----------------------------------------------------------------
            -- 5. SLIDER
            -- ----------------------------------------------------------------
            function Section:AddSlider(sCfg: { Name: string?, Description: string?, Min: number?, Max: number?, Default: number?, Rounding: number?, Suffix: string?, CallbackOnRelease: boolean?, Flag: string?, Callback: ((val: number) -> ())? }?)
                sCfg = sCfg or {}
                local ctrlScope = secScope:NewChild()
                local sName = tostring(sCfg.Name or "Slider")
                local sDesc = sCfg.Description and tostring(sCfg.Description) or nil
                local minVal = tonumber(sCfg.Min) or 0
                local maxVal = tonumber(sCfg.Max) or 100
                if maxVal < minVal then
                    minVal, maxVal = maxVal, minVal
                end
                local rounding = math.clamp(math.floor(tonumber(sCfg.Rounding) or 0), 0, 4)
                local suffix = tostring(sCfg.Suffix or "")
                local callbackOnRelease = (sCfg.CallbackOnRelease == true)
                local flag = tostring(sCfg.Flag or sName)
                local callback = sCfg.Callback

                local function roundValue(n: number): number
                    local clamped = math.clamp(n, minVal, maxVal)
                    if rounding <= 0 then
                        return math.floor(clamped + 0.5)
                    end
                    local mult = 10 ^ rounding
                    return math.floor(clamped * mult + 0.5) / mult
                end

                local currentVal = roundValue(tonumber(sCfg.Default) or minVal)
                Royalty.Flags[flag] = currentVal
                local SliderObj = { Value = currentVal }
                Window._controlsByFlag[flag] = SliderObj

                local Container = create("Frame", {
                    Size = UDim2.new(1, 0, 0, 0),
                    AutomaticSize = Enum.AutomaticSize.Y,
                    BackgroundTransparency = 1,
                    Parent = SecFrame
                }, {
                    create("UIListLayout", {
                        SortOrder = Enum.SortOrder.LayoutOrder,
                        Padding = UDim.new(0, 6)
                    })
                })
                registerSectionItem(Container, sName .. " " .. (sDesc or ""))

                local TopRow = create("Frame", {
                    LayoutOrder = 1,
                    Size = UDim2.new(1, 0, 0, 18),
                    BackgroundTransparency = 1,
                    Parent = Container
                })

                local TitleLbl = create("TextLabel", {
                    Size = UDim2.new(0.68, 0, 1, 0),
                    BackgroundTransparency = 1,
                    Text = sName,
                    TextColor3 = Royalty.Theme.Text,
                    Font = Royalty.Tokens.Font.Medium,
                    TextSize = Royalty.Tokens.TextSize.Control,
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = TopRow
                })
                Royalty:BindThemeProperty(ctrlScope, TitleLbl, "TextColor3", "Text")

                local ValueLbl = create("TextLabel", {
                    Size = UDim2.new(0.32, 0, 1, 0),
                    Position = UDim2.new(0.68, 0, 0, 0),
                    BackgroundTransparency = 1,
                    Text = "",
                    TextColor3 = Royalty.Theme.Accent,
                    Font = Royalty.Tokens.Font.Mono,
                    TextSize = Royalty.Tokens.TextSize.Description,
                    TextXAlignment = Enum.TextXAlignment.Right,
                    Parent = TopRow
                })
                Royalty:BindThemeProperty(ctrlScope, ValueLbl, "TextColor3", "Accent")

                if sDesc and sDesc ~= "" then
                    local DescLbl = create("TextLabel", {
                        LayoutOrder = 2,
                        Size = UDim2.new(1, 0, 0, 0),
                        AutomaticSize = Enum.AutomaticSize.Y,
                        BackgroundTransparency = 1,
                        Text = sDesc,
                        TextColor3 = Royalty.Theme.Muted,
                        Font = Royalty.Tokens.Font.Regular,
                        TextSize = Royalty.Tokens.TextSize.Small,
                        TextWrapped = true,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        Parent = Container
                    })
                    Royalty:BindThemeProperty(ctrlScope, DescLbl, "TextColor3", "Muted")
                end

                local TrackHitbox = create("Frame", {
                    LayoutOrder = 3,
                    Size = UDim2.new(1, 0, 0, 16),
                    BackgroundTransparency = 1,
                    Active = true,
                    Parent = Container
                })

                local Track = create("Frame", {
                    Size = UDim2.new(1, 0, 0, 6),
                    Position = UDim2.new(0, 0, 0.5, -3),
                    BackgroundColor3 = Royalty.Theme.SurfaceElevated,
                    BorderSizePixel = 0,
                    Parent = TrackHitbox
                }, {
                    create("UICorner", { CornerRadius = Royalty.Tokens.CornerRadius.Pill })
                })
                Royalty:BindThemeProperty(ctrlScope, Track, "BackgroundColor3", "SurfaceElevated")

                local TrackStroke = create("UIStroke", {
                    Color = Royalty.Theme.Border,
                    Thickness = 1,
                    Parent = Track
                })
                Royalty:BindThemeProperty(ctrlScope, TrackStroke, "Color", "Border")

                local Fill = create("Frame", {
                    Size = UDim2.new(0, 0, 1, 0),
                    BackgroundColor3 = Royalty.Theme.Accent,
                    BorderSizePixel = 0,
                    Parent = Track
                }, {
                    create("UICorner", { CornerRadius = Royalty.Tokens.CornerRadius.Pill })
                })
                Royalty:BindThemeProperty(ctrlScope, Fill, "BackgroundColor3", "Accent")

                local Thumb = create("Frame", {
                    Size = UDim2.new(0, 12, 0, 12),
                    AnchorPoint = Vector2.new(0.5, 0.5),
                    Position = UDim2.new(0, 0, 0.5, 0),
                    BackgroundColor3 = Color3.fromRGB(255, 255, 255),
                    BorderSizePixel = 0,
                    Parent = Track
                }, {
                    create("UICorner", { CornerRadius = Royalty.Tokens.CornerRadius.Pill }),
                    create("UIStroke", { Color = Royalty.Theme.Background, Thickness = 1.5 })
                })

                local function getAlpha(val: number): number
                    if maxVal <= minVal then
                        return 0
                    end
                    return math.clamp((val - minVal) / (maxVal - minVal), 0, 1)
                end

                local function formatVal(v: number): string
                    if rounding > 0 then
                        return string.format("%." .. rounding .. "f%s", v, suffix)
                    end
                    return tostring(v) .. suffix
                end

                local function updateVisualDirect(val: number)
                    local alpha = getAlpha(val)
                    ValueLbl.Text = formatVal(val)
                    Fill.Size = UDim2.new(alpha, 0, 1, 0)
                    Thumb.Position = UDim2.new(alpha, 0, 0.5, 0)
                end

                function SliderObj:Set(newVal: number, silent: boolean?)
                    local rounded = roundValue(tonumber(newVal) or minVal)
                    local changed = (self.Value ~= rounded)
                    self.Value = rounded
                    Royalty.Flags[flag] = rounded
                    updateVisualDirect(rounded)
                    if changed and not silent then
                        task.spawn(function()
                            safeCall("Slider:" .. sName, callback, rounded)
                        end)
                    end
                end

                function SliderObj:Get(): number
                    return self.Value
                end

                local isSliding = false
                local function updateFromPosition(xPos: number, isRelease: boolean)
                    local absWidth = math.max(1, Track.AbsoluteSize.X)
                    local rel = math.clamp((xPos - Track.AbsolutePosition.X) / absWidth, 0, 1)
                    local raw = minVal + (maxVal - minVal) * rel
                    local rounded = roundValue(raw)
                    local changed = (SliderObj.Value ~= rounded)
                    SliderObj.Value = rounded
                    Royalty.Flags[flag] = rounded
                    updateVisualDirect(rounded)

                    if not callbackOnRelease and changed then
                        task.spawn(function()
                            safeCall("Slider:" .. sName, callback, rounded)
                        end)
                    elseif callbackOnRelease and isRelease then
                        task.spawn(function()
                            safeCall("Slider:" .. sName, callback, rounded)
                        end)
                    end
                end

                ctrlScope:Connect(TrackHitbox.InputBegan, function(input)
                    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                        isSliding = true
                        updateFromPosition(input.Position.X, false)
                    end
                end)

                ctrlScope:Connect(UserInputService.InputChanged, function(input)
                    if isSliding and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                        updateFromPosition(input.Position.X, false)
                    end
                end)

                ctrlScope:Connect(UserInputService.InputEnded, function(input)
                    if isSliding and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
                        isSliding = false
                        updateFromPosition(input.Position.X, true)
                    end
                end)

                updateVisualDirect(currentVal)
                return SliderObj
            end

            -- ----------------------------------------------------------------
            -- 6. DROPDOWN (SINGLE & MULTI + BUSCA INTERNA + REFRESH SEGURO)
            -- ----------------------------------------------------------------
            function Section:AddDropdown(dCfg: { Name: string?, Description: string?, Options: { string }?, Default: any, Multi: boolean?, Searchable: boolean?, Flag: string?, Callback: ((val: any) -> ())? }?)
                dCfg = dCfg or {}
                local ctrlScope = secScope:NewChild()
                local dName = tostring(dCfg.Name or "Dropdown")
                local dDesc = dCfg.Description and tostring(dCfg.Description) or nil
                local isMulti = (dCfg.Multi == true)
                local flag = tostring(dCfg.Flag or dName)
                local callback = dCfg.Callback

                local cleanOptions: { string } = {}
                if type(dCfg.Options) == "table" then
                    for _, item in ipairs(dCfg.Options) do
                        table.insert(cleanOptions, tostring(item))
                    end
                end

                -- Normaliza seleção única (string?) ou múltipla ({ [string]: boolean })
                local function normalizeMultiTable(inputVal: any): { [string]: boolean }
                    local map: { [string]: boolean } = {}
                    if type(inputVal) == "table" then
                        if #inputVal > 0 then
                            for _, v in ipairs(inputVal) do
                                local s = tostring(v)
                                if table.find(cleanOptions, s) then
                                    map[s] = true
                                end
                            end
                        else
                            for k, v in pairs(inputVal) do
                                local s = tostring(k)
                                if v == true and table.find(cleanOptions, s) then
                                    map[s] = true
                                end
                            end
                        end
                    end
                    return map
                end

                local currentVal: any
                if isMulti then
                    currentVal = normalizeMultiTable(dCfg.Default)
                else
                    local defStr = dCfg.Default ~= nil and tostring(dCfg.Default) or nil
                    if defStr and table.find(cleanOptions, defStr) then
                        currentVal = defStr
                    else
                        currentVal = cleanOptions[1]
                    end
                end

                Royalty.Flags[flag] = currentVal
                local DropObj = {
                    Value = currentVal,
                    Options = cleanOptions,
                    Open = false
                }
                Window._controlsByFlag[flag] = DropObj

                local Wrapper = create("Frame", {
                    Size = UDim2.new(1, 0, 0, 0),
                    AutomaticSize = Enum.AutomaticSize.Y,
                    BackgroundTransparency = 1,
                    Parent = SecFrame
                }, {
                    create("UIListLayout", {
                        SortOrder = Enum.SortOrder.LayoutOrder,
                        Padding = UDim.new(0, 5)
                    })
                })
                registerSectionItem(Wrapper, dName .. " " .. (dDesc or ""))

                local TitleLbl = create("TextLabel", {
                    LayoutOrder = 1,
                    Size = UDim2.new(1, 0, 0, 16),
                    BackgroundTransparency = 1,
                    Text = dName,
                    TextColor3 = Royalty.Theme.Text,
                    Font = Royalty.Tokens.Font.Medium,
                    TextSize = Royalty.Tokens.TextSize.Control,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = Wrapper
                })
                Royalty:BindThemeProperty(ctrlScope, TitleLbl, "TextColor3", "Text")

                if dDesc and dDesc ~= "" then
                    local DescLbl = create("TextLabel", {
                        LayoutOrder = 2,
                        Size = UDim2.new(1, 0, 0, 0),
                        AutomaticSize = Enum.AutomaticSize.Y,
                        BackgroundTransparency = 1,
                        Text = dDesc,
                        TextColor3 = Royalty.Theme.Muted,
                        Font = Royalty.Tokens.Font.Regular,
                        TextSize = Royalty.Tokens.TextSize.Small,
                        TextWrapped = true,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        Parent = Wrapper
                    })
                    Royalty:BindThemeProperty(ctrlScope, DescLbl, "TextColor3", "Muted")
                end

                local HeaderBtn = create("TextButton", {
                    LayoutOrder = 3,
                    Size = UDim2.new(1, 0, 0, 30),
                    BackgroundColor3 = Royalty.Theme.SurfaceElevated,
                    AutoButtonColor = false,
                    Text = "",
                    Parent = Wrapper
                }, {
                    create("UICorner", { CornerRadius = Royalty.Tokens.CornerRadius.Control })
                })
                Royalty:BindThemeProperty(ctrlScope, HeaderBtn, "BackgroundColor3", "SurfaceElevated")

                local HeaderStroke = create("UIStroke", {
                    Color = Royalty.Theme.Border,
                    Thickness = 1,
                    Parent = HeaderBtn
                })
                Royalty:BindThemeProperty(ctrlScope, HeaderStroke, "Color", "Border")

                local SelectedLbl = create("TextLabel", {
                    Size = UDim2.new(1, -34, 1, 0),
                    Position = UDim2.new(0, 10, 0, 0),
                    BackgroundTransparency = 1,
                    Text = "",
                    TextColor3 = Royalty.Theme.Text,
                    Font = Royalty.Tokens.Font.Regular,
                    TextSize = Royalty.Tokens.TextSize.Description,
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = HeaderBtn
                })
                Royalty:BindThemeProperty(ctrlScope, SelectedLbl, "TextColor3", "Text")

                local Chevron = create("TextLabel", {
                    Size = UDim2.new(0, 20, 1, 0),
                    Position = UDim2.new(1, -24, 0, 0),
                    BackgroundTransparency = 1,
                    Text = "▾",
                    TextColor3 = Royalty.Theme.SubText,
                    Font = Royalty.Tokens.Font.Bold,
                    TextSize = 13,
                    Parent = HeaderBtn
                })
                Royalty:BindThemeProperty(ctrlScope, Chevron, "TextColor3", "SubText")

                local DropdownPanel = create("Frame", {
                    LayoutOrder = 4,
                    Size = UDim2.new(1, 0, 0, 0),
                    AutomaticSize = Enum.AutomaticSize.Y,
                    BackgroundColor3 = Royalty.Theme.Sidebar,
                    Visible = false,
                    Parent = Wrapper
                }, {
                    create("UICorner", { CornerRadius = Royalty.Tokens.CornerRadius.Control }),
                    create("UIPadding", {
                        PaddingTop = UDim.new(0, 6),
                        PaddingBottom = UDim.new(0, 6),
                        PaddingLeft = UDim.new(0, 6),
                        PaddingRight = UDim.new(0, 6)
                    }),
                    create("UIListLayout", {
                        SortOrder = Enum.SortOrder.LayoutOrder,
                        Padding = UDim.new(0, 4)
                    })
                })
                Royalty:BindThemeProperty(ctrlScope, DropdownPanel, "BackgroundColor3", "Sidebar")

                local PanelStroke = create("UIStroke", {
                    Color = Royalty.Theme.Border,
                    Thickness = 1,
                    Parent = DropdownPanel
                })
                Royalty:BindThemeProperty(ctrlScope, PanelStroke, "Color", "Border")

                local FilterBox = create("TextBox", {
                    LayoutOrder = 1,
                    Size = UDim2.new(1, 0, 0, 24),
                    BackgroundColor3 = Royalty.Theme.Surface,
                    Visible = (dCfg.Searchable == true) or (#cleanOptions >= 6),
                    Text = "",
                    PlaceholderText = "Filtrar opções...",
                    PlaceholderColor3 = Royalty.Theme.Muted,
                    TextColor3 = Royalty.Theme.Text,
                    Font = Royalty.Tokens.Font.Regular,
                    TextSize = Royalty.Tokens.TextSize.Small,
                    ClearTextOnFocus = false,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = DropdownPanel
                }, {
                    create("UICorner", { CornerRadius = UDim.new(0, 4) }),
                    create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) })
                })
                Royalty:BindThemeProperty(ctrlScope, FilterBox, "BackgroundColor3", "Surface")
                Royalty:BindThemeProperty(ctrlScope, FilterBox, "TextColor3", "Text")
                Royalty:BindThemeProperty(ctrlScope, FilterBox, "PlaceholderColor3", "Muted")

                local OptionsScroll = create("ScrollingFrame", {
                    LayoutOrder = 2,
                    Size = UDim2.new(1, 0, 0, 120),
                    BackgroundTransparency = 1,
                    BorderSizePixel = 0,
                    ScrollBarThickness = 2,
                    ScrollBarImageColor3 = Royalty.Theme.Accent,
                    CanvasSize = UDim2.new(0, 0, 0, 0),
                    AutomaticCanvasSize = Enum.AutomaticSize.Y,
                    Parent = DropdownPanel
                }, {
                    create("UIListLayout", {
                        SortOrder = Enum.SortOrder.LayoutOrder,
                        Padding = UDim.new(0, 2)
                    })
                })
                Royalty:BindThemeProperty(ctrlScope, OptionsScroll, "ScrollBarImageColor3", "Accent")

                local optionsScope = ctrlScope:NewChild()

                local function updateHeaderText()
                    if #DropObj.Options == 0 then
                        SelectedLbl.Text = "Sem opções"
                        return
                    end
                    if isMulti then
                        local list = {}
                        for _, opt in ipairs(DropObj.Options) do
                            if DropObj.Value[opt] then
                                table.insert(list, opt)
                            end
                        end
                        SelectedLbl.Text = (#list > 0) and table.concat(list, ", ") or "Nenhum selecionado"
                    else
                        SelectedLbl.Text = DropObj.Value ~= nil and tostring(DropObj.Value) or "Selecionar..."
                    end
                end

                local function rebuildOptionButtons()
                    optionsScope:Clean()
                    for _, child in ipairs(OptionsScroll:GetChildren()) do
                        if not child:IsA("UIListLayout") then
                            child:Destroy()
                        end
                    end

                    local filterQuery = string.lower(string.gsub(FilterBox.Text, "^%s*(.-)%s*$", "%1"))
                    local visibleCount = 0

                    for idx, opt in ipairs(DropObj.Options) do
                        if filterQuery == "" or string.find(string.lower(opt), filterQuery, 1, true) ~= nil then
                            visibleCount += 1
                            local isSelected = isMulti and (DropObj.Value[opt] == true) or (DropObj.Value == opt)

                            local OptBtn = create("TextButton", {
                                LayoutOrder = idx,
                                Size = UDim2.new(1, 0, 0, 26),
                                BackgroundColor3 = isSelected and Royalty.Theme.SurfaceElevated or Royalty.Theme.Sidebar,
                                BackgroundTransparency = isSelected and 0 or 1,
                                AutoButtonColor = false,
                                Text = "",
                                Parent = OptionsScroll
                            }, {
                                create("UICorner", { CornerRadius = UDim.new(0, 4) })
                            })

                            local OptText = create("TextLabel", {
                                Size = UDim2.new(1, -28, 1, 0),
                                Position = UDim2.new(0, 8, 0, 0),
                                BackgroundTransparency = 1,
                                Text = opt,
                                TextColor3 = isSelected and Royalty.Theme.Accent or Royalty.Theme.SubText,
                                Font = isSelected and Royalty.Tokens.Font.Semibold or Royalty.Tokens.Font.Regular,
                                TextSize = Royalty.Tokens.TextSize.Description,
                                TextTruncate = Enum.TextTruncate.AtEnd,
                                TextXAlignment = Enum.TextXAlignment.Left,
                                Parent = OptBtn
                            })

                            local CheckLbl = create("TextLabel", {
                                Size = UDim2.new(0, 18, 1, 0),
                                Position = UDim2.new(1, -22, 0, 0),
                                BackgroundTransparency = 1,
                                Text = isSelected and "✓" or "",
                                TextColor3 = Royalty.Theme.Accent,
                                Font = Royalty.Tokens.Font.Bold,
                                TextSize = 12,
                                Parent = OptBtn
                            })

                            optionsScope:Connect(OptBtn.Activated, function()
                                if isMulti then
                                    if DropObj.Value[opt] then
                                        DropObj.Value[opt] = nil
                                    else
                                        DropObj.Value[opt] = true
                                    end
                                    Royalty.Flags[flag] = table.clone(DropObj.Value)
                                    updateHeaderText()
                                    rebuildOptionButtons()
                                    task.spawn(function()
                                        safeCall("Dropdown:" .. dName, callback, table.clone(DropObj.Value))
                                    end)
                                else
                                    DropObj:Set(opt)
                                    DropObj.Open = false
                                    DropdownPanel.Visible = false
                                    Chevron.Text = "▾"
                                    Tab:_updateColumns()
                                end
                            end)
                        end
                    end

                    if visibleCount == 0 then
                        create("TextLabel", {
                            Size = UDim2.new(1, 0, 0, 26),
                            BackgroundTransparency = 1,
                            Text = (#DropObj.Options == 0) and "Nenhuma opção disponível" or "Nenhum resultado",
                            TextColor3 = Royalty.Theme.Muted,
                            Font = Royalty.Tokens.Font.Regular,
                            TextSize = Royalty.Tokens.TextSize.Small,
                            Parent = OptionsScroll
                        })
                        OptionsScroll.Size = UDim2.new(1, 0, 0, 28)
                    else
                        local targetH = math.min(visibleCount * 28, 140)
                        OptionsScroll.Size = UDim2.new(1, 0, 0, targetH)
                    end
                end

                ctrlScope:Connect(FilterBox:GetPropertyChangedSignal("Text"), rebuildOptionButtons)
                Royalty:OnThemeChanged(ctrlScope, function()
                    updateHeaderText()
                    rebuildOptionButtons()
                end)

                function DropObj:Set(newVal: any, silent: boolean?)
                    if isMulti then
                        self.Value = normalizeMultiTable(newVal)
                        Royalty.Flags[flag] = table.clone(self.Value)
                        updateHeaderText()
                        rebuildOptionButtons()
                        if not silent then
                            task.spawn(function()
                                safeCall("Dropdown:" .. dName, callback, table.clone(self.Value))
                            end)
                        end
                    else
                        local strVal = newVal ~= nil and tostring(newVal) or nil
                        if strVal and table.find(self.Options, strVal) then
                            self.Value = strVal
                        else
                            self.Value = self.Options[1]
                        end
                        Royalty.Flags[flag] = self.Value
                        updateHeaderText()
                        rebuildOptionButtons()
                        if not silent then
                            task.spawn(function()
                                safeCall("Dropdown:" .. dName, callback, self.Value)
                            end)
                        end
                    end
                end

                function DropObj:Refresh(newOptions: { string }?, newDefault: any, silent: boolean?)
                    local cleaned = {}
                    if type(newOptions) == "table" then
                        for _, item in ipairs(newOptions) do
                            table.insert(cleaned, tostring(item))
                        end
                    end
                    self.Options = cleaned
                    cleanOptions = cleaned
                    FilterBox.Visible = (dCfg.Searchable == true) or (#cleaned >= 6)
                    FilterBox.Text = ""

                    if newDefault ~= nil then
                        self:Set(newDefault, silent)
                    else
                        self:Set(self.Value, true)
                    end
                end

                function DropObj:Get(): any
                    if isMulti then
                        return table.clone(self.Value)
                    end
                    return self.Value
                end

                ctrlScope:Connect(HeaderBtn.Activated, function()
                    DropObj.Open = not DropObj.Open
                    DropdownPanel.Visible = DropObj.Open
                    Chevron.Text = DropObj.Open and "▴" or "▾"
                    if DropObj.Open then
                        rebuildOptionButtons()
                    end
                    Tab:_updateColumns()
                end)

                updateHeaderText()
                rebuildOptionButtons()
                return DropObj
            end

            -- ----------------------------------------------------------------
            -- 7. KEYBIND (COM CANCELAMENTO SEGURO E RESPEITO A TEXTBOX)
            -- ----------------------------------------------------------------
            function Section:AddKeybind(kCfg: { Name: string?, Description: string?, Default: any, Mode: string?, Flag: string?, Callback: ((active: boolean) -> ())?, ChangedCallback: ((newKey: any) -> ())? }?)
                kCfg = kCfg or {}
                local ctrlScope = secScope:NewChild()
                local kName = tostring(kCfg.Name or "Keybind")
                local kDesc = kCfg.Description and tostring(kCfg.Description) or nil
                local currentKey = kCfg.Default
                local currentMode = (kCfg.Mode and string.lower(tostring(kCfg.Mode)) == "hold") and "Hold" or "Toggle"
                local flag = tostring(kCfg.Flag or kName)
                local callback = kCfg.Callback
                local changedCallback = kCfg.ChangedCallback

                Royalty.Flags[flag] = currentKey
                local KeyObj = {
                    Key = currentKey,
                    Mode = currentMode,
                    Active = false,
                    Binding = false
                }
                Window._controlsByFlag[flag] = KeyObj

                local Row = create("Frame", {
                    Size = UDim2.new(1, 0, 0, 0),
                    AutomaticSize = Enum.AutomaticSize.Y,
                    BackgroundTransparency = 1,
                    Parent = SecFrame
                })
                registerSectionItem(Row, kName .. " " .. (kDesc or ""))

                local TextStack = create("Frame", {
                    Size = UDim2.new(1, -110, 0, 0),
                    AutomaticSize = Enum.AutomaticSize.Y,
                    BackgroundTransparency = 1,
                    Parent = Row
                }, {
                    create("UIListLayout", {
                        SortOrder = Enum.SortOrder.LayoutOrder,
                        Padding = UDim.new(0, 2)
                    })
                })

                local TitleLbl = create("TextLabel", {
                    LayoutOrder = 1,
                    Size = UDim2.new(1, 0, 0, 18),
                    BackgroundTransparency = 1,
                    Text = kName,
                    TextColor3 = Royalty.Theme.Text,
                    Font = Royalty.Tokens.Font.Medium,
                    TextSize = Royalty.Tokens.TextSize.Control,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = TextStack
                })
                Royalty:BindThemeProperty(ctrlScope, TitleLbl, "TextColor3", "Text")

                if kDesc and kDesc ~= "" then
                    local DescLbl = create("TextLabel", {
                        LayoutOrder = 2,
                        Size = UDim2.new(1, 0, 0, 0),
                        AutomaticSize = Enum.AutomaticSize.Y,
                        BackgroundTransparency = 1,
                        Text = kDesc,
                        TextColor3 = Royalty.Theme.Muted,
                        Font = Royalty.Tokens.Font.Regular,
                        TextSize = Royalty.Tokens.TextSize.Small,
                        TextWrapped = true,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        Parent = TextStack
                    })
                    Royalty:BindThemeProperty(ctrlScope, DescLbl, "TextColor3", "Muted")
                end

                local ModeBtn = create("TextButton", {
                    Size = UDim2.new(0, 42, 0, 22),
                    Position = UDim2.new(1, -106, 0, 0),
                    BackgroundColor3 = Royalty.Theme.SurfaceElevated,
                    AutoButtonColor = false,
                    Text = currentMode,
                    TextColor3 = Royalty.Theme.SubText,
                    Font = Royalty.Tokens.Font.Medium,
                    TextSize = 10,
                    Parent = Row
                }, {
                    create("UICorner", { CornerRadius = UDim.new(0, 4) })
                })
                Royalty:BindThemeProperty(ctrlScope, ModeBtn, "BackgroundColor3", "SurfaceElevated")
                Royalty:BindThemeProperty(ctrlScope, ModeBtn, "TextColor3", "SubText")

                local KeyBtn = create("TextButton", {
                    Size = UDim2.new(0, 60, 0, 22),
                    Position = UDim2.new(1, -60, 0, 0),
                    BackgroundColor3 = Royalty.Theme.SurfaceElevated,
                    AutoButtonColor = false,
                    Text = "[" .. formatKeyName(currentKey) .. "]",
                    TextColor3 = Royalty.Theme.Text,
                    Font = Royalty.Tokens.Font.Mono,
                    TextSize = Royalty.Tokens.TextSize.Small,
                    Parent = Row
                }, {
                    create("UICorner", { CornerRadius = UDim.new(0, 5) })
                })
                Royalty:BindThemeProperty(ctrlScope, KeyBtn, "BackgroundColor3", "SurfaceElevated")
                Royalty:BindThemeProperty(ctrlScope, KeyBtn, "TextColor3", "Text")

                local KeyStroke = create("UIStroke", {
                    Color = Royalty.Theme.Border,
                    Thickness = 1,
                    Parent = KeyBtn
                })
                Royalty:BindThemeProperty(ctrlScope, KeyStroke, "Color", "Border")

                function KeyObj:Set(newKey: any, silent: boolean?)
                    self.Key = newKey
                    Royalty.Flags[flag] = newKey
                    KeyBtn.Text = "[" .. formatKeyName(newKey) .. "]"
                    if not silent then
                        task.spawn(function()
                            safeCall("KeybindChanged:" .. kName, changedCallback, newKey)
                        end)
                    end
                end

                function KeyObj:Get(): any
                    return self.Key
                end

                function KeyObj:SetMode(newMode: string)
                    self.Mode = (string.lower(tostring(newMode)) == "hold") and "Hold" or "Toggle"
                    ModeBtn.Text = self.Mode
                end

                function KeyObj:GetMode(): string
                    return self.Mode
                end

                ctrlScope:Connect(ModeBtn.Activated, function()
                    KeyObj:SetMode(KeyObj.Mode == "Toggle" and "Hold" or "Toggle")
                end)

                ctrlScope:Connect(KeyBtn.Activated, function()
                    KeyObj.Binding = true
                    Window._isBindingKey = true
                    KeyBtn.Text = "[ ... ]"
                    Royalty:Animate(KeyStroke, Royalty.Tokens.Animation.Fast, { Color = Royalty.Theme.Accent })
                end)

                ctrlScope:Connect(UserInputService.InputBegan, function(input, gameProcessed)
                    if KeyObj.Binding then
                        -- Escape cancela sem apagar a tecla anterior; Backspace/Delete limpa para None
                        if input.KeyCode == Enum.KeyCode.Escape then
                            KeyObj.Binding = false
                            task.defer(function() Window._isBindingKey = false end)
                            KeyBtn.Text = "[" .. formatKeyName(KeyObj.Key) .. "]"
                            Royalty:Animate(KeyStroke, Royalty.Tokens.Animation.Fast, { Color = Royalty.Theme.Border })
                            return
                        elseif input.KeyCode == Enum.KeyCode.Backspace or input.KeyCode == Enum.KeyCode.Delete then
                            KeyObj.Binding = false
                            task.defer(function() Window._isBindingKey = false end)
                            KeyObj:Set(nil)
                            Royalty:Animate(KeyStroke, Royalty.Tokens.Animation.Fast, { Color = Royalty.Theme.Border })
                            return
                        end

                        local chosen = nil
                        if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode ~= Enum.KeyCode.Unknown then
                            chosen = input.KeyCode
                        elseif input.UserInputType == Enum.UserInputType.MouseButton1
                            or input.UserInputType == Enum.UserInputType.MouseButton2
                            or input.UserInputType == Enum.UserInputType.MouseButton3 then
                            chosen = input.UserInputType
                        end

                        if chosen then
                            KeyObj.Binding = false
                            task.defer(function() Window._isBindingKey = false end)
                            KeyObj:Set(chosen)
                            Royalty:Animate(KeyStroke, Royalty.Tokens.Animation.Fast, { Color = Royalty.Theme.Border })
                        end
                        return
                    end

                    -- Ignora se o usuário estiver digitando em qualquer TextBox ou se conflitar com o ToggleKey da janela
                    if gameProcessed or UserInputService:GetFocusedTextBox() ~= nil then
                        return
                    end
                    if not KeyObj.Key or KeyObj.Key == Window.ToggleKey then
                        return
                    end

                    local matched = (input.KeyCode == KeyObj.Key) or (input.UserInputType == KeyObj.Key)
                    if matched then
                        if KeyObj.Mode == "Hold" then
                            if not KeyObj.Active then
                                KeyObj.Active = true
                                task.spawn(function()
                                    safeCall("Keybind:" .. kName, callback, true)
                                end)
                            end
                        else
                            KeyObj.Active = not KeyObj.Active
                            task.spawn(function()
                                safeCall("Keybind:" .. kName, callback, KeyObj.Active)
                            end)
                        end
                    end
                end)

                ctrlScope:Connect(UserInputService.InputEnded, function(input)
                    if KeyObj.Binding or not KeyObj.Key or KeyObj.Mode ~= "Hold" then
                        return
                    end
                    local matched = (input.KeyCode == KeyObj.Key) or (input.UserInputType == KeyObj.Key)
                    if matched and KeyObj.Active then
                        KeyObj.Active = false
                        task.spawn(function()
                            safeCall("Keybind:" .. kName, callback, false)
                        end)
                    end
                end)

                return KeyObj
            end

            -- ----------------------------------------------------------------
            -- 8. COLOR PICKER (HSV FIEL + INDICADORES + VALIDAÇÃO HEX)
            -- ----------------------------------------------------------------
            function Section:AddColorPicker(cCfg: { Name: string?, Description: string?, Default: Color3?, Flag: string?, Callback: ((color: Color3) -> ())? }?)
                cCfg = cCfg or {}
                local ctrlScope = secScope:NewChild()
                local cName = tostring(cCfg.Name or "Color")
                local cDesc = cCfg.Description and tostring(cCfg.Description) or nil
                local currentColor: Color3 = typeof(cCfg.Default) == "Color3" and cCfg.Default or Royalty.Theme.Accent
                local flag = tostring(cCfg.Flag or cName)
                local callback = cCfg.Callback

                local h, s, v = Color3.toHSV(currentColor)
                Royalty.Flags[flag] = currentColor
                local ColorObj = {
                    Value = currentColor,
                    Open = false
                }
                Window._controlsByFlag[flag] = ColorObj

                local Wrapper = create("Frame", {
                    Size = UDim2.new(1, 0, 0, 0),
                    AutomaticSize = Enum.AutomaticSize.Y,
                    BackgroundTransparency = 1,
                    Parent = SecFrame
                }, {
                    create("UIListLayout", {
                        SortOrder = Enum.SortOrder.LayoutOrder,
                        Padding = UDim.new(0, 6)
                    })
                })
                registerSectionItem(Wrapper, cName .. " " .. (cDesc or ""))

                local TopRow = create("TextButton", {
                    LayoutOrder = 1,
                    Size = UDim2.new(1, 0, 0, 24),
                    BackgroundTransparency = 1,
                    AutoButtonColor = false,
                    Text = "",
                    Parent = Wrapper
                })

                local TitleLbl = create("TextLabel", {
                    Size = UDim2.new(1, -50, 1, 0),
                    BackgroundTransparency = 1,
                    Text = cName,
                    TextColor3 = Royalty.Theme.Text,
                    Font = Royalty.Tokens.Font.Medium,
                    TextSize = Royalty.Tokens.TextSize.Control,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = TopRow
                })
                Royalty:BindThemeProperty(ctrlScope, TitleLbl, "TextColor3", "Text")

                local SwatchBtn = create("Frame", {
                    Size = UDim2.new(0, 38, 0, 20),
                    Position = UDim2.new(1, -38, 0.5, -10),
                    BackgroundColor3 = currentColor,
                    Parent = TopRow
                }, {
                    create("UICorner", { CornerRadius = UDim.new(0, 5) }),
                    create("UIStroke", { Color = Royalty.Theme.Border, Thickness = 1 })
                })

                local PickerPanel = create("Frame", {
                    LayoutOrder = 2,
                    Size = UDim2.new(1, 0, 0, 0),
                    AutomaticSize = Enum.AutomaticSize.Y,
                    BackgroundColor3 = Royalty.Theme.Sidebar,
                    Visible = false,
                    Parent = Wrapper
                }, {
                    create("UICorner", { CornerRadius = Royalty.Tokens.CornerRadius.Control }),
                    create("UIStroke", { Color = Royalty.Theme.Border, Thickness = 1 }),
                    create("UIPadding", {
                        PaddingTop = UDim.new(0, 8),
                        PaddingBottom = UDim.new(0, 8),
                        PaddingLeft = UDim.new(0, 10),
                        PaddingRight = UDim.new(0, 10)
                    }),
                    create("UIListLayout", {
                        SortOrder = Enum.SortOrder.LayoutOrder,
                        Padding = UDim.new(0, 8)
                    })
                })
                Royalty:BindThemeProperty(ctrlScope, PickerPanel, "BackgroundColor3", "Sidebar")

                local function createHSVBar(order: number, labelText: string)
                    local row = create("Frame", {
                        LayoutOrder = order,
                        Size = UDim2.new(1, 0, 0, 18),
                        BackgroundTransparency = 1,
                        Parent = PickerPanel
                    })
                    local lbl = create("TextLabel", {
                        Size = UDim2.new(0, 16, 1, 0),
                        BackgroundTransparency = 1,
                        Text = labelText,
                        TextColor3 = Royalty.Theme.Muted,
                        Font = Royalty.Tokens.Font.Bold,
                        TextSize = 11,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        Parent = row
                    })
                    Royalty:BindThemeProperty(ctrlScope, lbl, "TextColor3", "Muted")

                    local bar = create("Frame", {
                        Size = UDim2.new(1, -22, 0, 10),
                        Position = UDim2.new(0, 22, 0.5, -5),
                        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
                        BorderSizePixel = 0,
                        Active = true,
                        Parent = row
                    }, {
                        create("UICorner", { CornerRadius = Royalty.Tokens.CornerRadius.Pill }),
                        create("UIStroke", { Color = Royalty.Theme.Border, Thickness = 1 })
                    })

                    local grad = create("UIGradient", { Parent = bar })

                    local cursor = create("Frame", {
                        Size = UDim2.new(0, 8, 0, 14),
                        AnchorPoint = Vector2.new(0.5, 0.5),
                        Position = UDim2.new(0, 0, 0.5, 0),
                        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
                        BorderSizePixel = 0,
                        Parent = bar
                    }, {
                        create("UICorner", { CornerRadius = UDim.new(0, 3) }),
                        create("UIStroke", { Color = Color3.fromRGB(15, 15, 20), Thickness = 1.5 })
                    })

                    return bar, grad, cursor
                end

                local HueBar, HueGrad, HueCursor = createHSVBar(1, "H")
                HueGrad.Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 0, 0)),
                    ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 255, 0)),
                    ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 255, 0)),
                    ColorSequenceKeypoint.new(0.50, Color3.fromRGB(0, 255, 255)),
                    ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 0, 255)),
                    ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 0, 255)),
                    ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 0, 0))
                })

                local SatBar, SatGrad, SatCursor = createHSVBar(2, "S")
                local ValBar, ValGrad, ValCursor = createHSVBar(3, "V")

                local BottomRow = create("Frame", {
                    LayoutOrder = 4,
                    Size = UDim2.new(1, 0, 0, 24),
                    BackgroundTransparency = 1,
                    Parent = PickerPanel
                })

                local RGBLabel = create("TextLabel", {
                    Size = UDim2.new(0.55, 0, 1, 0),
                    BackgroundTransparency = 1,
                    Text = "",
                    TextColor3 = Royalty.Theme.SubText,
                    Font = Royalty.Tokens.Font.Mono,
                    TextSize = 11,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = BottomRow
                })
                Royalty:BindThemeProperty(ctrlScope, RGBLabel, "TextColor3", "SubText")

                local HexBox = create("TextBox", {
                    Size = UDim2.new(0.42, 0, 1, 0),
                    Position = UDim2.new(0.58, 0, 0, 0),
                    BackgroundColor3 = Royalty.Theme.Surface,
                    Text = colorToHex(currentColor),
                    PlaceholderText = "#RRGGBB",
                    TextColor3 = Royalty.Theme.Text,
                    Font = Royalty.Tokens.Font.Mono,
                    TextSize = 11,
                    ClearTextOnFocus = false,
                    Parent = BottomRow
                }, {
                    create("UICorner", { CornerRadius = UDim.new(0, 4) })
                })
                Royalty:BindThemeProperty(ctrlScope, HexBox, "BackgroundColor3", "Surface")
                Royalty:BindThemeProperty(ctrlScope, HexBox, "TextColor3", "Text")

                local HexStroke = create("UIStroke", {
                    Color = Royalty.Theme.Border,
                    Thickness = 1,
                    Parent = HexBox
                })

                local function syncPickerVisuals()
                    local pureHue = Color3.fromHSV(h, 1, 1)
                    local fullValColor = Color3.fromHSV(h, s, 1)

                    -- Saturação vai de Branco até a cor da Matiz atual
                    SatGrad.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), pureHue)
                    -- Valor/Brilho vai de Preto até a cor saturada atual
                    ValGrad.Color = ColorSequence.new(Color3.fromRGB(0, 0, 0), fullValColor)

                    HueCursor.Position = UDim2.new(math.clamp(h, 0, 1), 0, 0.5, 0)
                    SatCursor.Position = UDim2.new(math.clamp(s, 0, 1), 0, 0.5, 0)
                    ValCursor.Position = UDim2.new(math.clamp(v, 0, 1), 0, 0.5, 0)

                    local c = ColorObj.Value
                    SwatchBtn.BackgroundColor3 = c
                    RGBLabel.Text = string.format(
                        "%d, %d, %d",
                        math.floor(c.R * 255 + 0.5),
                        math.floor(c.G * 255 + 0.5),
                        math.floor(c.B * 255 + 0.5)
                    )
                    if UserInputService:GetFocusedTextBox() ~= HexBox then
                        HexBox.Text = colorToHex(c)
                    end
                end

                function ColorObj:Set(newColor: Color3, silent: boolean?)
                    if typeof(newColor) ~= "Color3" then return end
                    self.Value = newColor
                    h, s, v = Color3.toHSV(newColor)
                    Royalty.Flags[flag] = newColor
                    syncPickerVisuals()
                    if not silent then
                        task.spawn(function()
                            safeCall("ColorPicker:" .. cName, callback, newColor)
                        end)
                    end
                end

                function ColorObj:Get(): Color3
                    return self.Value
                end

                -- Uma única conexão compartilhada de InputChanged/Ended para as 3 barras do Picker
                local activeBarMode: string? = nil
                local function updateBarFromX(barMode: string, xPos: number)
                    local targetBar = (barMode == "H" and HueBar) or (barMode == "S" and SatBar) or ValBar
                    local rel = math.clamp((xPos - targetBar.AbsolutePosition.X) / math.max(1, targetBar.AbsoluteSize.X), 0, 1)
                    if barMode == "H" then
                        h = rel
                    elseif barMode == "S" then
                        s = rel
                    else
                        v = rel
                    end
                    local computed = Color3.fromHSV(h, s, v)
                    ColorObj.Value = computed
                    Royalty.Flags[flag] = computed
                    syncPickerVisuals()
                    task.spawn(function()
                        safeCall("ColorPicker:" .. cName, callback, computed)
                    end)
                end

                ctrlScope:Connect(HueBar.InputBegan, function(inp)
                    if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
                        activeBarMode = "H"
                        updateBarFromX("H", inp.Position.X)
                    end
                end)
                ctrlScope:Connect(SatBar.InputBegan, function(inp)
                    if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
                        activeBarMode = "S"
                        updateBarFromX("S", inp.Position.X)
                    end
                end)
                ctrlScope:Connect(ValBar.InputBegan, function(inp)
                    if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
                        activeBarMode = "V"
                        updateBarFromX("V", inp.Position.X)
                    end
                end)

                ctrlScope:Connect(UserInputService.InputChanged, function(inp)
                    if activeBarMode and (inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch) then
                        updateBarFromX(activeBarMode, inp.Position.X)
                    end
                end)
                ctrlScope:Connect(UserInputService.InputEnded, function(inp)
                    if activeBarMode and (inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch) then
                        activeBarMode = nil
                    end
                end)

                ctrlScope:Connect(HexBox.FocusLost, function()
                    local parsed = hexToColor(HexBox.Text)
                    if parsed then
                        HexStroke.Color = Royalty.Theme.Border
                        ColorObj:Set(parsed)
                    else
                        -- Sinaliza erro visual sem corromper o valor atual
                        HexStroke.Color = Royalty.Theme.Error
                        task.delay(0.8, function()
                            if HexBox and HexBox.Parent then
                                HexStroke.Color = Royalty.Theme.Border
                                HexBox.Text = colorToHex(ColorObj.Value)
                            end
                        end)
                    end
                end)

                ctrlScope:Connect(TopRow.Activated, function()
                    ColorObj.Open = not ColorObj.Open
                    PickerPanel.Visible = ColorObj.Open
                    if ColorObj.Open then
                        syncPickerVisuals()
                    end
                    Tab:_updateColumns()
                end)

                syncPickerVisuals()
                return ColorObj
            end

            -- ----------------------------------------------------------------
            -- 9. INPUT (TEXTBOX COM VALIDAÇÃO, LIMITE E ESTADOS DE FOCO)
            -- ----------------------------------------------------------------
            function Section:AddInput(iCfg: { Name: string?, Description: string?, Placeholder: string?, Default: string?, MaxLength: number?, CallbackOnType: boolean?, Validator: ((txt: string) -> boolean)?, Flag: string?, Callback: ((txt: string) -> ())? }?)
                iCfg = iCfg or {}
                local ctrlScope = secScope:NewChild()
                local iName = tostring(iCfg.Name or "Input")
                local iDesc = iCfg.Description and tostring(iCfg.Description) or nil
                local placeholder = tostring(iCfg.Placeholder or "Digite aqui...")
                local maxLen = tonumber(iCfg.MaxLength)
                local callbackOnType = (iCfg.CallbackOnType == true)
                local validator = iCfg.Validator
                local flag = tostring(iCfg.Flag or iName)
                local callback = iCfg.Callback

                local currentText = tostring(iCfg.Default or "")
                if maxLen and #currentText > maxLen then
                    currentText = string.sub(currentText, 1, maxLen)
                end

                Royalty.Flags[flag] = currentText
                local InputObj = { Value = currentText }
                Window._controlsByFlag[flag] = InputObj

                local Container = create("Frame", {
                    Size = UDim2.new(1, 0, 0, 0),
                    AutomaticSize = Enum.AutomaticSize.Y,
                    BackgroundTransparency = 1,
                    Parent = SecFrame
                }, {
                    create("UIListLayout", {
                        SortOrder = Enum.SortOrder.LayoutOrder,
                        Padding = UDim.new(0, 5)
                    })
                })
                registerSectionItem(Container, iName .. " " .. (iDesc or ""))

                local TitleLbl = create("TextLabel", {
                    LayoutOrder = 1,
                    Size = UDim2.new(1, 0, 0, 16),
                    BackgroundTransparency = 1,
                    Text = iName,
                    TextColor3 = Royalty.Theme.Text,
                    Font = Royalty.Tokens.Font.Medium,
                    TextSize = Royalty.Tokens.TextSize.Control,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = Container
                })
                Royalty:BindThemeProperty(ctrlScope, TitleLbl, "TextColor3", "Text")

                if iDesc and iDesc ~= "" then
                    local DescLbl = create("TextLabel", {
                        LayoutOrder = 2,
                        Size = UDim2.new(1, 0, 0, 0),
                        AutomaticSize = Enum.AutomaticSize.Y,
                        BackgroundTransparency = 1,
                        Text = iDesc,
                        TextColor3 = Royalty.Theme.Muted,
                        Font = Royalty.Tokens.Font.Regular,
                        TextSize = Royalty.Tokens.TextSize.Small,
                        TextWrapped = true,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        Parent = Container
                    })
                    Royalty:BindThemeProperty(ctrlScope, DescLbl, "TextColor3", "Muted")
                end

                local BoxHolder = create("Frame", {
                    LayoutOrder = 3,
                    Size = UDim2.new(1, 0, 0, 30),
                    BackgroundColor3 = Royalty.Theme.SurfaceElevated,
                    Parent = Container
                }, {
                    create("UICorner", { CornerRadius = Royalty.Tokens.CornerRadius.Control })
                })
                Royalty:BindThemeProperty(ctrlScope, BoxHolder, "BackgroundColor3", "SurfaceElevated")

                local BoxStroke = create("UIStroke", {
                    Color = Royalty.Theme.Border,
                    Thickness = 1,
                    Parent = BoxHolder
                })
                Royalty:BindThemeProperty(ctrlScope, BoxStroke, "Color", "Border")

                local Box = create("TextBox", {
                    Size = UDim2.new(1, -16, 1, 0),
                    Position = UDim2.new(0, 8, 0, 0),
                    BackgroundTransparency = 1,
                    Text = currentText,
                    PlaceholderText = placeholder,
                    PlaceholderColor3 = Royalty.Theme.Muted,
                    TextColor3 = Royalty.Theme.Text,
                    Font = Royalty.Tokens.Font.Regular,
                    TextSize = Royalty.Tokens.TextSize.Description,
                    ClearTextOnFocus = false,
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = BoxHolder
                })
                Royalty:BindThemeProperty(ctrlScope, Box, "TextColor3", "Text")
                Royalty:BindThemeProperty(ctrlScope, Box, "PlaceholderColor3", "Muted")

                function InputObj:Set(newText: string, silent: boolean?)
                    local str = tostring(newText or "")
                    if maxLen and #str > maxLen then
                        str = string.sub(str, 1, maxLen)
                    end
                    if type(validator) == "function" then
                        local ok, valid = safeCall("InputValidator:" .. iName, validator, str)
                        if not ok or valid == false then
                            Royalty:Animate(BoxStroke, Royalty.Tokens.Animation.Fast, { Color = Royalty.Theme.Error })
                            Box.Text = self.Value
                            return
                        end
                    end
                    self.Value = str
                    Royalty.Flags[flag] = str
                    if Box.Text ~= str then
                        Box.Text = str
                    end
                    if not silent then
                        task.spawn(function()
                            safeCall("Input:" .. iName, callback, str)
                        end)
                    end
                end

                function InputObj:Get(): string
                    return self.Value
                end

                ctrlScope:Connect(Box.Focused, function()
                    Royalty:Animate(BoxStroke, Royalty.Tokens.Animation.Fast, { Color = Royalty.Theme.Accent })
                end)

                ctrlScope:Connect(Box:GetPropertyChangedSignal("Text"), function()
                    if maxLen and #Box.Text > maxLen then
                        Box.Text = string.sub(Box.Text, 1, maxLen)
                        return
                    end
                    if callbackOnType and UserInputService:GetFocusedTextBox() == Box then
                        InputObj:Set(Box.Text)
                    end
                end)

                ctrlScope:Connect(Box.FocusLost, function()
                    Royalty:Animate(BoxStroke, Royalty.Tokens.Animation.Fast, { Color = Royalty.Theme.Border })
                    InputObj:Set(Box.Text)
                end)

                return InputObj
            end

            return Section
        end

        return Tab
    end

    -- ========================================================================
    -- 8. ABA DE CONFIGURAÇÕES CONECTADA AO ESTADO REAL DA BIBLIOTECA
    -- ========================================================================
    function Window:AddSettingsTab(tabTitle: string?)
        local SettingsTab = self:AddTab(tabTitle or "Settings")
        local AppearanceSec = SettingsTab:AddSection("Aparência & Tema", "Left")
        local SystemSec = SettingsTab:AddSection("Interface & Perfis", "Right")

        AppearanceSec:AddDropdown({
            Name = "Esquema de Cores",
            Description = "Alterna todas as superfícies e textos da biblioteca.",
            Options = { "Dark", "Light" },
            Default = Royalty.Theme.Name or "Dark",
            Flag = "Royalty_ThemeMode",
            Callback = function(selected)
                Royalty:SetTheme(selected)
            end
        })

        local AccentPicker = AppearanceSec:AddColorPicker({
            Name = "Cor de Destaque (Accent)",
            Default = Royalty.Theme.Accent,
            Flag = "Royalty_AccentColor",
            Callback = function(color)
                Royalty:SetAccentColor(color)
            end
        })

        AppearanceSec:AddDropdown({
            Name = "Predefinições de Destaque",
            Options = { "Royalty Blue", "Emerald", "Amber", "Crimson", "Violet" },
            Default = "Royalty Blue",
            Flag = "Royalty_AccentPreset",
            Callback = function(preset)
                local map = {
                    ["Royalty Blue"] = Color3.fromRGB(94, 129, 244),
                    ["Emerald"] = Color3.fromRGB(52, 199, 123),
                    ["Amber"] = Color3.fromRGB(245, 166, 35),
                    ["Crimson"] = Color3.fromRGB(239, 83, 80),
                    ["Violet"] = Color3.fromRGB(155, 107, 255)
                }
                if map[preset] then
                    AccentPicker:Set(map[preset])
                end
            end
        })

        AppearanceSec:AddToggle({
            Name = "Movimento Reduzido",
            Description = "Desativa animações longas mantendo mudanças de estado imediatas.",
            Default = Royalty.ReducedMotion,
            Flag = "Royalty_ReducedMotion",
            CallOnInit = false,
            Callback = function(state)
                Royalty:SetReducedMotion(state)
            end
        })

        AppearanceSec:AddToggle({
            Name = "Blur de Profundidade",
            Description = "Aplica desfoque no mundo 3D enquanto a janela estiver aberta.",
            Default = self.UseBlur,
            Flag = "Royalty_UseBlur",
            CallOnInit = false,
            Callback = function(state)
                self.UseBlur = state
                Royalty:_syncBlur()
            end
        })

        SystemSec:AddSlider({
            Name = "Escala da Interface",
            Description = "Ajusta o dimensionamento proporcional da janela.",
            Min = 0.80,
            Max = 1.25,
            Default = self.Scale,
            Rounding = 2,
            Suffix = "x",
            Flag = "Royalty_UIScale",
            Callback = function(scaleVal)
                self:SetScale(scaleVal)
            end
        })

        SystemSec:AddKeybind({
            Name = "Tecla de Alternância da UI",
            Default = self.ToggleKey,
            Mode = "Toggle",
            Flag = "Royalty_ToggleKey",
            ChangedCallback = function(newKey)
                self:SetToggleKey(newKey)
            end
        })

        SystemSec:AddToggle({
            Name = "Exibir Notificações",
            Default = Royalty.NotificationsEnabled,
            Flag = "Royalty_NotificationsEnabled",
            CallOnInit = false,
            Callback = function(state)
                Royalty.NotificationsEnabled = state
            end
        })

        SystemSec:AddDivider()

        local profileInput = SystemSec:AddInput({
            Name = "Nome do Perfil",
            Placeholder = "Default",
            Default = "Default",
            MaxLength = 24,
            Flag = "Royalty_ProfileName"
        })

        SystemSec:AddButton({
            Name = "Salvar Configuração Atual",
            Description = Royalty.StorageAdapter and "Grava os controles via StorageAdapter." or "Salva na memória da sessão atual.",
            Callback = function()
                local ok, msg = Royalty:SaveConfiguration(profileInput:Get())
                Royalty:Notify({
                    Title = "Configurações",
                    Content = msg,
                    Type = ok and "Success" or "Error",
                    Duration = 3
                })
            end
        })

        SystemSec:AddButton({
            Name = "Carregar Configuração",
            Callback = function()
                local ok, msg = Royalty:LoadConfiguration(profileInput:Get())
                Royalty:Notify({
                    Title = "Configurações",
                    Content = msg,
                    Type = ok and "Success" or "Warning",
                    Duration = 3
                })
            end
        })

        SystemSec:AddButton({
            Name = "Encerrar Janela (Unload)",
            Callback = function()
                self:Destroy()
            end
        })

        return SettingsTab
    end

    if cfg.AutoAddSettingsTab == true then
        Window:AddSettingsTab()
    end

    return Window
end

function Royalty:Destroy()
    for i = #self.Windows, 1, -1 do
        local win = self.Windows[i]
        if win then
            win:Destroy()
        end
    end
    table.clear(self.Windows)
    table.clear(self._themeListeners)
    self._scope:Destroy()
end

return Royalty
