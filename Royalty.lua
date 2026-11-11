--!strict
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

-- ============================================================================
-- 1. GERENCIADOR DE CICLO DE VIDA (SCOPE)
-- ============================================================================
local Scope = {}
Scope.__index = Scope

function Scope.new()
    return setmetatable({ _tasks = {}, _destroyed = false }, Scope)
end

function Scope:Add(item: any): any
    if self._destroyed then
        Scope._clean(item)
        return item
    end
    table.insert(self._tasks, item)
    return item
end

function Scope:Connect(signal: RBXScriptSignal, fn: (...any) -> ()): RBXScriptConnection
    return self:Add(signal:Connect(fn))
end

function Scope:NewChild(): any
    return self:Add(Scope.new())
end

function Scope._clean(item: any)
    local t = typeof(item)
    if t == "RBXScriptConnection" then
        if item.Connected then item:Disconnect() end
    elseif t == "Instance" then
        pcall(function() item:Destroy() end)
    elseif t == "function" then
        pcall(item)
    elseif t == "thread" then
        pcall(task.cancel, item)
    elseif t == "table" then
        if type(item.Destroy) == "function" then
            pcall(function() item:Destroy() end)
        elseif type(item.Cancel) == "function" then
            pcall(function() item:Cancel() end)
        end
    end
end

function Scope:Clean()
    for i = #self._tasks, 1, -1 do
        local item = self._tasks[i]
        self._tasks[i] = nil
        Scope._clean(item)
    end
end

function Scope:Destroy()
    if self._destroyed then return end
    self._destroyed = true
    self:Clean()
end

-- ============================================================================
-- 2. TOKENS DE DESIGN E TEMAS (GRAFITE NEUTRO + ACENTO PRECISO)
-- ============================================================================
local Royalty = {}
Royalty.__index = Royalty
Royalty.Name = "Royalty"
Royalty.Version = "2.2.0"

Royalty.Themes = {
    Escuro = {
        Name = "Escuro",
        Accent = Color3.fromRGB(88, 124, 244),
        Background = Color3.fromRGB(14, 16, 22),
        Sidebar = Color3.fromRGB(18, 20, 28),
        Surface = Color3.fromRGB(23, 26, 35),
        SurfaceElevated = Color3.fromRGB(30, 34, 46),
        SurfaceHover = Color3.fromRGB(37, 42, 56),
        Border = Color3.fromRGB(48, 54, 72),
        BorderSubtle = Color3.fromRGB(33, 38, 50),
        Text = Color3.fromRGB(244, 246, 250),
        SubText = Color3.fromRGB(178, 184, 200),
        Muted = Color3.fromRGB(120, 128, 146),
        Success = Color3.fromRGB(46, 196, 118),
        Warning = Color3.fromRGB(242, 164, 36),
        Error = Color3.fromRGB(232, 76, 72)
    },
    Claro = {
        Name = "Claro",
        Accent = Color3.fromRGB(52, 94, 224),
        Background = Color3.fromRGB(243, 245, 249),
        Sidebar = Color3.fromRGB(234, 238, 245),
        Surface = Color3.fromRGB(255, 255, 255),
        SurfaceElevated = Color3.fromRGB(239, 242, 248),
        SurfaceHover = Color3.fromRGB(229, 234, 243),
        Border = Color3.fromRGB(204, 211, 224),
        BorderSubtle = Color3.fromRGB(223, 228, 237),
        Text = Color3.fromRGB(20, 24, 33),
        SubText = Color3.fromRGB(72, 80, 96),
        Muted = Color3.fromRGB(126, 134, 152),
        Success = Color3.fromRGB(32, 158, 92),
        Warning = Color3.fromRGB(210, 126, 16),
        Error = Color3.fromRGB(208, 54, 50)
    }
}
Royalty.Themes.Dark = Royalty.Themes.Escuro
Royalty.Themes.Light = Royalty.Themes.Claro

Royalty.Tokens = {
    Corner = {
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
    Anim = {
        Fast = 0.12,
        Normal = 0.18,
        Style = Enum.EasingStyle.Quart,
        Dir = Enum.EasingDirection.Out
    }
}

Royalty._scope = Scope.new()
Royalty.Flags = {}
Royalty.Windows = {}
Royalty.Theme = table.clone(Royalty.Themes.Escuro)
Royalty.ReducedMotion = false
Royalty.NotificationsEnabled = true
Royalty._themeListeners = {}
Royalty._activeTweens = setmetatable({}, { __mode = "k" })
Royalty._memoryStorage = {}
Royalty._registeredKeybinds = {}
Royalty.StorageAdapter = nil

-- ============================================================================
-- 3. FUNÇÕES UTILITÁRIAS E ÍCONES GEOMÉTRICOS (SEM GLIFOS QUEBRADOS)
-- ============================================================================
local function safeCall(label: string, fn: ((...any) -> ...any)?, ...: any): (boolean, ...any)
    if type(fn) ~= "function" then
        return true
    end
    local args = table.pack(...)
    local res = table.pack(xpcall(function()
        return fn(table.unpack(args, 1, args.n))
    end, function(err)
        return debug.traceback(tostring(err), 2)
    end))
    if not res[1] then
        warn(string.format("[Royalty] Erro em '%s':\n%s", label, tostring(res[2])))
        return false, res[2]
    end
    return true, table.unpack(res, 2, res.n)
end

local function resolveParent(customParent: Instance?): Instance
    if typeof(customParent) == "Instance" then return customParent end
    local okHui, hui = pcall(function() return (gethui :: any) and (gethui :: any)() end)
    if okHui and typeof(hui) == "Instance" then return hui end
    local okCore, core = pcall(function() return game:GetService("CoreGui") end)
    if okCore and core then
        local okProbe = pcall(function()
            local f = Instance.new("Folder")
            f.Parent = core
            f:Destroy()
        end)
        if okProbe then return core end
    end
    return LocalPlayer:WaitForChild("PlayerGui")
end

local function create(className: string, props: { [string]: any }?, children: { Instance }?): any
    local inst = Instance.new(className)
    if props then
        for k, v in pairs(props) do
            if k ~= "Parent" then (inst :: any)[k] = v end
        end
    end
    if children then
        for _, ch in ipairs(children) do ch.Parent = inst end
    end
    if props and props.Parent ~= nil then inst.Parent = props.Parent end
    return inst
end

local function createChevronIcon(parent: Instance): (Frame, (isOpen: boolean) -> (), (color: Color3) -> ())
    local holder = create("Frame", {
        Size = UDim2.fromOffset(14, 14),
        Position = UDim2.new(1, -22, 0.5, -7),
        BackgroundTransparency = 1,
        Parent = parent
    })
    local leftBar = create("Frame", {
        Size = UDim2.fromOffset(6, 2),
        Position = UDim2.fromOffset(2, 6),
        AnchorPoint = Vector2.new(0, 0.5),
        Rotation = 40,
        BorderSizePixel = 0,
        Parent = holder
    }, { create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
    local rightBar = create("Frame", {
        Size = UDim2.fromOffset(6, 2),
        Position = UDim2.fromOffset(6, 6),
        AnchorPoint = Vector2.new(0, 0.5),
        Rotation = -40,
        BorderSizePixel = 0,
        Parent = holder
    }, { create("UICorner", { CornerRadius = UDim.new(1, 0) }) })

    local function setOpen(isOpen: boolean)
        Royalty:Animate(leftBar, Royalty.Tokens.Anim.Fast, { Rotation = isOpen and -40 or 40 })
        Royalty:Animate(rightBar, Royalty.Tokens.Anim.Fast, { Rotation = isOpen and 40 or -40 })
    end
    local function setColor(color: Color3)
        leftBar.BackgroundColor3 = color
        rightBar.BackgroundColor3 = color
    end
    return holder, setOpen, setColor
end

local function createCloseIcon(parent: Instance): (TextButton, (color: Color3) -> ())
    local btn = create("TextButton", {
        Size = UDim2.fromOffset(18, 18),
        Position = UDim2.new(1, -18, 0, 0),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        Parent = parent
    })
    local b1 = create("Frame", {
        Size = UDim2.fromOffset(12, 2),
        Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Rotation = 45,
        BorderSizePixel = 0,
        Parent = btn
    }, { create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
    local b2 = create("Frame", {
        Size = UDim2.fromOffset(12, 2),
        Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Rotation = -45,
        BorderSizePixel = 0,
        Parent = btn
    }, { create("UICorner", { CornerRadius = UDim.new(1, 0) }) })

    return btn, function(color: Color3)
        b1.BackgroundColor3 = color
        b2.BackgroundColor3 = color
    end
end

local function formatKeyName(keyEnum: any): string
    if not keyEnum then return "Nenhum" end
    local name = tostring(keyEnum.Name or keyEnum)
    local map = {
        RightShift = "RShift", LeftShift = "LShift",
        RightControl = "RCtrl", LeftControl = "LCtrl",
        RightAlt = "RAlt", LeftAlt = "LAlt",
        MouseButton1 = "MB1", MouseButton2 = "MB2", MouseButton3 = "MB3",
        Backspace = "Back", CapsLock = "Caps", Insert = "Ins",
        Delete = "Del", PageUp = "PgUp", PageDown = "PgDn", Return = "Enter"
    }
    return map[name] or name
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
    local cleaned = string.gsub(string.gsub(hex, "^#", ""), "%s+", "")
    if #cleaned ~= 6 or not string.match(cleaned, "^[0-9a-fA-F]+$") then return nil end
    local r = tonumber(string.sub(cleaned, 1, 2), 16)
    local g = tonumber(string.sub(cleaned, 3, 4), 16)
    local b = tonumber(string.sub(cleaned, 5, 6), 16)
    if not r or not g or not b then return nil end
    return Color3.fromRGB(r, g, b)
end

function Royalty:Animate(instance: Instance, duration: number, props: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween?
    if not instance then return nil end
    local bucket = self._activeTweens[instance]
    if not bucket then
        bucket = {}
        self._activeTweens[instance] = bucket
    end
    for propName in pairs(props) do
        local prev = bucket[propName]
        if prev then
            pcall(function() prev:Cancel() end)
            bucket[propName] = nil
        end
    end

    local actualDuration = self.ReducedMotion and 0 or (duration or self.Tokens.Anim.Normal)
    if actualDuration <= 0 then
        for propName, val in pairs(props) do
            pcall(function() (instance :: any)[propName] = val end)
        end
        return nil
    end

    local tw = TweenService:Create(
        instance,
        TweenInfo.new(actualDuration, style or self.Tokens.Anim.Style, direction or self.Tokens.Anim.Dir),
        props
    )
    for propName in pairs(props) do bucket[propName] = tw end
    tw.Completed:Connect(function()
        if self._activeTweens[instance] then
            for propName in pairs(props) do
                if self._activeTweens[instance][propName] == tw then
                    self._activeTweens[instance][propName] = nil
                end
            end
        end
    end)
    tw:Play()
    return tw
end

function Royalty:OnThemeChanged(scope: any, fn: (theme: { [string]: any }) -> ())
    local entry = { Scope = scope, Callback = fn }
    table.insert(self._themeListeners, entry)
    fn(self.Theme)
    if scope and type(scope.Add) == "function" then
        scope:Add(function()
            local idx = table.find(self._themeListeners, entry)
            if idx then table.remove(self._themeListeners, idx) end
        end)
    end
end

function Royalty:BindThemeProperty(scope: any, instance: Instance, property: string, tokenName: string)
    self:OnThemeChanged(scope, function(theme)
        if instance and instance.Parent ~= nil and theme[tokenName] then
            self:Animate(instance, self.Tokens.Anim.Fast, { [property] = theme[tokenName] })
        end
    end)
    if self.Theme[tokenName] then
        (instance :: any)[property] = self.Theme[tokenName]
    end
end

function Royalty:_notifyThemeListeners()
    for i = #self._themeListeners, 1, -1 do
        local l = self._themeListeners[i]
        if l.Scope and l.Scope._destroyed then
            table.remove(self._themeListeners, i)
        else
            safeCall("ThemeListener", l.Callback, self.Theme)
        end
    end
end

function Royalty:SetTheme(themeNameOrTable: string | { [string]: any })
    local src = type(themeNameOrTable) == "string" and self.Themes[themeNameOrTable] or themeNameOrTable
    if type(src) ~= "table" then return end
    local savedAccent = self.Theme.Accent
    for k, v in pairs(src) do self.Theme[k] = v end
    if type(themeNameOrTable) == "string" and savedAccent then
        self.Theme.Accent = savedAccent
    end
    self:_notifyThemeListeners()
end

function Royalty:SetAccentColor(newColor: Color3)
    if typeof(newColor) ~= "Color3" then return end
    self.Theme.Accent = newColor
    self:_notifyThemeListeners()
end

function Royalty:SetReducedMotion(enabled: boolean)
    self.ReducedMotion = (enabled == true)
    self.Flags["Royalty_ReducedMotion"] = self.ReducedMotion
end

-- ============================================================================
-- 4. PERSISTÊNCIA DE CONFIGURAÇÕES
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
                if (type(tk) == "string" or type(tk) == "number") and (type(tv) == "boolean" or type(tv) == "string" or type(tv) == "number") then
                    copy[tk] = tv
                end
            end
            out[k] = { Type = "table", Value = copy }
        end
    end
    return out
end

function Royalty:SaveConfiguration(profileName: string?): (boolean, string)
    local trimmed = string.gsub(tostring(profileName or ""), "^%s*(.-)%s*$", "%1")
    local key = (trimmed ~= "") and trimmed or "Padrao"
    local payload = self:_serializeFlags()

    if self.StorageAdapter and type(self.StorageAdapter.Save) == "function" then
        local ok, status, err = safeCall("StorageAdapter.Save", self.StorageAdapter.Save, key, payload)
        if not ok or status == false then
            return false, tostring(err or "Falha ao gravar no adaptador.")
        end
        return true, string.format("Perfil '%s' salvo no armazenamento.", key)
    end

    self._memoryStorage[key] = payload
    return true, string.format("Perfil '%s' salvo na memória da sessão.", key)
end

function Royalty:LoadConfiguration(profileName: string?): (boolean, string)
    local trimmed = string.gsub(tostring(profileName or ""), "^%s*(.-)%s*$", "%1")
    local key = (trimmed ~= "") and trimmed or "Padrao"
    local payload = nil

    if self.StorageAdapter and type(self.StorageAdapter.Load) == "function" then
        local ok, status, data = safeCall("StorageAdapter.Load", self.StorageAdapter.Load, key)
        if not ok or status == false or type(data) ~= "table" then
            return false, string.format("Perfil '%s' não encontrado no adaptador.", key)
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
                pcall(function() decoded = (Enum :: any)[entry.EnumType][entry.Name] end)
            end
            if decoded ~= nil then
                self.Flags[flagName] = decoded
                for _, win in ipairs(self.Windows) do
                    if win._controlsByFlag and win._controlsByFlag[flagName] then
                        pcall(function() win._controlsByFlag[flagName]:Set(decoded) end)
                    end
                end
            end
        end
    end

    return true, string.format("Perfil '%s' carregado com sucesso.", key)
end

-- ============================================================================
-- 5. HOST RAIZ, WATERMARK, HOTKEY LIST, TOOLTIP E NOTIFICAÇÕES
-- ============================================================================
function Royalty:_ensureRoot(customParent: Instance?)
    if self._rootGui and self._rootGui.Parent then return self._rootGui end

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

    self._backdropDim = create("Frame", {
        Name = "BackdropDim",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.fromRGB(6, 8, 12),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 1,
        Parent = gui
    })

    self._blurEffect = create("BlurEffect", {
        Name = "RoyaltyDepthBlur",
        Size = 0,
        Enabled = false,
        Parent = Lighting
    })
    self._scope:Add(self._blurEffect)

    -- Watermark Flutuante Discreta
    local wmFrame = create("Frame", {
        Name = "Watermark",
        Size = UDim2.fromOffset(0, 28),
        AutomaticSize = Enum.AutomaticSize.X,
        Position = UDim2.fromOffset(16, 14),
        BackgroundColor3 = self.Theme.Surface,
        Visible = false,
        ZIndex = 80,
        Parent = gui
    }, {
        create("UICorner", { CornerRadius = self.Tokens.Corner.Control }),
        create("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }),
        create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            Padding = UDim.new(0, 8)
        })
    })
    self:BindThemeProperty(self._scope, wmFrame, "BackgroundColor3", "Surface")
    local wmStroke = create("UIStroke", { Color = self.Theme.Border, Thickness = 1, Parent = wmFrame })
    self:BindThemeProperty(self._scope, wmStroke, "Color", "Border")

    local wmDot = create("Frame", {
        Size = UDim2.fromOffset(6, 6),
        BackgroundColor3 = self.Theme.Accent,
        BorderSizePixel = 0,
        Parent = wmFrame
    }, { create("UICorner", { CornerRadius = self.Tokens.Corner.Pill }) })
    self:BindThemeProperty(self._scope, wmDot, "BackgroundColor3", "Accent")

    local wmLabel = create("TextLabel", {
        Size = UDim2.fromOffset(0, 20),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        Text = "Royalty • Unlock Hub",
        TextColor3 = self.Theme.Text,
        Font = self.Tokens.Font.Medium,
        TextSize = self.Tokens.TextSize.Small,
        Parent = wmFrame
    })
    self:BindThemeProperty(self._scope, wmLabel, "TextColor3", "Text")
    self._watermarkFrame = wmFrame
    self._watermarkLabel = wmLabel

    -- Painel Flutuante de Hotkeys Ativas (Keybind List)
    local hkFrame = create("Frame", {
        Name = "HotkeyList",
        Size = UDim2.fromOffset(190, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Position = UDim2.new(0, 16, 0.5, -60),
        BackgroundColor3 = self.Theme.Surface,
        Visible = false,
        ZIndex = 80,
        Parent = gui
    }, {
        create("UICorner", { CornerRadius = self.Tokens.Corner.Section }),
        create("UIPadding", {
            PaddingTop = UDim.new(0, 8),
            PaddingBottom = UDim.new(0, 8),
            PaddingLeft = UDim.new(0, 10),
            PaddingRight = UDim.new(0, 10)
        }),
        create("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 4)
        })
    })
    self:BindThemeProperty(self._scope, hkFrame, "BackgroundColor3", "Surface")
    local hkStroke = create("UIStroke", { Color = self.Theme.Border, Thickness = 1, Parent = hkFrame })
    self:BindThemeProperty(self._scope, hkStroke, "Color", "Border")

    local hkTitle = create("TextLabel", {
        LayoutOrder = 0,
        Size = UDim2.new(1, 0, 0, 16),
        BackgroundTransparency = 1,
        Text = "Atalhos Ativos",
        TextColor3 = self.Theme.Text,
        Font = self.Tokens.Font.Bold,
        TextSize = self.Tokens.TextSize.Small,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = hkFrame
    })
    self:BindThemeProperty(self._scope, hkTitle, "TextColor3", "Text")

    local hkItemsHolder = create("Frame", {
        LayoutOrder = 1,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Parent = hkFrame
    }, {
        create("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 3)
        })
    })
    self._hotkeyFrame = hkFrame
    self._hotkeyItemsHolder = hkItemsHolder

    -- Tooltip Flutuante Único
    local tooltipFrame = create("Frame", {
        Name = "Tooltip",
        Size = UDim2.fromOffset(0, 24),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = self.Theme.SurfaceElevated,
        Visible = false,
        ZIndex = 120,
        Parent = gui
    }, {
        create("UICorner", { CornerRadius = UDim.new(0, 5) }),
        create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) })
    })
    self:BindThemeProperty(self._scope, tooltipFrame, "BackgroundColor3", "SurfaceElevated")
    local ttStroke = create("UIStroke", { Color = self.Theme.Border, Thickness = 1, Parent = tooltipFrame })
    self:BindThemeProperty(self._scope, ttStroke, "Color", "Border")
    local ttText = create("TextLabel", {
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        Text = "",
        TextColor3 = self.Theme.Text,
        Font = self.Tokens.Font.Regular,
        TextSize = self.Tokens.TextSize.Small,
        Parent = tooltipFrame
    })
    self:BindThemeProperty(self._scope, ttText, "TextColor3", "Text")
    self._tooltipFrame = tooltipFrame
    self._tooltipText = ttText

    -- Pilha de Notificações
    self._notifHolder = create("Frame", {
        Name = "NotificationStack",
        Size = UDim2.new(0, 290, 1, -32),
        Position = UDim2.new(1, -306, 0, 16),
        BackgroundTransparency = 1,
        ZIndex = 110,
        Parent = gui
    }, {
        create("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            VerticalAlignment = Enum.VerticalAlignment.Bottom,
            HorizontalAlignment = Enum.HorizontalAlignment.Right,
            Padding = UDim.new(0, 8)
        })
    })

    return gui
end

function Royalty:SetWatermarkVisible(visible: boolean, customText: string?)
    self:_ensureRoot()
    if customText then
        self._watermarkLabel.Text = customText
    end
    self._watermarkFrame.Visible = (visible == true)
end

function Royalty:SetHotkeyListVisible(visible: boolean)
    self:_ensureRoot()
    self._hotkeyFrame.Visible = (visible == true)
    self:_refreshHotkeyList()
end

function Royalty:_refreshHotkeyList()
    if not self._hotkeyItemsHolder then return end
    for _, ch in ipairs(self._hotkeyItemsHolder:GetChildren()) do
        if not ch:IsA("UIListLayout") then ch:Destroy() end
    end
    local count = 0
    for _, kb in ipairs(self._registeredKeybinds) do
        if kb.Key then
            count += 1
            local row = create("Frame", {
                LayoutOrder = count,
                Size = UDim2.new(1, 0, 0, 18),
                BackgroundTransparency = 1,
                Parent = self._hotkeyItemsHolder
            })
            create("TextLabel", {
                Size = UDim2.new(1, -60, 1, 0),
                BackgroundTransparency = 1,
                Text = kb.Name,
                TextColor3 = kb.Active and self.Theme.Accent or self.Theme.SubText,
                Font = kb.Active and self.Tokens.Font.Semibold or self.Tokens.Font.Regular,
                TextSize = self.Tokens.TextSize.Small,
                TextTruncate = Enum.TextTruncate.AtEnd,
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = row
            })
            create("TextLabel", {
                Size = UDim2.fromOffset(56, 18),
                Position = UDim2.new(1, -56, 0, 0),
                BackgroundTransparency = 1,
                Text = "[" .. formatKeyName(kb.Key) .. "]",
                TextColor3 = kb.Active and self.Theme.Text or self.Theme.Muted,
                Font = self.Tokens.Font.Mono,
                TextSize = 10,
                TextXAlignment = Enum.TextXAlignment.Right,
                Parent = row
            })
        end
    end
end

function Royalty:AttachTooltip(scope: any, target: GuiObject, text: string?)
    if not text or text == "" then return end
    scope:Connect(target.MouseEnter, function()
        if not self._tooltipFrame then return end
        self._tooltipText.Text = text
        local mPos = UserInputService:GetMouseLocation()
        self._tooltipFrame.Position = UDim2.fromOffset(mPos.X + 14, mPos.Y + 12)
        self._tooltipFrame.Visible = true
    end)
    scope:Connect(target.MouseMoved, function(x, y)
        if self._tooltipFrame and self._tooltipFrame.Visible then
            self._tooltipFrame.Position = UDim2.fromOffset(x + 14, y + 12)
        end
    end)
    scope:Connect(target.MouseLeave, function()
        if self._tooltipFrame then
            self._tooltipFrame.Visible = false
        end
    end)
end

function Royalty:_syncBlur()
    local shouldBlur = false
    for _, win in ipairs(self.Windows) do
        if not win._destroyed and win.Visible and win.UseBlur then
            shouldBlur = true
            break
        end
    end

    if self._blurEffect and self._blurEffect.Parent then
        if shouldBlur then
            self._blurEffect.Enabled = true
            self:Animate(self._blurEffect, self.Tokens.Anim.Normal, { Size = 12 })
        else
            local tw = self:Animate(self._blurEffect, self.Tokens.Anim.Fast, { Size = 0 })
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

    if self._backdropDim and self._backdropDim.Parent then
        if shouldBlur then
            self._backdropDim.Visible = true
            self:Animate(self._backdropDim, self.Tokens.Anim.Normal, { BackgroundTransparency = 0.42 })
        else
            local twDim = self:Animate(self._backdropDim, self.Tokens.Anim.Fast, { BackgroundTransparency = 1 })
            if twDim then
                twDim.Completed:Once(function()
                    if self._backdropDim and self._backdropDim.BackgroundTransparency >= 0.98 then
                        self._backdropDim.Visible = false
                    end
                end)
            else
                self._backdropDim.Visible = false
            end
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
    if nType == "success" or nType == "sucesso" then typeToken = "Success"
    elseif nType == "warning" or nType == "aviso" then typeToken = "Warning"
    elseif nType == "error" or nType == "erro" then typeToken = "Error" end

    local wrapper = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Parent = self._notifHolder
    })
    notifScope:Add(wrapper)

    local card = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Position = UDim2.fromOffset(20, 0),
        BackgroundColor3 = self.Theme.Surface,
        BackgroundTransparency = 1,
        ClipsDescendants = true,
        Parent = wrapper
    }, { create("UICorner", { CornerRadius = self.Tokens.Corner.Section }) })
    self:BindThemeProperty(notifScope, card, "BackgroundColor3", "Surface")

    local stroke = create("UIStroke", { Color = self.Theme.Border, Thickness = 1, Transparency = 1, Parent = card })
    self:BindThemeProperty(notifScope, stroke, "Color", "Border")

    local pad = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Parent = card
    }, {
        create("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 12), PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }),
        create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) })
    })

    local topRow = create("Frame", { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Parent = pad })
    local dot = create("Frame", {
        Size = UDim2.fromOffset(8, 8),
        Position = UDim2.new(0, 2, 0.5, -4),
        BackgroundColor3 = self.Theme[typeToken],
        BorderSizePixel = 0,
        Parent = topRow
    }, { create("UICorner", { CornerRadius = self.Tokens.Corner.Pill }) })
    self:BindThemeProperty(notifScope, dot, "BackgroundColor3", typeToken)

    local titleLbl = create("TextLabel", {
        Size = UDim2.new(1, -38, 1, 0),
        Position = UDim2.fromOffset(16, 0),
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

    local closeBtn, setCloseColor = createCloseIcon(topRow)
    self:OnThemeChanged(notifScope, function(th) setCloseColor(th.Muted) end)

    if contentText ~= "" then
        local bodyLbl = create("TextLabel", {
            LayoutOrder = 2,
            Size = UDim2.new(1, -16, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            Position = UDim2.fromOffset(16, 0),
            BackgroundTransparency = 1,
            Text = contentText,
            TextColor3 = self.Theme.SubText,
            Font = self.Tokens.Font.Regular,
            TextSize = self.Tokens.TextSize.Description,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = pad
        })
        self:BindThemeProperty(notifScope, bodyLbl, "TextColor3", "SubText")
    end

    local pTrack = create("Frame", {
        Size = UDim2.new(1, 0, 0, 2),
        Position = UDim2.new(0, 0, 1, -2),
        BackgroundColor3 = self.Theme.BorderSubtle,
        BorderSizePixel = 0,
        Parent = card
    })
    local pFill = create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = self.Theme[typeToken],
        BorderSizePixel = 0,
        Parent = pTrack
    })
    self:BindThemeProperty(notifScope, pFill, "BackgroundColor3", typeToken)

    self:Animate(card, self.Tokens.Anim.Normal, { Position = UDim2.fromOffset(0, 0), BackgroundTransparency = 0 })
    self:Animate(stroke, self.Tokens.Anim.Normal, { Transparency = 0 })

    if not self.ReducedMotion then
        TweenService:Create(pFill, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(0, 1) }):Play()
    end

    local function dismiss()
        if dismissed then return end
        dismissed = true
        local tw = self:Animate(card, self.Tokens.Anim.Fast, { Position = UDim2.fromOffset(20, 0), BackgroundTransparency = 1 })
        self:Animate(stroke, self.Tokens.Anim.Fast, { Transparency = 1 })
        if tw then tw.Completed:Once(function() notifScope:Destroy() end) else notifScope:Destroy() end
    end

    notifScope:Connect(closeBtn.Activated, dismiss)
    notifScope:Add(task.delay(duration, dismiss))
    return { Dismiss = dismiss }
end

-- ============================================================================
-- 6. CRIAÇÃO DE JANELA (DESKTOP + MOBILE RESPONSIVO + POPOVER DE CONFIRMAÇÃO)
-- ============================================================================
function Royalty:CreateWindow(cfg: { [string]: any }?)
    cfg = cfg or {}
    self:_ensureRoot(cfg.Parent)

    if cfg.Theme then self:SetTheme(cfg.Theme) end
    if typeof(cfg.Accent) == "Color3" then self:SetAccentColor(cfg.Accent) end
    if cfg.ReducedMotion ~= nil then self:SetReducedMotion(cfg.ReducedMotion == true) end

    local winScope = self._scope:NewChild()
    local titleText = tostring(cfg.Title or "Royalty")
    local subTitleText = tostring(cfg.SubTitle or "Unlock Hub")
    local desktopSize: UDim2 = typeof(cfg.Size) == "UDim2" and cfg.Size or UDim2.fromOffset(650, 440)
    local toggleKey = cfg.ToggleKey or Enum.KeyCode.RightShift
    local useBlur = (cfg.Blur == true)
    local uiScaleValue = math.clamp(tonumber(cfg.Scale) or 1, 0.75, 1.35)
    local initialLayoutMode = tostring(cfg.LayoutMode or "Desktop")

    local Window = {
        Title = titleText,
        SubTitle = subTitleText,
        Tabs = {},
        ActiveTab = nil,
        Visible = true,
        ToggleKey = toggleKey,
        UseBlur = useBlur,
        Scale = uiScaleValue,
        LayoutMode = initialLayoutMode,
        _scope = winScope,
        _destroyed = false,
        _transitionId = 0,
        _controlsByFlag = {},
        _isBindingKey = false
    }
    table.insert(self.Windows, Window)

    local function computeBounds(mode: string): (UDim2, UDim2)
        local cam = workspace.CurrentCamera
        local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
        if mode == "Mobile" then
            local w = math.clamp(math.floor(vp.X * 0.92), 340, 460)
            local h = math.clamp(math.floor(vp.Y * 0.84), 320, 520)
            return UDim2.fromOffset(w, h), UDim2.fromOffset(math.floor((vp.X - w) * 0.5), math.floor((vp.Y - h) * 0.5))
        end
        local w = desktopSize.X.Scale * vp.X + desktopSize.X.Offset
        local h = desktopSize.Y.Scale * vp.Y + desktopSize.Y.Offset
        w = math.clamp(w, 420, math.max(440, vp.X - 32))
        h = math.clamp(h, 300, math.max(320, vp.Y - 48))
        return UDim2.fromOffset(math.floor(w), math.floor(h)), UDim2.fromOffset(math.floor((vp.X - w) * 0.5), math.floor((vp.Y - h) * 0.5))
    end

    local initSize, initPos = computeBounds(initialLayoutMode)

    local Main = create("CanvasGroup", {
        Name = "RoyaltyWindow_" .. titleText,
        Size = initSize,
        Position = initPos,
        BackgroundColor3 = self.Theme.Background,
        GroupTransparency = 1,
        ClipsDescendants = true,
        ZIndex = 10,
        Parent = self._rootGui
    }, { create("UICorner", { CornerRadius = self.Tokens.Corner.Window }) })
    winScope:Add(Main)
    self:BindThemeProperty(winScope, Main, "BackgroundColor3", "Background")

    local WinScale = create("UIScale", {
        Scale = self.ReducedMotion and uiScaleValue or (uiScaleValue * 0.96),
        Parent = Main
    })

    local MainStroke = create("UIStroke", { Color = self.Theme.Border, Thickness = 1, Parent = Main })
    self:BindThemeProperty(winScope, MainStroke, "Color", "Border")

    -- Sidebar Desktop
    local Sidebar = create("Frame", {
        Name = "Sidebar",
        Size = UDim2.new(0, 168, 1, 0),
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

    local BrandHeader = create("Frame", {
        Size = UDim2.new(1, 0, 0, 56),
        BackgroundTransparency = 1,
        Parent = Sidebar
    })

    local BrandBar = create("Frame", {
        Size = UDim2.fromOffset(6, 20),
        Position = UDim2.fromOffset(14, 18),
        BackgroundColor3 = self.Theme.Accent,
        BorderSizePixel = 0,
        Parent = BrandHeader
    }, { create("UICorner", { CornerRadius = self.Tokens.Corner.Pill }) })
    self:BindThemeProperty(winScope, BrandBar, "BackgroundColor3", "Accent")

    local WinTitleLbl = create("TextLabel", {
        Size = UDim2.new(1, -36, 0, 20),
        Position = UDim2.fromOffset(28, 12),
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
        Size = UDim2.new(1, -36, 0, 14),
        Position = UDim2.fromOffset(28, 32),
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
        Size = UDim2.new(1, -16, 1, -98),
        Position = UDim2.fromOffset(8, 58),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = self.Theme.Border,
        CanvasSize = UDim2.fromOffset(0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Parent = Sidebar
    })
    local TabListLayout = create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        FillDirection = Enum.FillDirection.Vertical,
        Padding = UDim.new(0, 4),
        Parent = TabList
    })
    self:BindThemeProperty(winScope, TabList, "ScrollBarImageColor3", "Border")

    local FooterFrame = create("Frame", {
        Size = UDim2.new(1, 0, 0, 36),
        Position = UDim2.new(0, 0, 1, -36),
        BackgroundTransparency = 1,
        Parent = Sidebar
    })
    local FooterDiv = create("Frame", {
        Size = UDim2.new(1, -24, 0, 1),
        Position = UDim2.fromOffset(12, 0),
        BackgroundColor3 = self.Theme.BorderSubtle,
        BorderSizePixel = 0,
        Parent = FooterFrame
    })
    self:BindThemeProperty(winScope, FooterDiv, "BackgroundColor3", "BorderSubtle")

    local FooterKeyLabel = create("TextLabel", {
        Size = UDim2.new(1, -24, 1, -2),
        Position = UDim2.fromOffset(12, 2),
        BackgroundTransparency = 1,
        Text = "Menu: [" .. formatKeyName(toggleKey) .. "]",
        TextColor3 = self.Theme.Muted,
        Font = self.Tokens.Font.Medium,
        TextSize = self.Tokens.TextSize.Small,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = FooterFrame
    })
    self:BindThemeProperty(winScope, FooterKeyLabel, "TextColor3", "Muted")

    -- Área Principal de Conteúdo
    local ContentArea = create("Frame", {
        Name = "ContentArea",
        Size = UDim2.new(1, -168, 1, 0),
        Position = UDim2.fromOffset(168, 0),
        BackgroundTransparency = 1,
        Parent = Main
    })

    local TopHeaderBar = create("Frame", {
        Name = "TopHeaderBar",
        Size = UDim2.new(1, 0, 0, 50),
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
        Size = UDim2.new(1, -265, 1, 0),
        Position = UDim2.fromOffset(18, 0),
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

    -- Botão de Alternar Layout Desktop/Mobile no Topo
    local ModeSwitchBtn = create("TextButton", {
        Size = UDim2.fromOffset(68, 28),
        Position = UDim2.new(1, -252, 0.5, -14),
        BackgroundColor3 = self.Theme.Surface,
        AutoButtonColor = false,
        Text = initialLayoutMode == "Mobile" and "Mobile" or "Desktop",
        TextColor3 = self.Theme.SubText,
        Font = self.Tokens.Font.Medium,
        TextSize = self.Tokens.TextSize.Small,
        Parent = TopHeaderBar
    }, {
        create("UICorner", { CornerRadius = self.Tokens.Corner.Control })
    })
    self:BindThemeProperty(winScope, ModeSwitchBtn, "BackgroundColor3", "Surface")
    self:BindThemeProperty(winScope, ModeSwitchBtn, "TextColor3", "SubText")
    local ModeSwitchStroke = create("UIStroke", { Color = self.Theme.BorderSubtle, Thickness = 1, Parent = ModeSwitchBtn })
    self:BindThemeProperty(winScope, ModeSwitchStroke, "Color", "BorderSubtle")
    self:AttachTooltip(winScope, ModeSwitchBtn, "Alternar entre visualização Desktop e Mobile")

    local SearchContainer = create("Frame", {
        Size = UDim2.fromOffset(162, 28),
        Position = UDim2.new(1, -176, 0.5, -14),
        BackgroundColor3 = self.Theme.Surface,
        Parent = TopHeaderBar
    }, { create("UICorner", { CornerRadius = self.Tokens.Corner.Control }) })
    self:BindThemeProperty(winScope, SearchContainer, "BackgroundColor3", "Surface")
    local SearchStroke = create("UIStroke", { Color = self.Theme.BorderSubtle, Thickness = 1, Parent = SearchContainer })
    self:BindThemeProperty(winScope, SearchStroke, "Color", "BorderSubtle")

    local SearchBox = create("TextBox", {
        Size = UDim2.new(1, -16, 1, 0),
        Position = UDim2.fromOffset(8, 0),
        BackgroundTransparency = 1,
        Text = "",
        PlaceholderText = "Buscar...",
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
        Size = UDim2.new(1, 0, 1, -50),
        Position = UDim2.fromOffset(0, 50),
        BackgroundTransparency = 1,
        ClipsDescendants = true,
        Parent = ContentArea
    })

    local EmptySearchBanner = create("TextLabel", {
        Size = UDim2.new(1, -36, 0, 40),
        Position = UDim2.fromOffset(18, 24),
        BackgroundTransparency = 1,
        Visible = false,
        Text = "Nenhum controle encontrado para esta busca.",
        TextColor3 = self.Theme.Muted,
        Font = self.Tokens.Font.Medium,
        TextSize = self.Tokens.TextSize.Control,
        Parent = PagesHolder
    })
    self:BindThemeProperty(winScope, EmptySearchBanner, "TextColor3", "Muted")

    -- Camada de Popover / Confirmação Interna da Janela
    local ModalOverlay = create("TextButton", {
        Name = "ModalOverlay",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.fromRGB(6, 8, 12),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        Visible = false,
        ZIndex = 40,
        Parent = Main
    })

    -- ========================================================================
    -- MÉTODO DE CONFIRMAÇÃO / POPOVER DENTRO DA JANELA
    -- ========================================================================
    function Window:Confirm(cCfg: { Title: string?, Content: string?, ConfirmText: string?, CancelText: string?, Destructive: boolean?, OnConfirm: (() -> ())?, OnCancel: (() -> ())? })
        cCfg = cCfg or {}
        for _, ch in ipairs(ModalOverlay:GetChildren()) do ch:Destroy() end

        ModalOverlay.Visible = true
        ModalOverlay.BackgroundTransparency = 1
        Royalty:Animate(ModalOverlay, Royalty.Tokens.Anim.Fast, { BackgroundTransparency = 0.45 })

        local dialog = create("Frame", {
            Size = UDim2.fromOffset(310, 150),
            Position = UDim2.fromScale(0.5, 0.5),
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundColor3 = Royalty.Theme.Surface,
            ZIndex = 41,
            Parent = ModalOverlay
        }, {
            create("UICorner", { CornerRadius = Royalty.Tokens.Corner.Section }),
            create("UIStroke", { Color = Royalty.Theme.Border, Thickness = 1 }),
            create("UIPadding", { PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 14), PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) })
        })

        create("TextLabel", {
            Size = UDim2.new(1, 0, 0, 20),
            BackgroundTransparency = 1,
            ZIndex = 42,
            Text = tostring(cCfg.Title or "Confirmar Ação"),
            TextColor3 = Royalty.Theme.Text,
            Font = Royalty.Tokens.Font.Bold,
            TextSize = 14,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = dialog
        })

        create("TextLabel", {
            Size = UDim2.new(1, 0, 0, 54),
            Position = UDim2.fromOffset(0, 26),
            BackgroundTransparency = 1,
            ZIndex = 42,
            Text = tostring(cCfg.Content or "Deseja prosseguir com esta operação?"),
            TextColor3 = Royalty.Theme.SubText,
            Font = Royalty.Tokens.Font.Regular,
            TextSize = Royalty.Tokens.TextSize.Description,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            Parent = dialog
        })

        local cancelBtn = create("TextButton", {
            Size = UDim2.new(0.48, 0, 0, 32),
            Position = UDim2.new(0, 0, 1, -32),
            BackgroundColor3 = Royalty.Theme.SurfaceElevated,
            AutoButtonColor = false,
            ZIndex = 42,
            Text = tostring(cCfg.CancelText or "Cancelar"),
            TextColor3 = Royalty.Theme.Text,
            Font = Royalty.Tokens.Font.Medium,
            TextSize = Royalty.Tokens.TextSize.Description,
            Parent = dialog
        }, {
            create("UICorner", { CornerRadius = Royalty.Tokens.Corner.Control }),
            create("UIStroke", { Color = Royalty.Theme.Border, Thickness = 1 })
        })

        local confirmBtn = create("TextButton", {
            Size = UDim2.new(0.48, 0, 0, 32),
            Position = UDim2.new(0.52, 0, 1, -32),
            BackgroundColor3 = (cCfg.Destructive ~= false) and Royalty.Theme.Error or Royalty.Theme.Accent,
            AutoButtonColor = false,
            ZIndex = 42,
            Text = tostring(cCfg.ConfirmText or "Confirmar"),
            TextColor3 = Color3.fromRGB(255, 255, 255),
            Font = Royalty.Tokens.Font.Semibold,
            TextSize = Royalty.Tokens.TextSize.Description,
            Parent = dialog
        }, {
            create("UICorner", { CornerRadius = Royalty.Tokens.Corner.Control })
        })

        local function closeModal()
            local tw = Royalty:Animate(ModalOverlay, Royalty.Tokens.Anim.Fast, { BackgroundTransparency = 1 })
            if tw then
                tw.Completed:Once(function() ModalOverlay.Visible = false end)
            else
                ModalOverlay.Visible = false
            end
        end

        cancelBtn.Activated:Connect(function()
            closeModal()
            if cCfg.OnCancel then task.spawn(cCfg.OnCancel) end
        end)
        confirmBtn.Activated:Connect(function()
            closeModal()
            if cCfg.OnConfirm then task.spawn(cCfg.OnConfirm) end
        end)
    end

    -- ========================================================================
    -- ALTERNÂNCIA DE LAYOUT DESKTOP <-> MOBILE REAL
    -- ========================================================================
    function Window:SetLayoutMode(mode: string)
        local isMobile = (string.lower(tostring(mode)) == "mobile")
        self.LayoutMode = isMobile and "Mobile" or "Desktop"
        ModeSwitchBtn.Text = self.LayoutMode
        Royalty.Flags["Royalty_LayoutMode"] = self.LayoutMode

        local newSize, newPos = computeBounds(self.LayoutMode)
        Royalty:Animate(Main, Royalty.Tokens.Anim.Normal, { Size = newSize, Position = newPos })

        if isMobile then
            -- Reorganiza a Sidebar para virar uma barra superior compacta com abas horizontais
            Sidebar.Size = UDim2.new(1, 0, 0, 86)
            SidebarDivider.Size = UDim2.new(1, 0, 0, 1)
            SidebarDivider.Position = UDim2.new(0, 0, 1, -1)
            BrandHeader.Size = UDim2.new(1, 0, 0, 42)
            WinSubLbl.Visible = false
            FooterFrame.Visible = false

            TabList.Size = UDim2.new(1, -16, 0, 38)
            TabList.Position = UDim2.fromOffset(8, 44)
            TabList.ScrollingDirection = Enum.ScrollingDirection.X
            TabList.AutomaticCanvasSize = Enum.AutomaticSize.X
            TabListLayout.FillDirection = Enum.FillDirection.Horizontal

            for _, t in ipairs(self.Tabs) do
                t.Btn.Size = UDim2.fromOffset(112, 32)
            end

            ContentArea.Size = UDim2.new(1, 0, 1, -86)
            ContentArea.Position = UDim2.fromOffset(0, 86)
        else
            Sidebar.Size = UDim2.new(0, 168, 1, 0)
            SidebarDivider.Size = UDim2.new(0, 1, 1, 0)
            SidebarDivider.Position = UDim2.new(1, -1, 0, 0)
            BrandHeader.Size = UDim2.new(1, 0, 0, 56)
            WinSubLbl.Visible = true
            FooterFrame.Visible = true

            TabList.Size = UDim2.new(1, -16, 1, -98)
            TabList.Position = UDim2.fromOffset(8, 58)
            TabList.ScrollingDirection = Enum.ScrollingDirection.Y
            TabList.AutomaticCanvasSize = Enum.AutomaticSize.Y
            TabListLayout.FillDirection = Enum.FillDirection.Vertical

            for _, t in ipairs(self.Tabs) do
                t.Btn.Size = UDim2.new(1, 0, 0, 34)
            end

            ContentArea.Size = UDim2.new(1, -168, 1, 0)
            ContentArea.Position = UDim2.fromOffset(168, 0)
        end

        task.delay(0.2, function()
            if self.ActiveTab then
                self.ActiveTab:_updateColumns()
            end
        end)
    end

    winScope:Connect(ModeSwitchBtn.Activated, function()
        Window:SetLayoutMode(Window.LayoutMode == "Desktop" and "Mobile" or "Desktop")
    end)

    -- Arrasto da Janela
    local dragging = false
    local dragInput = nil
    local dragStartPos = Vector2.zero
    local windowStartPos = initPos

    local function beginDrag(input: InputObject)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            if UserInputService:GetFocusedTextBox() == SearchBox then return end
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
            local minX = -math.floor(absSize.X * 0.6)
            local maxX = math.floor(vp.X - absSize.X * 0.4)
            local minY = 0
            local maxY = math.floor(vp.Y - 48)

            Main.Position = UDim2.fromOffset(
                math.clamp(windowStartPos.X.Offset + delta.X, minX, maxX),
                math.clamp(windowStartPos.Y.Offset + delta.Y, minY, maxY)
            )
        end
    end)

    winScope:Connect(UserInputService.InputEnded, function(input)
        if input == dragInput or input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
            dragInput = nil
        end
    end)

    -- Busca em Tempo Real
    local function applySearchFilter()
        local activeTab = Window.ActiveTab
        if not activeTab then return end
        local query = string.lower(string.gsub(SearchBox.Text, "^%s*(.-)%s*$", "%1"))

        if query == "" then
            EmptySearchBanner.Visible = false
            for _, sec in ipairs(activeTab.Sections) do
                sec.Frame.Visible = true
                for _, item in ipairs(sec.Items) do item.Instance.Visible = true end
                sec:_updateHeight()
            end
            activeTab:_updateColumns()
            return
        end

        local anyMatch = false
        for _, sec in ipairs(activeTab.Sections) do
            local secMatches = string.find(string.lower(sec.Name), query, 1, true) ~= nil
            local itemMatches = false
            for _, item in ipairs(sec.Items) do
                if secMatches then
                    item.Instance.Visible = true
                    itemMatches = true
                else
                    local m = string.find(string.lower(item.SearchText), query, 1, true) ~= nil
                    item.Instance.Visible = m
                    if m then itemMatches = true end
                end
            end
            sec.Frame.Visible = secMatches or itemMatches
            sec:_updateHeight()
            if sec.Frame.Visible then anyMatch = true end
        end

        EmptySearchBanner.Visible = not anyMatch
        activeTab:_updateColumns()
    end

    winScope:Connect(SearchBox:GetPropertyChangedSignal("Text"), applySearchFilter)

    function Window:SetScale(newScale: number)
        self.Scale = math.clamp(tonumber(newScale) or 1, 0.75, 1.35)
        Royalty.Flags["Royalty_UIScale"] = self.Scale
        if self.Visible then
            Royalty:Animate(WinScale, Royalty.Tokens.Anim.Fast, { Scale = self.Scale })
        end
        if self.ActiveTab then
            task.defer(function()
                if self.ActiveTab then self.ActiveTab:_updateColumns() end
            end)
        end
    end

    function Window:SetToggleKey(newKey: Enum.KeyCode?)
        self.ToggleKey = newKey
        FooterKeyLabel.Text = "Menu: [" .. formatKeyName(newKey) .. "]"
        Royalty.Flags["Royalty_ToggleKey"] = newKey
    end

    function Window:Toggle(forcedState: boolean?)
        if self._destroyed then return end
        local targetState: boolean
        if forcedState ~= nil then
            targetState = (forcedState == true)
        else
            targetState = not self.Visible
        end

        if self.Visible == targetState and self._transitionId > 0 then return end
        self.Visible = targetState
        self._transitionId += 1
        local currentId = self._transitionId

        Royalty:_syncBlur()

        if targetState then
            Main.Visible = true
            if Royalty.ReducedMotion then
                Main.GroupTransparency = 0
                WinScale.Scale = self.Scale
            else
                WinScale.Scale = self.Scale * 0.96
                Royalty:Animate(Main, Royalty.Tokens.Anim.Normal, { GroupTransparency = 0 })
                Royalty:Animate(WinScale, Royalty.Tokens.Anim.Normal, { Scale = self.Scale })
            end
        else
            if Royalty.ReducedMotion then
                Main.GroupTransparency = 1
                Main.Visible = false
            else
                local fadeOut = Royalty:Animate(Main, Royalty.Tokens.Anim.Fast, { GroupTransparency = 1 })
                Royalty:Animate(WinScale, Royalty.Tokens.Anim.Fast, { Scale = self.Scale * 0.96 })
                if fadeOut then
                    fadeOut.Completed:Once(function()
                        if self._transitionId == currentId and not self.Visible and Main and Main.Parent then
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
        if idx then table.remove(Royalty.Windows, idx) end
        Royalty:_syncBlur()
        self._scope:Destroy()
    end

    winScope:Connect(UserInputService.InputBegan, function(input, gp)
        if gp or UserInputService:GetFocusedTextBox() ~= nil or Window._isBindingKey then return end
        if input.KeyCode == Enum.KeyCode.Escape and ModalOverlay.Visible then
            ModalOverlay.Visible = false
            return
        end
        if Window.ToggleKey and input.KeyCode == Window.ToggleKey then
            Window:Toggle()
        end
    end)

    -- Tela de Carregamento Opcional
    local initTasks = cfg.InitTasks
    local showLoading = (cfg.LoadingScreen ~= false) and (type(initTasks) == "table" and #initTasks > 0)
    if showLoading then
        local LoadingOverlay = create("Frame", {
            Size = UDim2.fromScale(1, 1),
            BackgroundColor3 = self.Theme.Background,
            ZIndex = 50,
            Active = true,
            Parent = Main
        })
        self:BindThemeProperty(winScope, LoadingOverlay, "BackgroundColor3", "Background")

        create("TextLabel", {
            Size = UDim2.new(1, -48, 0, 24),
            Position = UDim2.new(0, 24, 0.5, -48),
            BackgroundTransparency = 1,
            ZIndex = 51,
            Text = titleText,
            TextColor3 = self.Theme.Text,
            Font = self.Tokens.Font.Bold,
            TextSize = 18,
            Parent = LoadingOverlay
        })

        local LoadStatus = create("TextLabel", {
            Size = UDim2.new(1, -48, 0, 18),
            Position = UDim2.new(0, 24, 0.5, -20),
            BackgroundTransparency = 1,
            ZIndex = 51,
            Text = "Inicializando...",
            TextColor3 = self.Theme.SubText,
            Font = self.Tokens.Font.Regular,
            TextSize = self.Tokens.TextSize.Description,
            Parent = LoadingOverlay
        })

        local BarTrack = create("Frame", {
            Size = UDim2.fromOffset(240, 5),
            Position = UDim2.new(0.5, -120, 0.5, 8),
            BackgroundColor3 = self.Theme.SurfaceElevated,
            BorderSizePixel = 0,
            ZIndex = 51,
            ClipsDescendants = true,
            Parent = LoadingOverlay
        }, { create("UICorner", { CornerRadius = self.Tokens.Corner.Pill }) })

        local BarFill = create("Frame", {
            Size = UDim2.fromScale(0, 1),
            BackgroundColor3 = self.Theme.Accent,
            BorderSizePixel = 0,
            ZIndex = 52,
            Parent = BarTrack
        }, { create("UICorner", { CornerRadius = self.Tokens.Corner.Pill }) })

        winScope:Add(task.spawn(function()
            local total = #initTasks
            for idx, entry in ipairs(initTasks) do
                if Window._destroyed then return end
                local tName = type(entry) == "table" and tostring(entry.Name or ("Etapa " .. idx)) or ("Etapa " .. idx)
                local tFn = type(entry) == "table" and entry.Task or entry
                LoadStatus.Text = string.format("%s (%d/%d)", tName, idx, total)
                safeCall("InitTask", tFn)
                self:Animate(BarFill, self.Tokens.Anim.Fast, { Size = UDim2.fromScale(idx / total, 1) })
            end
            local tw = self:Animate(LoadingOverlay, self.Tokens.Anim.Normal, { BackgroundTransparency = 1 })
            if tw then tw.Completed:Wait() end
            if LoadingOverlay and LoadingOverlay.Parent then LoadingOverlay:Destroy() end
        end))
    end

    Window._transitionId = 1
    Main.Visible = true
    self:_syncBlur()
    if self.ReducedMotion then
        Main.GroupTransparency = 0
        WinScale.Scale = uiScaleValue
    else
        self:Animate(Main, self.Tokens.Anim.Normal, { GroupTransparency = 0 })
        self:Animate(WinScale, self.Tokens.Anim.Normal, { Scale = uiScaleValue })
    end

    -- ========================================================================
    -- 7. CRIAÇÃO DE ABAS, SEÇÕES E CONTROLES
    -- ========================================================================
    function Window:AddTab(tabName: string, forceSingleColumn: boolean?)
        tabName = tostring(tabName or "Aba")
        local tabScope = winScope:NewChild()

        local Tab = {
            Name = tabName,
            Active = false,
            ForceSingleColumn = (forceSingleColumn == true),
            Sections = {},
            _scope = tabScope
        }

        local TabBtn = create("TextButton", {
            Name = tabName .. "_TabBtn",
            Size = (Window.LayoutMode == "Mobile") and UDim2.fromOffset(112, 32) or UDim2.new(1, 0, 0, 34),
            BackgroundColor3 = Royalty.Theme.Surface,
            BackgroundTransparency = 1,
            AutoButtonColor = false,
            Text = "",
            Parent = TabList
        }, { create("UICorner", { CornerRadius = Royalty.Tokens.Corner.Control }) })
        Royalty:BindThemeProperty(tabScope, TabBtn, "BackgroundColor3", "Surface")

        local ActiveBar = create("Frame", {
            Size = UDim2.fromOffset(3, 0),
            Position = UDim2.new(0, 0, 0.5, 0),
            AnchorPoint = Vector2.new(0, 0.5),
            BackgroundColor3 = Royalty.Theme.Accent,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Parent = TabBtn
        }, { create("UICorner", { CornerRadius = Royalty.Tokens.Corner.Pill }) })
        Royalty:BindThemeProperty(tabScope, ActiveBar, "BackgroundColor3", "Accent")

        local TabTitle = create("TextLabel", {
            Size = UDim2.new(1, -20, 1, 0),
            Position = UDim2.fromOffset(12, 0),
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
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Visible = false,
            ScrollingDirection = Enum.ScrollingDirection.Y,
            ScrollBarThickness = 3,
            ScrollBarImageColor3 = Royalty.Theme.Border,
            CanvasSize = UDim2.fromOffset(0, 0),
            AutomaticCanvasSize = Enum.AutomaticSize.None,
            Parent = PagesHolder
        }, {
            create("UIPadding", {
                PaddingTop = UDim.new(0, 14),
                PaddingBottom = UDim.new(0, 20),
                PaddingLeft = UDim.new(0, 16),
                PaddingRight = UDim.new(0, 20)
            })
        })
        Royalty:BindThemeProperty(tabScope, PageScroll, "ScrollBarImageColor3", "Border")

        local ColumnsContainer = create("Frame", {
            Size = UDim2.new(1, 0, 0, 0),
            BackgroundTransparency = 1,
            Parent = PageScroll
        })

        local LeftColumn = create("Frame", {
            Size = UDim2.new(1, 0, 0, 0),
            BackgroundTransparency = 1,
            Parent = ColumnsContainer
        })
        local LeftLayout = create("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 12),
            Parent = LeftColumn
        })

        local RightColumn = create("Frame", {
            Size = UDim2.new(1, 0, 0, 0),
            BackgroundTransparency = 1,
            Parent = ColumnsContainer
        })
        local RightLayout = create("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 12),
            Parent = RightColumn
        })

        function Tab:_updateColumns()
            local rawW = PageScroll.AbsoluteSize.X
            local innerW = math.max(220, rawW - 36)

            local hasLeft, hasRight = false, false
            for _, sec in ipairs(self.Sections) do
                if sec.Frame.Visible then
                    if sec.Side == "right" then hasRight = true else hasLeft = true end
                end
            end

            local leftH = hasLeft and LeftLayout.AbsoluteContentSize.Y or 0
            local rightH = hasRight and RightLayout.AbsoluteContentSize.Y or 0

            local useTwoCols = (not self.ForceSingleColumn)
                and (Window.LayoutMode ~= "Mobile")
                and hasLeft and hasRight
                and (innerW >= 440)

            if useTwoCols then
                local gap = 12
                local colW = math.floor((innerW - gap) * 0.5)
                LeftColumn.Visible = true
                RightColumn.Visible = true
                LeftColumn.Size = UDim2.fromOffset(colW, leftH)
                LeftColumn.Position = UDim2.fromOffset(0, 0)
                RightColumn.Size = UDim2.fromOffset(colW, rightH)
                RightColumn.Position = UDim2.fromOffset(colW + gap, 0)

                local totalH = math.max(leftH, rightH)
                ColumnsContainer.Size = UDim2.fromOffset(innerW, totalH)
                PageScroll.CanvasSize = UDim2.fromOffset(0, totalH + 40)
            else
                LeftColumn.Visible = hasLeft
                RightColumn.Visible = hasRight
                LeftColumn.Size = UDim2.fromOffset(innerW, leftH)
                LeftColumn.Position = UDim2.fromOffset(0, 0)

                local rightY = (hasLeft and leftH > 0) and (leftH + 12) or 0
                RightColumn.Size = UDim2.fromOffset(innerW, rightH)
                RightColumn.Position = UDim2.fromOffset(0, rightY)

                local totalH = leftH + rightH + ((hasLeft and hasRight and leftH > 0 and rightH > 0) and 12 or 0)
                ColumnsContainer.Size = UDim2.fromOffset(innerW, totalH)
                PageScroll.CanvasSize = UDim2.fromOffset(0, totalH + 40)
            end
        end

        tabScope:Connect(PageScroll:GetPropertyChangedSignal("AbsoluteSize"), function() Tab:_updateColumns() end)
        tabScope:Connect(LeftLayout:GetPropertyChangedSignal("AbsoluteContentSize"), function() Tab:_updateColumns() end)
        tabScope:Connect(RightLayout:GetPropertyChangedSignal("AbsoluteContentSize"), function() Tab:_updateColumns() end)

        Royalty:OnThemeChanged(tabScope, function(th)
            TabTitle.TextColor3 = Tab.Active and th.Text or th.SubText
        end)

        function Tab:Activate()
            if Window.ActiveTab == self then return end
            for _, other in ipairs(Window.Tabs) do
                other.Active = false
                other.Page.Visible = false
                other.Title.Font = Royalty.Tokens.Font.Medium
                Royalty:Animate(other.Btn, Royalty.Tokens.Anim.Fast, { BackgroundTransparency = 1 })
                Royalty:Animate(other.Title, Royalty.Tokens.Anim.Fast, { TextColor3 = Royalty.Theme.SubText })
                Royalty:Animate(other.ActiveBar, Royalty.Tokens.Anim.Fast, { Size = UDim2.fromOffset(3, 0), BackgroundTransparency = 1 })
            end

            self.Active = true
            Window.ActiveTab = self
            ActivePageTitle.Text = self.Name

            TabTitle.Font = Royalty.Tokens.Font.Semibold
            Royalty:Animate(TabBtn, Royalty.Tokens.Anim.Fast, { BackgroundTransparency = 0 })
            Royalty:Animate(TabTitle, Royalty.Tokens.Anim.Fast, { TextColor3 = Royalty.Theme.Text })
            Royalty:Animate(ActiveBar, Royalty.Tokens.Anim.Normal, { Size = UDim2.fromOffset(3, 18), BackgroundTransparency = 0 })

            PageScroll.Visible = true
            applySearchFilter()
            self:_updateColumns()

            if not Royalty.ReducedMotion then
                ColumnsContainer.Position = UDim2.fromOffset(0, 6)
                Royalty:Animate(ColumnsContainer, Royalty.Tokens.Anim.Fast, { Position = UDim2.fromOffset(0, 0) })
            else
                ColumnsContainer.Position = UDim2.fromOffset(0, 0)
            end
        end

        tabScope:Connect(TabBtn.Activated, function() Tab:Activate() end)
        Tab.Btn = TabBtn
        Tab.Title = TabTitle
        Tab.ActiveBar = ActiveBar
        Tab.Page = PageScroll
        table.insert(Window.Tabs, Tab)

        if #Window.Tabs == 1 then Tab:Activate() end

        function Tab:AddSection(sectionName: string, side: string?)
            sectionName = tostring(sectionName or "Seção")
            local normSide = (side and string.lower(tostring(side)) == "right") and "right" or "left"
            local parentCol = (normSide == "right") and RightColumn or LeftColumn
            local secScope = tabScope:NewChild()

            local Section = { Name = sectionName, Side = normSide, Items = {}, _scope = secScope }

            local SecFrame = create("Frame", {
                Size = UDim2.new(1, 0, 0, 44),
                BackgroundColor3 = Royalty.Theme.Surface,
                ClipsDescendants = true,
                Parent = parentCol
            }, {
                create("UICorner", { CornerRadius = Royalty.Tokens.Corner.Section }),
                create("UIPadding", { PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12), PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) })
            })
            Royalty:BindThemeProperty(secScope, SecFrame, "BackgroundColor3", "Surface")

            local SecLayout = create("UIListLayout", {
                SortOrder = Enum.SortOrder.LayoutOrder,
                Padding = UDim.new(0, 10),
                Parent = SecFrame
            })

            local SecStroke = create("UIStroke", { Color = Royalty.Theme.BorderSubtle, Thickness = 1, Parent = SecFrame })
            Royalty:BindThemeProperty(secScope, SecStroke, "Color", "BorderSubtle")

            local HeaderHolder = create("Frame", { LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, Parent = SecFrame })
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

            function Section:_updateHeight()
                if not SecFrame or not SecFrame.Parent then return end
                SecFrame.Size = UDim2.new(1, 0, 0, SecLayout.AbsoluteContentSize.Y + 24)
                Tab:_updateColumns()
            end

            secScope:Connect(SecLayout:GetPropertyChangedSignal("AbsoluteContentSize"), function() Section:_updateHeight() end)
            Section.Frame = SecFrame
            table.insert(Tab.Sections, Section)
            Section:_updateHeight()

            local itemOrder = 0
            local function registerItem(inst: Instance, searchLabel: string)
                itemOrder += 1
                (inst :: any).LayoutOrder = itemOrder
                table.insert(Section.Items, { Instance = inst, SearchText = searchLabel })
                Section:_updateHeight()
            end

            function Section:AddLabel(textOrCfg: string | { Text: string?, Description: string? })
                local ctrlScope = secScope:NewChild()
                local mainText = type(textOrCfg) == "table" and tostring(textOrCfg.Text or "") or tostring(textOrCfg or "")
                local descText = type(textOrCfg) == "table" and textOrCfg.Description and tostring(textOrCfg.Description) or nil

                local Holder = create("Frame", {
                    Size = UDim2.new(1, 0, 0, 20),
                    AutomaticSize = Enum.AutomaticSize.Y,
                    BackgroundTransparency = 1,
                    Parent = SecFrame
                }, { create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }) })

                local Lbl = create("TextLabel", {
                    LayoutOrder = 1,
                    Size = UDim2.new(1, 0, 0, 18),
                    AutomaticSize = Enum.AutomaticSize.Y,
                    BackgroundTransparency = 1,
                    Text = mainText,
                    TextColor3 = Royalty.Theme.SubText,
                    Font = Royalty.Tokens.Font.Medium,
                    TextSize = Royalty.Tokens.TextSize.Description,
                    TextWrapped = true,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = Holder
                })
                Royalty:BindThemeProperty(ctrlScope, Lbl, "TextColor3", "SubText")

                if descText and descText ~= "" then
                    local dLbl = create("TextLabel", {
                        LayoutOrder = 2,
                        Size = UDim2.new(1, 0, 0, 15),
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
                    Royalty:BindThemeProperty(ctrlScope, dLbl, "TextColor3", "Muted")
                end

                registerItem(Holder, mainText .. " " .. (descText or ""))
                return {
                    Set = function(_, newText: string)
                        mainText = tostring(newText or "")
                        Lbl.Text = mainText
                        Section:_updateHeight()
                    end,
                    Get = function() return mainText end
                }
            end

            function Section:AddDivider()
                local ctrlScope = secScope:NewChild()
                local Div = create("Frame", {
                    Size = UDim2.new(1, 0, 0, 1),
                    BackgroundColor3 = Royalty.Theme.BorderSubtle,
                    BorderSizePixel = 0,
                    Parent = SecFrame
                })
                Royalty:BindThemeProperty(ctrlScope, Div, "BackgroundColor3", "BorderSubtle")
                registerItem(Div, "")
                return Div
            end

            function Section:AddButton(bCfg: { Name: string?, Description: string?, Tooltip: string?, Destructive: boolean?, Disabled: boolean?, Callback: (() -> ())? }?)
                bCfg = bCfg or {}
                local ctrlScope = secScope:NewChild()
                local bName = tostring(bCfg.Name or "Botão")
                local bDesc = bCfg.Description and tostring(bCfg.Description) or nil
                local destructive = (bCfg.Destructive == true)
                local disabled = (bCfg.Disabled == true)
                local loading = false
                local callback = bCfg.Callback
                local hasDesc = (bDesc ~= nil and bDesc ~= "")

                local BtnFrame = create("TextButton", {
                    Size = UDim2.new(1, 0, 0, hasDesc and 48 or 34),
                    BackgroundColor3 = destructive and Color3.fromRGB(54, 24, 28) or Royalty.Theme.SurfaceElevated,
                    AutoButtonColor = false,
                    Text = "",
                    Parent = SecFrame
                }, {
                    create("UICorner", { CornerRadius = Royalty.Tokens.Corner.Control }),
                    create("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) })
                })

                local BtnStroke = create("UIStroke", {
                    Color = destructive and Royalty.Theme.Error or Royalty.Theme.Border,
                    Thickness = 1,
                    Parent = BtnFrame
                })

                local TitleLbl = create("TextLabel", {
                    Size = UDim2.new(1, -24, 0, 18),
                    Position = hasDesc and UDim2.fromOffset(0, 7) or UDim2.new(0, 0, 0.5, -9),
                    BackgroundTransparency = 1,
                    Text = bName,
                    TextColor3 = destructive and Royalty.Theme.Error or Royalty.Theme.Text,
                    Font = Royalty.Tokens.Font.Semibold,
                    TextSize = Royalty.Tokens.TextSize.Control,
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = BtnFrame
                })

                if hasDesc then
                    local DescLbl = create("TextLabel", {
                        Size = UDim2.new(1, -24, 0, 15),
                        Position = UDim2.fromOffset(0, 25),
                        BackgroundTransparency = 1,
                        Text = bDesc :: string,
                        TextColor3 = Royalty.Theme.Muted,
                        Font = Royalty.Tokens.Font.Regular,
                        TextSize = Royalty.Tokens.TextSize.Small,
                        TextTruncate = Enum.TextTruncate.AtEnd,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        Parent = BtnFrame
                    })
                    Royalty:BindThemeProperty(ctrlScope, DescLbl, "TextColor3", "Muted")
                end

                local RightDot = create("Frame", {
                    Size = UDim2.fromOffset(6, 6),
                    Position = UDim2.new(1, -6, 0.5, -3),
                    BackgroundColor3 = destructive and Royalty.Theme.Error or Royalty.Theme.SubText,
                    BorderSizePixel = 0,
                    Parent = BtnFrame
                }, { create("UICorner", { CornerRadius = Royalty.Tokens.Corner.Pill }) })

                if bCfg.Tooltip then Royalty:AttachTooltip(ctrlScope, BtnFrame, bCfg.Tooltip) end
                registerItem(BtnFrame, bName .. " " .. (bDesc or ""))

                local hovered = false
                local function refreshVisual()
                    if destructive then
                        BtnFrame.BackgroundColor3 = hovered and not disabled and Color3.fromRGB(72, 28, 32) or Color3.fromRGB(48, 22, 26)
                        BtnStroke.Color = Royalty.Theme.Error
                        TitleLbl.TextColor3 = disabled and Royalty.Theme.Muted or Royalty.Theme.Error
                        RightDot.BackgroundColor3 = Royalty.Theme.Error
                        return
                    end
                    local bg = (hovered and not disabled and not loading) and Royalty.Theme.SurfaceHover or Royalty.Theme.SurfaceElevated
                    local txt = (disabled or loading) and Royalty.Theme.Muted or Royalty.Theme.Text
                    local dot = loading and Royalty.Theme.Accent or (hovered and not disabled and Royalty.Theme.Accent or Royalty.Theme.Muted)
                    BtnStroke.Color = Royalty.Theme.Border
                    Royalty:Animate(BtnFrame, Royalty.Tokens.Anim.Fast, { BackgroundColor3 = bg })
                    Royalty:Animate(TitleLbl, Royalty.Tokens.Anim.Fast, { TextColor3 = txt })
                    Royalty:Animate(RightDot, Royalty.Tokens.Anim.Fast, { BackgroundColor3 = dot })
                end

                Royalty:OnThemeChanged(ctrlScope, refreshVisual)
                ctrlScope:Connect(BtnFrame.MouseEnter, function() hovered = true; refreshVisual() end)
                ctrlScope:Connect(BtnFrame.MouseLeave, function() hovered = false; refreshVisual() end)
                ctrlScope:Connect(BtnFrame.Activated, function()
                    if disabled or loading then return end
                    task.spawn(function() safeCall("Button:" .. bName, callback) end)
                end)

                return {
                    SetText = function(_, t: string) bName = tostring(t or ""); TitleLbl.Text = bName end,
                    SetDisabled = function(_, d: boolean) disabled = (d == true); refreshVisual() end,
                    SetLoading = function(_, l: boolean) loading = (l == true); refreshVisual() end
                }
            end

            function Section:AddToggle(tCfg: { Name: string?, Description: string?, Tooltip: string?, Default: boolean?, Disabled: boolean?, Flag: string?, CallOnInit: boolean?, Callback: ((state: boolean) -> ())? }?)
                tCfg = tCfg or {}
                local ctrlScope = secScope:NewChild()
                local tName = tostring(tCfg.Name or "Alternar")
                local tDesc = tCfg.Description and tostring(tCfg.Description) or nil
                local state = (tCfg.Default == true)
                local disabled = (tCfg.Disabled == true)
                local flag = tostring(tCfg.Flag or tName)
                local callOnInit = (tCfg.CallOnInit ~= false)
                local callback = tCfg.Callback
                local hasDesc = (tDesc ~= nil and tDesc ~= "")

                Royalty.Flags[flag] = state
                local ToggleObj = { Value = state, Disabled = disabled }
                Window._controlsByFlag[flag] = ToggleObj

                local RowBtn = create("TextButton", {
                    Size = UDim2.new(1, 0, 0, hasDesc and 42 or 26),
                    BackgroundTransparency = 1,
                    AutoButtonColor = false,
                    Text = "",
                    Parent = SecFrame
                })

                local TitleLbl = create("TextLabel", {
                    Size = UDim2.new(1, -54, 0, 18),
                    Position = hasDesc and UDim2.fromOffset(0, 2) or UDim2.new(0, 0, 0.5, -9),
                    BackgroundTransparency = 1,
                    Text = tName,
                    TextColor3 = Royalty.Theme.Text,
                    Font = Royalty.Tokens.Font.Medium,
                    TextSize = Royalty.Tokens.TextSize.Control,
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = RowBtn
                })

                if hasDesc then
                    local DescLbl = create("TextLabel", {
                        Size = UDim2.new(1, -54, 0, 15),
                        Position = UDim2.fromOffset(0, 22),
                        BackgroundTransparency = 1,
                        Text = tDesc :: string,
                        TextColor3 = Royalty.Theme.Muted,
                        Font = Royalty.Tokens.Font.Regular,
                        TextSize = Royalty.Tokens.TextSize.Small,
                        TextTruncate = Enum.TextTruncate.AtEnd,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        Parent = RowBtn
                    })
                    Royalty:BindThemeProperty(ctrlScope, DescLbl, "TextColor3", "Muted")
                end

                local Track = create("Frame", {
                    Size = UDim2.fromOffset(40, 20),
                    Position = UDim2.new(1, -40, 0.5, -10),
                    BackgroundColor3 = state and Royalty.Theme.Accent or Royalty.Theme.SurfaceElevated,
                    BorderSizePixel = 0,
                    Parent = RowBtn
                }, { create("UICorner", { CornerRadius = Royalty.Tokens.Corner.Pill }) })

                local TrackStroke = create("UIStroke", {
                    Color = state and Royalty.Theme.Accent or Royalty.Theme.Border,
                    Thickness = 1,
                    Parent = Track
                })

                local Knob = create("Frame", {
                    Size = UDim2.fromOffset(14, 14),
                    Position = state and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7),
                    BackgroundColor3 = Color3.fromRGB(255, 255, 255),
                    BorderSizePixel = 0,
                    Parent = Track
                }, { create("UICorner", { CornerRadius = Royalty.Tokens.Corner.Pill }) })

                if tCfg.Tooltip then Royalty:AttachTooltip(ctrlScope, RowBtn, tCfg.Tooltip) end
                registerItem(RowBtn, tName .. " " .. (tDesc or ""))

                local function syncVisual()
                    local isOn = ToggleObj.Value
                    local isDis = ToggleObj.Disabled
                    Royalty:Animate(TitleLbl, Royalty.Tokens.Anim.Fast, {
                        TextColor3 = isDis and Royalty.Theme.Muted or (isOn and Royalty.Theme.Text or Royalty.Theme.SubText)
                    })
                    Royalty:Animate(Track, Royalty.Tokens.Anim.Fast, {
                        BackgroundColor3 = isOn and Royalty.Theme.Accent or Royalty.Theme.SurfaceElevated
                    })
                    Royalty:Animate(TrackStroke, Royalty.Tokens.Anim.Fast, {
                        Color = isOn and Royalty.Theme.Accent or Royalty.Theme.Border
                    })
                    Royalty:Animate(Knob, Royalty.Tokens.Anim.Fast, {
                        Position = isOn and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7),
                        BackgroundColor3 = isOn and Color3.fromRGB(255, 255, 255) or Royalty.Theme.SubText
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
                        task.spawn(function() safeCall("Toggle:" .. tName, callback, boolVal) end)
                    end
                end
                function ToggleObj:Get(): boolean return self.Value end
                function ToggleObj:SetDisabled(d: boolean) self.Disabled = (d == true); syncVisual() end

                ctrlScope:Connect(RowBtn.Activated, function()
                    if ToggleObj.Disabled then return end
                    ToggleObj:Set(not ToggleObj.Value)
                end)

                syncVisual()
                if state and callOnInit then
                    task.spawn(function() safeCall("ToggleInit:" .. tName, callback, true) end)
                end
                return ToggleObj
            end

            function Section:AddSlider(sCfg: { Name: string?, Description: string?, Min: number?, Max: number?, Default: number?, Rounding: number?, Suffix: string?, CallbackOnRelease: boolean?, Flag: string?, Callback: ((val: number) -> ())? }?)
                sCfg = sCfg or {}
                local ctrlScope = secScope:NewChild()
                local sName = tostring(sCfg.Name or "Ajuste")
                local sDesc = sCfg.Description and tostring(sCfg.Description) or nil
                local minVal = tonumber(sCfg.Min) or 0
                local maxVal = tonumber(sCfg.Max) or 100
                if maxVal < minVal then minVal, maxVal = maxVal, minVal end
                local rounding = math.clamp(math.floor(tonumber(sCfg.Rounding) or 0), 0, 4)
                local suffix = tostring(sCfg.Suffix or "")
                local callbackOnRelease = (sCfg.CallbackOnRelease == true)
                local flag = tostring(sCfg.Flag or sName)
                local callback = sCfg.Callback
                local hasDesc = (sDesc ~= nil and sDesc ~= "")

                local function roundValue(n: number): number
                    local clamped = math.clamp(n, minVal, maxVal)
                    if rounding <= 0 then return math.floor(clamped + 0.5) end
                    local mult = 10 ^ rounding
                    return math.floor(clamped * mult + 0.5) / mult
                end

                local currentVal = roundValue(tonumber(sCfg.Default) or minVal)
                Royalty.Flags[flag] = currentVal
                local SliderObj = { Value = currentVal }
                Window._controlsByFlag[flag] = SliderObj

                local Container = create("Frame", {
                    Size = UDim2.new(1, 0, 0, hasDesc and 56 or 38),
                    BackgroundTransparency = 1,
                    Parent = SecFrame
                })

                local TopRow = create("Frame", { Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Parent = Container })
                local TitleLbl = create("TextLabel", {
                    Size = UDim2.new(1, -76, 1, 0),
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
                    Size = UDim2.fromOffset(72, 18),
                    Position = UDim2.new(1, -72, 0, 0),
                    BackgroundTransparency = 1,
                    Text = "",
                    TextColor3 = Royalty.Theme.Accent,
                    Font = Royalty.Tokens.Font.Mono,
                    TextSize = Royalty.Tokens.TextSize.Description,
                    TextXAlignment = Enum.TextXAlignment.Right,
                    Parent = TopRow
                })
                Royalty:BindThemeProperty(ctrlScope, ValueLbl, "TextColor3", "Accent")

                if hasDesc then
                    local DescLbl = create("TextLabel", {
                        Size = UDim2.new(1, 0, 0, 15),
                        Position = UDim2.fromOffset(0, 19),
                        BackgroundTransparency = 1,
                        Text = sDesc :: string,
                        TextColor3 = Royalty.Theme.Muted,
                        Font = Royalty.Tokens.Font.Regular,
                        TextSize = Royalty.Tokens.TextSize.Small,
                        TextTruncate = Enum.TextTruncate.AtEnd,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        Parent = Container
                    })
                    Royalty:BindThemeProperty(ctrlScope, DescLbl, "TextColor3", "Muted")
                end

                local TrackHitbox = create("Frame", {
                    Size = UDim2.new(1, 0, 0, 16),
                    Position = UDim2.new(0, 0, 1, -16),
                    BackgroundTransparency = 1,
                    Active = true,
                    Parent = Container
                })

                local Track = create("Frame", {
                    Size = UDim2.new(1, -12, 0, 6),
                    Position = UDim2.new(0, 6, 0.5, -3),
                    BackgroundColor3 = Royalty.Theme.SurfaceElevated,
                    BorderSizePixel = 0,
                    Parent = TrackHitbox
                }, { create("UICorner", { CornerRadius = Royalty.Tokens.Corner.Pill }) })
                Royalty:BindThemeProperty(ctrlScope, Track, "BackgroundColor3", "SurfaceElevated")

                local TrackStroke = create("UIStroke", { Color = Royalty.Theme.Border, Thickness = 1, Parent = Track })
                Royalty:BindThemeProperty(ctrlScope, TrackStroke, "Color", "Border")

                local Fill = create("Frame", {
                    Size = UDim2.fromScale(0, 1),
                    BackgroundColor3 = Royalty.Theme.Accent,
                    BorderSizePixel = 0,
                    Parent = Track
                }, { create("UICorner", { CornerRadius = Royalty.Tokens.Corner.Pill }) })
                Royalty:BindThemeProperty(ctrlScope, Fill, "BackgroundColor3", "Accent")

                local Thumb = create("Frame", {
                    Size = UDim2.fromOffset(12, 12),
                    AnchorPoint = Vector2.new(0.5, 0.5),
                    Position = UDim2.fromScale(0, 0.5),
                    BackgroundColor3 = Color3.fromRGB(255, 255, 255),
                    BorderSizePixel = 0,
                    Parent = Track
                }, {
                    create("UICorner", { CornerRadius = Royalty.Tokens.Corner.Pill }),
                    create("UIStroke", { Color = Royalty.Theme.Background, Thickness = 1.5 })
                })

                registerItem(Container, sName .. " " .. (sDesc or ""))

                local function updateVisualDirect(val: number)
                    local alpha = (maxVal > minVal) and math.clamp((val - minVal) / (maxVal - minVal), 0, 1) or 0
                    ValueLbl.Text = (rounding > 0) and string.format("%." .. rounding .. "f%s", val, suffix) or (tostring(val) .. suffix)
                    Fill.Size = UDim2.fromScale(alpha, 1)
                    Thumb.Position = UDim2.fromScale(alpha, 0.5)
                end

                function SliderObj:Set(newVal: number, silent: boolean?)
                    local rounded = roundValue(tonumber(newVal) or minVal)
                    local changed = (self.Value ~= rounded)
                    self.Value = rounded
                    Royalty.Flags[flag] = rounded
                    updateVisualDirect(rounded)
                    if changed and not silent then
                        task.spawn(function() safeCall("Slider:" .. sName, callback, rounded) end)
                    end
                end
                function SliderObj:Get(): number return self.Value end

                local isSliding = false
                local function updateFromX(xPos: number, isRelease: boolean)
                    local rel = math.clamp((xPos - Track.AbsolutePosition.X) / math.max(1, Track.AbsoluteSize.X), 0, 1)
                    local rounded = roundValue(minVal + (maxVal - minVal) * rel)
                    local changed = (SliderObj.Value ~= rounded)
                    SliderObj.Value = rounded
                    Royalty.Flags[flag] = rounded
                    updateVisualDirect(rounded)
                    if not callbackOnRelease and changed then
                        task.spawn(function() safeCall("Slider:" .. sName, callback, rounded) end)
                    elseif callbackOnRelease and isRelease then
                        task.spawn(function() safeCall("Slider:" .. sName, callback, rounded) end)
                    end
                end

                ctrlScope:Connect(TrackHitbox.InputBegan, function(inp)
                    if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
                        isSliding = true
                        updateFromX(inp.Position.X, false)
                    end
                end)
                ctrlScope:Connect(UserInputService.InputChanged, function(inp)
                    if isSliding and (inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch) then
                        updateFromX(inp.Position.X, false)
                    end
                end)
                ctrlScope:Connect(UserInputService.InputEnded, function(inp)
                    if isSliding and (inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch) then
                        isSliding = false
                        updateFromX(inp.Position.X, true)
                    end
                end)

                updateVisualDirect(currentVal)
                return SliderObj
            end

            function Section:AddDropdown(dCfg: { Name: string?, Description: string?, Options: { string }?, Default: any, Multi: boolean?, Searchable: boolean?, Flag: string?, Callback: ((val: any) -> ())? }?)
                dCfg = dCfg or {}
                local ctrlScope = secScope:NewChild()
                local dName = tostring(dCfg.Name or "Seletor")
                local dDesc = dCfg.Description and tostring(dCfg.Description) or nil
                local isMulti = (dCfg.Multi == true)
                local flag = tostring(dCfg.Flag or dName)
                local callback = dCfg.Callback

                local cleanOptions: { string } = {}
                if type(dCfg.Options) == "table" then
                    for _, item in ipairs(dCfg.Options) do table.insert(cleanOptions, tostring(item)) end
                end

                local function normalizeMulti(inputVal: any): { [string]: boolean }
                    local map: { [string]: boolean } = {}
                    if type(inputVal) == "table" then
                        if #inputVal > 0 then
                            for _, v in ipairs(inputVal) do
                                local s = tostring(v)
                                if table.find(cleanOptions, s) then map[s] = true end
                            end
                        else
                            for k, v in pairs(inputVal) do
                                local s = tostring(k)
                                if v == true and table.find(cleanOptions, s) then map[s] = true end
                            end
                        end
                    end
                    return map
                end

                local currentVal: any
                if isMulti then
                    currentVal = normalizeMulti(dCfg.Default)
                else
                    local defStr = dCfg.Default ~= nil and tostring(dCfg.Default) or nil
                    currentVal = (defStr and table.find(cleanOptions, defStr)) and defStr or cleanOptions[1]
                end

                Royalty.Flags[flag] = currentVal
                local DropObj = { Value = currentVal, Options = cleanOptions, Open = false }
                Window._controlsByFlag[flag] = DropObj

                local Wrapper = create("Frame", { Size = UDim2.new(1, 0, 0, 52), BackgroundTransparency = 1, Parent = SecFrame })
                local WrapperLayout = create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 5), Parent = Wrapper })

                local TitleLbl = create("TextLabel", {
                    LayoutOrder = 1,
                    Size = UDim2.new(1, 0, 0, 16),
                    BackgroundTransparency = 1,
                    Text = dName,
                    TextColor3 = Royalty.Theme.Text,
                    Font = Royalty.Tokens.Font.Medium,
                    TextSize = Royalty.Tokens.TextSize.Control,
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = Wrapper
                })
                Royalty:BindThemeProperty(ctrlScope, TitleLbl, "TextColor3", "Text")

                if dDesc and dDesc ~= "" then
                    local DescLbl = create("TextLabel", {
                        LayoutOrder = 2,
                        Size = UDim2.new(1, 0, 0, 15),
                        BackgroundTransparency = 1,
                        Text = dDesc,
                        TextColor3 = Royalty.Theme.Muted,
                        Font = Royalty.Tokens.Font.Regular,
                        TextSize = Royalty.Tokens.TextSize.Small,
                        TextTruncate = Enum.TextTruncate.AtEnd,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        Parent = Wrapper
                    })
                    Royalty:BindThemeProperty(ctrlScope, DescLbl, "TextColor3", "Muted")
                end

                local HeaderBtn = create("TextButton", {
                    LayoutOrder = 3,
                    Size = UDim2.new(1, 0, 0, 32),
                    BackgroundColor3 = Royalty.Theme.SurfaceElevated,
                    AutoButtonColor = false,
                    Text = "",
                    Parent = Wrapper
                }, { create("UICorner", { CornerRadius = Royalty.Tokens.Corner.Control }) })
                Royalty:BindThemeProperty(ctrlScope, HeaderBtn, "BackgroundColor3", "SurfaceElevated")

                local HeaderStroke = create("UIStroke", { Color = Royalty.Theme.Border, Thickness = 1, Parent = HeaderBtn })
                Royalty:BindThemeProperty(ctrlScope, HeaderStroke, "Color", "Border")

                local SelectedLbl = create("TextLabel", {
                    Size = UDim2.new(1, -36, 1, 0),
                    Position = UDim2.fromOffset(10, 0),
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

                local _, setChevronOpen, setChevronColor = createChevronIcon(HeaderBtn)
                Royalty:OnThemeChanged(ctrlScope, function(th) setChevronColor(th.SubText) end)

                local DropdownPanel = create("Frame", {
                    LayoutOrder = 4,
                    Size = UDim2.new(1, 0, 0, 120),
                    BackgroundColor3 = Royalty.Theme.Sidebar,
                    Visible = false,
                    Parent = Wrapper
                }, {
                    create("UICorner", { CornerRadius = Royalty.Tokens.Corner.Control }),
                    create("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) })
                })
                Royalty:BindThemeProperty(ctrlScope, DropdownPanel, "BackgroundColor3", "Sidebar")

                local PanelLayout = create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4), Parent = DropdownPanel })
                local PanelStroke = create("UIStroke", { Color = Royalty.Theme.Border, Thickness = 1, Parent = DropdownPanel })
                Royalty:BindThemeProperty(ctrlScope, PanelStroke, "Color", "Border")

                local FilterBox = create("TextBox", {
                    LayoutOrder = 1,
                    Size = UDim2.new(1, 0, 0, 26),
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
                    Size = UDim2.new(1, 0, 0, 100),
                    BackgroundTransparency = 1,
                    BorderSizePixel = 0,
                    ScrollingDirection = Enum.ScrollingDirection.Y,
                    ScrollBarThickness = 2,
                    ScrollBarImageColor3 = Royalty.Theme.Accent,
                    CanvasSize = UDim2.fromOffset(0, 0),
                    AutomaticCanvasSize = Enum.AutomaticSize.None,
                    Parent = DropdownPanel
                })
                Royalty:BindThemeProperty(ctrlScope, OptionsScroll, "ScrollBarImageColor3", "Accent")

                create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2), Parent = OptionsScroll })

                local function syncWrapperHeight()
                    DropdownPanel.Size = UDim2.new(1, 0, 0, PanelLayout.AbsoluteContentSize.Y + 12)
                    Wrapper.Size = UDim2.new(1, 0, 0, WrapperLayout.AbsoluteContentSize.Y)
                    Section:_updateHeight()
                end

                ctrlScope:Connect(WrapperLayout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
                    Wrapper.Size = UDim2.new(1, 0, 0, WrapperLayout.AbsoluteContentSize.Y)
                    Section:_updateHeight()
                end)

                registerItem(Wrapper, dName .. " " .. (dDesc or ""))
                local optionsScope = ctrlScope:NewChild()

                local function updateHeaderText()
                    if #DropObj.Options == 0 then
                        SelectedLbl.Text = "Sem opções"
                        return
                    end
                    if isMulti then
                        local list = {}
                        for _, opt in ipairs(DropObj.Options) do
                            if DropObj.Value[opt] then table.insert(list, opt) end
                        end
                        SelectedLbl.Text = (#list > 0) and table.concat(list, ", ") or "Nenhum"
                    else
                        SelectedLbl.Text = DropObj.Value ~= nil and tostring(DropObj.Value) or "Selecionar..."
                    end
                end

                local function rebuildOptions()
                    optionsScope:Clean()
                    for _, ch in ipairs(OptionsScroll:GetChildren()) do
                        if not ch:IsA("UIListLayout") then ch:Destroy() end
                    end

                    local fq = string.lower(string.gsub(FilterBox.Text, "^%s*(.-)%s*$", "%1"))
                    local visCount = 0

                    for idx, opt in ipairs(DropObj.Options) do
                        if fq == "" or string.find(string.lower(opt), fq, 1, true) ~= nil then
                            visCount += 1
                            local isSel = isMulti and (DropObj.Value[opt] == true) or (DropObj.Value == opt)

                            local OptBtn = create("TextButton", {
                                LayoutOrder = idx,
                                Size = UDim2.new(1, -4, 0, 28),
                                BackgroundColor3 = isSel and Royalty.Theme.SurfaceElevated or Royalty.Theme.Sidebar,
                                BackgroundTransparency = isSel and 0 or 1,
                                AutoButtonColor = false,
                                Text = "",
                                Parent = OptionsScroll
                            }, { create("UICorner", { CornerRadius = UDim.new(0, 4) }) })

                            create("TextLabel", {
                                Size = UDim2.new(1, -30, 1, 0),
                                Position = UDim2.fromOffset(8, 0),
                                BackgroundTransparency = 1,
                                Text = opt,
                                TextColor3 = isSel and Royalty.Theme.Text or Royalty.Theme.SubText,
                                Font = isSel and Royalty.Tokens.Font.Semibold or Royalty.Tokens.Font.Regular,
                                TextSize = Royalty.Tokens.TextSize.Description,
                                TextTruncate = Enum.TextTruncate.AtEnd,
                                TextXAlignment = Enum.TextXAlignment.Left,
                                Parent = OptBtn
                            })

                            local CheckBox = create("Frame", {
                                Size = UDim2.fromOffset(12, 12),
                                Position = UDim2.new(1, -18, 0.5, -6),
                                BackgroundColor3 = isSel and Royalty.Theme.Accent or Royalty.Theme.Surface,
                                BorderSizePixel = 0,
                                Parent = OptBtn
                            }, {
                                create("UICorner", { CornerRadius = isMulti and UDim.new(0, 3) or Royalty.Tokens.Corner.Pill }),
                                create("UIStroke", { Color = isSel and Royalty.Theme.Accent or Royalty.Theme.Border, Thickness = 1 })
                            })

                            if isSel then
                                create("Frame", {
                                    Size = UDim2.fromOffset(6, 6),
                                    Position = UDim2.fromScale(0.5, 0.5),
                                    AnchorPoint = Vector2.new(0.5, 0.5),
                                    BackgroundColor3 = Color3.fromRGB(255, 255, 255),
                                    BorderSizePixel = 0,
                                    Parent = CheckBox
                                }, { create("UICorner", { CornerRadius = Royalty.Tokens.Corner.Pill }) })
                            end

                            optionsScope:Connect(OptBtn.Activated, function()
                                if isMulti then
                                    if DropObj.Value[opt] then DropObj.Value[opt] = nil else DropObj.Value[opt] = true end
                                    Royalty.Flags[flag] = table.clone(DropObj.Value)
                                    updateHeaderText()
                                    rebuildOptions()
                                    task.spawn(function() safeCall("Dropdown:" .. dName, callback, table.clone(DropObj.Value)) end)
                                else
                                    DropObj:Set(opt)
                                    DropObj.Open = false
                                    DropdownPanel.Visible = false
                                    setChevronOpen(false)
                                    syncWrapperHeight()
                                end
                            end)
                        end
                    end

                    if visCount == 0 then
                        create("TextLabel", {
                            Size = UDim2.new(1, 0, 0, 26),
                            BackgroundTransparency = 1,
                            Text = (#DropObj.Options == 0) and "Sem opções" or "Nenhum resultado",
                            TextColor3 = Royalty.Theme.Muted,
                            Font = Royalty.Tokens.Font.Regular,
                            TextSize = Royalty.Tokens.TextSize.Small,
                            Parent = OptionsScroll
                        })
                        OptionsScroll.Size = UDim2.new(1, 0, 0, 28)
                        OptionsScroll.CanvasSize = UDim2.fromOffset(0, 28)
                    else
                        local cH = visCount * 30
                        OptionsScroll.Size = UDim2.new(1, 0, 0, math.min(cH, 136))
                        OptionsScroll.CanvasSize = UDim2.fromOffset(0, cH)
                    end
                    syncWrapperHeight()
                end

                ctrlScope:Connect(FilterBox:GetPropertyChangedSignal("Text"), rebuildOptions)
                Royalty:OnThemeChanged(ctrlScope, function() updateHeaderText(); rebuildOptions() end)

                function DropObj:Set(newVal: any, silent: boolean?)
                    if isMulti then
                        self.Value = normalizeMulti(newVal)
                        Royalty.Flags[flag] = table.clone(self.Value)
                        updateHeaderText()
                        rebuildOptions()
                        if not silent then
                            task.spawn(function() safeCall("Dropdown:" .. dName, callback, table.clone(self.Value)) end)
                        end
                    else
                        local s = newVal ~= nil and tostring(newVal) or nil
                        self.Value = (s and table.find(self.Options, s)) and s or self.Options[1]
                        Royalty.Flags[flag] = self.Value
                        updateHeaderText()
                        rebuildOptions()
                        if not silent then
                            task.spawn(function() safeCall("Dropdown:" .. dName, callback, self.Value) end)
                        end
                    end
                end

                function DropObj:Refresh(newOptions: { string }?, newDefault: any, silent: boolean?)
                    local cleaned = {}
                    if type(newOptions) == "table" then
                        for _, item in ipairs(newOptions) do table.insert(cleaned, tostring(item)) end
                    end
                    self.Options = cleaned
                    cleanOptions = cleaned
                    FilterBox.Visible = (dCfg.Searchable == true) or (#cleaned >= 6)
                    FilterBox.Text = ""
                    if newDefault ~= nil then self:Set(newDefault, silent) else self:Set(self.Value, true) end
                end

                function DropObj:Get(): any
                    return isMulti and table.clone(self.Value) or self.Value
                end

                ctrlScope:Connect(HeaderBtn.Activated, function()
                    DropObj.Open = not DropObj.Open
                    DropdownPanel.Visible = DropObj.Open
                    setChevronOpen(DropObj.Open)
                    if DropObj.Open then rebuildOptions() else syncWrapperHeight() end
                end)

                updateHeaderText()
                rebuildOptions()
                return DropObj
            end

            function Section:AddKeybind(kCfg: { Name: string?, Description: string?, Default: any, Mode: string?, Flag: string?, Callback: ((active: boolean) -> ())?, ChangedCallback: ((newKey: any) -> ())? }?)
                kCfg = kCfg or {}
                local ctrlScope = secScope:NewChild()
                local kName = tostring(kCfg.Name or "Tecla de Atalho")
                local kDesc = kCfg.Description and tostring(kCfg.Description) or nil
                local currentKey = kCfg.Default
                local currentMode = (kCfg.Mode and string.lower(tostring(kCfg.Mode)) == "hold") and "Hold" or "Toggle"
                local flag = tostring(kCfg.Flag or kName)
                local callback = kCfg.Callback
                local changedCallback = kCfg.ChangedCallback
                local hasDesc = (kDesc ~= nil and kDesc ~= "")

                Royalty.Flags[flag] = currentKey
                local KeyObj = { Name = kName, Key = currentKey, Mode = currentMode, Active = false, Binding = false }
                Window._controlsByFlag[flag] = KeyObj
                table.insert(Royalty._registeredKeybinds, KeyObj)
                ctrlScope:Add(function()
                    local idx = table.find(Royalty._registeredKeybinds, KeyObj)
                    if idx then table.remove(Royalty._registeredKeybinds, idx) end
                    Royalty:_refreshHotkeyList()
                end)

                local Row = create("Frame", { Size = UDim2.new(1, 0, 0, hasDesc and 42 or 26), BackgroundTransparency = 1, Parent = SecFrame })
                local TitleLbl = create("TextLabel", {
                    Size = UDim2.new(1, -82, 0, 18),
                    Position = hasDesc and UDim2.fromOffset(0, 2) or UDim2.new(0, 0, 0.5, -9),
                    BackgroundTransparency = 1,
                    Text = kName,
                    TextColor3 = Royalty.Theme.Text,
                    Font = Royalty.Tokens.Font.Medium,
                    TextSize = Royalty.Tokens.TextSize.Control,
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = Row
                })
                Royalty:BindThemeProperty(ctrlScope, TitleLbl, "TextColor3", "Text")

                if hasDesc then
                    local DescLbl = create("TextLabel", {
                        Size = UDim2.new(1, -82, 0, 15),
                        Position = UDim2.fromOffset(0, 22),
                        BackgroundTransparency = 1,
                        Text = kDesc :: string,
                        TextColor3 = Royalty.Theme.Muted,
                        Font = Royalty.Tokens.Font.Regular,
                        TextSize = Royalty.Tokens.TextSize.Small,
                        TextTruncate = Enum.TextTruncate.AtEnd,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        Parent = Row
                    })
                    Royalty:BindThemeProperty(ctrlScope, DescLbl, "TextColor3", "Muted")
                end

                local KeyBtn = create("TextButton", {
                    Size = UDim2.fromOffset(72, 24),
                    Position = UDim2.new(1, -72, 0.5, -12),
                    BackgroundColor3 = Royalty.Theme.SurfaceElevated,
                    AutoButtonColor = false,
                    Text = "[" .. formatKeyName(currentKey) .. "]",
                    TextColor3 = Royalty.Theme.Text,
                    Font = Royalty.Tokens.Font.Mono,
                    TextSize = Royalty.Tokens.TextSize.Small,
                    Parent = Row
                }, { create("UICorner", { CornerRadius = UDim.new(0, 5) }) })
                Royalty:BindThemeProperty(ctrlScope, KeyBtn, "BackgroundColor3", "SurfaceElevated")
                Royalty:BindThemeProperty(ctrlScope, KeyBtn, "TextColor3", "Text")

                local KeyStroke = create("UIStroke", { Color = Royalty.Theme.Border, Thickness = 1, Parent = KeyBtn })
                Royalty:BindThemeProperty(ctrlScope, KeyStroke, "Color", "Border")

                registerItem(Row, kName .. " " .. (kDesc or ""))
                Royalty:_refreshHotkeyList()

                function KeyObj:Set(newKey: any, silent: boolean?)
                    self.Key = newKey
                    Royalty.Flags[flag] = newKey
                    KeyBtn.Text = "[" .. formatKeyName(newKey) .. "]"
                    Royalty:_refreshHotkeyList()
                    if not silent then
                        task.spawn(function() safeCall("KeybindChanged:" .. kName, changedCallback, newKey) end)
                    end
                end
                function KeyObj:Get(): any return self.Key end

                ctrlScope:Connect(KeyBtn.Activated, function()
                    KeyObj.Binding = true
                    Window._isBindingKey = true
                    KeyBtn.Text = "[ ... ]"
                    Royalty:Animate(KeyStroke, Royalty.Tokens.Anim.Fast, { Color = Royalty.Theme.Accent })
                end)

                ctrlScope:Connect(UserInputService.InputBegan, function(input, gp)
                    if KeyObj.Binding then
                        if input.KeyCode == Enum.KeyCode.Escape then
                            KeyObj.Binding = false
                            task.defer(function() Window._isBindingKey = false end)
                            KeyBtn.Text = "[" .. formatKeyName(KeyObj.Key) .. "]"
                            Royalty:Animate(KeyStroke, Royalty.Tokens.Anim.Fast, { Color = Royalty.Theme.Border })
                            return
                        elseif input.KeyCode == Enum.KeyCode.Backspace or input.KeyCode == Enum.KeyCode.Delete then
                            KeyObj.Binding = false
                            task.defer(function() Window._isBindingKey = false end)
                            KeyObj:Set(nil)
                            Royalty:Animate(KeyStroke, Royalty.Tokens.Anim.Fast, { Color = Royalty.Theme.Border })
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
                            Royalty:Animate(KeyStroke, Royalty.Tokens.Anim.Fast, { Color = Royalty.Theme.Border })
                        end
                        return
                    end

                    if gp or UserInputService:GetFocusedTextBox() ~= nil then return end
                    if not KeyObj.Key or KeyObj.Key == Window.ToggleKey then return end

                    if input.KeyCode == KeyObj.Key or input.UserInputType == KeyObj.Key then
                        if KeyObj.Mode == "Hold" then
                            if not KeyObj.Active then
                                KeyObj.Active = true
                                Royalty:_refreshHotkeyList()
                                task.spawn(function() safeCall("Keybind:" .. kName, callback, true) end)
                            end
                        else
                            KeyObj.Active = not KeyObj.Active
                            Royalty:_refreshHotkeyList()
                            task.spawn(function() safeCall("Keybind:" .. kName, callback, KeyObj.Active) end)
                        end
                    end
                end)

                ctrlScope:Connect(UserInputService.InputEnded, function(input)
                    if KeyObj.Binding or not KeyObj.Key or KeyObj.Mode ~= "Hold" then return end
                    if (input.KeyCode == KeyObj.Key or input.UserInputType == KeyObj.Key) and KeyObj.Active then
                        KeyObj.Active = false
                        Royalty:_refreshHotkeyList()
                        task.spawn(function() safeCall("Keybind:" .. kName, callback, false) end)
                    end
                end)

                return KeyObj
            end

            function Section:AddColorPicker(cCfg: { Name: string?, Description: string?, Default: Color3?, Flag: string?, Callback: ((color: Color3) -> ())? }?)
                cCfg = cCfg or {}
                local ctrlScope = secScope:NewChild()
                local cName = tostring(cCfg.Name or "Cor")
                local cDesc = cCfg.Description and tostring(cCfg.Description) or nil
                local currentColor: Color3 = typeof(cCfg.Default) == "Color3" and cCfg.Default or Royalty.Theme.Accent
                local flag = tostring(cCfg.Flag or cName)
                local callback = cCfg.Callback

                local h, s, v = Color3.toHSV(currentColor)
                Royalty.Flags[flag] = currentColor
                local ColorObj = { Value = currentColor, Open = false }
                Window._controlsByFlag[flag] = ColorObj

                local Wrapper = create("Frame", { Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, Parent = SecFrame })
                local WrapperLayout = create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6), Parent = Wrapper })

                local TopRow = create("TextButton", { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, AutoButtonColor = false, Text = "", Parent = Wrapper })
                local TitleLbl = create("TextLabel", {
                    Size = UDim2.new(1, -52, 1, 0),
                    BackgroundTransparency = 1,
                    Text = cName,
                    TextColor3 = Royalty.Theme.Text,
                    Font = Royalty.Tokens.Font.Medium,
                    TextSize = Royalty.Tokens.TextSize.Control,
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = TopRow
                })
                Royalty:BindThemeProperty(ctrlScope, TitleLbl, "TextColor3", "Text")

                local SwatchBtn = create("Frame", {
                    Size = UDim2.fromOffset(40, 20),
                    Position = UDim2.new(1, -40, 0.5, -10),
                    BackgroundColor3 = currentColor,
                    Parent = TopRow
                }, {
                    create("UICorner", { CornerRadius = UDim.new(0, 5) }),
                    create("UIStroke", { Color = Royalty.Theme.Border, Thickness = 1 })
                })

                local PickerPanel = create("Frame", {
                    LayoutOrder = 2,
                    Size = UDim2.new(1, 0, 0, 114),
                    BackgroundColor3 = Royalty.Theme.Sidebar,
                    Visible = false,
                    Parent = Wrapper
                }, {
                    create("UICorner", { CornerRadius = Royalty.Tokens.Corner.Control }),
                    create("UIStroke", { Color = Royalty.Theme.Border, Thickness = 1 }),
                    create("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }),
                    create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) })
                })
                Royalty:BindThemeProperty(ctrlScope, PickerPanel, "BackgroundColor3", "Sidebar")

                ctrlScope:Connect(WrapperLayout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
                    Wrapper.Size = UDim2.new(1, 0, 0, WrapperLayout.AbsoluteContentSize.Y)
                    Section:_updateHeight()
                end)
                registerItem(Wrapper, cName .. " " .. (cDesc or ""))

                local function createHSVBar(order: number, labelText: string)
                    local row = create("Frame", { LayoutOrder = order, Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Parent = PickerPanel })
                    local lbl = create("TextLabel", {
                        Size = UDim2.fromOffset(16, 18),
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
                        Size = UDim2.new(1, -26, 0, 10),
                        Position = UDim2.new(0, 22, 0.5, -5),
                        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
                        BorderSizePixel = 0,
                        Active = true,
                        Parent = row
                    }, {
                        create("UICorner", { CornerRadius = Royalty.Tokens.Corner.Pill }),
                        create("UIStroke", { Color = Royalty.Theme.Border, Thickness = 1 })
                    })
                    local grad = create("UIGradient", { Parent = bar })
                    local cursor = create("Frame", {
                        Size = UDim2.fromOffset(8, 14),
                        AnchorPoint = Vector2.new(0.5, 0.5),
                        Position = UDim2.fromScale(0, 0.5),
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

                local BottomRow = create("Frame", { LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, Parent = PickerPanel })
                local RGBLabel = create("TextLabel", {
                    Size = UDim2.new(1, -92, 1, 0),
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
                    Size = UDim2.fromOffset(84, 24),
                    Position = UDim2.new(1, -84, 0, 0),
                    BackgroundColor3 = Royalty.Theme.Surface,
                    Text = colorToHex(currentColor),
                    PlaceholderText = "#RRGGBB",
                    TextColor3 = Royalty.Theme.Text,
                    Font = Royalty.Tokens.Font.Mono,
                    TextSize = 11,
                    ClearTextOnFocus = false,
                    Parent = BottomRow
                }, { create("UICorner", { CornerRadius = UDim.new(0, 4) }) })
                Royalty:BindThemeProperty(ctrlScope, HexBox, "BackgroundColor3", "Surface")
                Royalty:BindThemeProperty(ctrlScope, HexBox, "TextColor3", "Text")
                local HexStroke = create("UIStroke", { Color = Royalty.Theme.Border, Thickness = 1, Parent = HexBox })

                local function syncPickerVisuals()
                    SatGrad.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromHSV(h, 1, 1))
                    ValGrad.Color = ColorSequence.new(Color3.fromRGB(0, 0, 0), Color3.fromHSV(h, s, 1))
                    HueCursor.Position = UDim2.fromScale(math.clamp(h, 0, 1), 0.5)
                    SatCursor.Position = UDim2.fromScale(math.clamp(s, 0, 1), 0.5)
                    ValCursor.Position = UDim2.fromScale(math.clamp(v, 0, 1), 0.5)

                    local c = ColorObj.Value
                    SwatchBtn.BackgroundColor3 = c
                    RGBLabel.Text = string.format("RGB: %d, %d, %d", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
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
                        task.spawn(function() safeCall("ColorPicker:" .. cName, callback, newColor) end)
                    end
                end
                function ColorObj:Get(): Color3 return self.Value end

                local activeBar: string? = nil
                local function updateBar(mode: string, xPos: number)
                    local b = (mode == "H" and HueBar) or (mode == "S" and SatBar) or ValBar
                    local rel = math.clamp((xPos - b.AbsolutePosition.X) / math.max(1, b.AbsoluteSize.X), 0, 1)
                    if mode == "H" then h = rel elseif mode == "S" then s = rel else v = rel end
                    local comp = Color3.fromHSV(h, s, v)
                    ColorObj.Value = comp
                    Royalty.Flags[flag] = comp
                    syncPickerVisuals()
                    task.spawn(function() safeCall("ColorPicker:" .. cName, callback, comp) end)
                end

                ctrlScope:Connect(HueBar.InputBegan, function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then activeBar = "H"; updateBar("H", i.Position.X) end end)
                ctrlScope:Connect(SatBar.InputBegan, function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then activeBar = "S"; updateBar("S", i.Position.X) end end)
                ctrlScope:Connect(ValBar.InputBegan, function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then activeBar = "V"; updateBar("V", i.Position.X) end end)
                ctrlScope:Connect(UserInputService.InputChanged, function(i) if activeBar and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then updateBar(activeBar, i.Position.X) end end)
                ctrlScope:Connect(UserInputService.InputEnded, function(i) if activeBar and (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) then activeBar = nil end end)

                ctrlScope:Connect(HexBox.FocusLost, function()
                    local parsed = hexToColor(HexBox.Text)
                    if parsed then
                        HexStroke.Color = Royalty.Theme.Border
                        ColorObj:Set(parsed)
                    else
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
                    if ColorObj.Open then syncPickerVisuals() end
                    Wrapper.Size = UDim2.new(1, 0, 0, WrapperLayout.AbsoluteContentSize.Y)
                    Section:_updateHeight()
                end)

                syncPickerVisuals()
                return ColorObj
            end

            function Section:AddInput(iCfg: { Name: string?, Description: string?, Placeholder: string?, Default: string?, MaxLength: number?, CallbackOnType: boolean?, Validator: ((txt: string) -> boolean)?, Flag: string?, Callback: ((txt: string) -> ())? }?)
                iCfg = iCfg or {}
                local ctrlScope = secScope:NewChild()
                local iName = tostring(iCfg.Name or "Campo de Texto")
                local iDesc = iCfg.Description and tostring(iCfg.Description) or nil
                local placeholder = tostring(iCfg.Placeholder or "Digite aqui...")
                local maxLen = tonumber(iCfg.MaxLength)
                local callbackOnType = (iCfg.CallbackOnType == true)
                local validator = iCfg.Validator
                local flag = tostring(iCfg.Flag or iName)
                local callback = iCfg.Callback
                local hasDesc = (iDesc ~= nil and iDesc ~= "")

                local currentText = tostring(iCfg.Default or "")
                if maxLen and #currentText > maxLen then currentText = string.sub(currentText, 1, maxLen) end

                Royalty.Flags[flag] = currentText
                local InputObj = { Value = currentText }
                Window._controlsByFlag[flag] = InputObj

                local Container = create("Frame", { Size = UDim2.new(1, 0, 0, hasDesc and 70 or 52), BackgroundTransparency = 1, Parent = SecFrame })
                local TitleLbl = create("TextLabel", {
                    Size = UDim2.new(1, 0, 0, 16),
                    BackgroundTransparency = 1,
                    Text = iName,
                    TextColor3 = Royalty.Theme.Text,
                    Font = Royalty.Tokens.Font.Medium,
                    TextSize = Royalty.Tokens.TextSize.Control,
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = Container
                })
                Royalty:BindThemeProperty(ctrlScope, TitleLbl, "TextColor3", "Text")

                if hasDesc then
                    local DescLbl = create("TextLabel", {
                        Size = UDim2.new(1, 0, 0, 15),
                        Position = UDim2.fromOffset(0, 18),
                        BackgroundTransparency = 1,
                        Text = iDesc :: string,
                        TextColor3 = Royalty.Theme.Muted,
                        Font = Royalty.Tokens.Font.Regular,
                        TextSize = Royalty.Tokens.TextSize.Small,
                        TextTruncate = Enum.TextTruncate.AtEnd,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        Parent = Container
                    })
                    Royalty:BindThemeProperty(ctrlScope, DescLbl, "TextColor3", "Muted")
                end

                local BoxHolder = create("Frame", {
                    Size = UDim2.new(1, 0, 0, 32),
                    Position = UDim2.new(0, 0, 1, -32),
                    BackgroundColor3 = Royalty.Theme.SurfaceElevated,
                    Parent = Container
                }, { create("UICorner", { CornerRadius = Royalty.Tokens.Corner.Control }) })
                Royalty:BindThemeProperty(ctrlScope, BoxHolder, "BackgroundColor3", "SurfaceElevated")

                local BoxStroke = create("UIStroke", { Color = Royalty.Theme.Border, Thickness = 1, Parent = BoxHolder })
                Royalty:BindThemeProperty(ctrlScope, BoxStroke, "Color", "Border")

                local Box = create("TextBox", {
                    Size = UDim2.new(1, -20, 1, 0),
                    Position = UDim2.fromOffset(10, 0),
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

                registerItem(Container, iName .. " " .. (iDesc or ""))

                function InputObj:Set(newText: string, silent: boolean?)
                    local str = tostring(newText or "")
                    if maxLen and #str > maxLen then str = string.sub(str, 1, maxLen) end
                    if type(validator) == "function" then
                        local ok, valid = safeCall("InputValidator:" .. iName, validator, str)
                        if not ok or valid == false then
                            Royalty:Animate(BoxStroke, Royalty.Tokens.Anim.Fast, { Color = Royalty.Theme.Error })
                            Box.Text = self.Value
                            return
                        end
                    end
                    self.Value = str
                    Royalty.Flags[flag] = str
                    if Box.Text ~= str then Box.Text = str end
                    if not silent then
                        task.spawn(function() safeCall("Input:" .. iName, callback, str) end)
                    end
                end
                function InputObj:Get(): string return self.Value end

                ctrlScope:Connect(Box.Focused, function() Royalty:Animate(BoxStroke, Royalty.Tokens.Anim.Fast, { Color = Royalty.Theme.Accent }) end)
                ctrlScope:Connect(Box:GetPropertyChangedSignal("Text"), function()
                    if maxLen and #Box.Text > maxLen then Box.Text = string.sub(Box.Text, 1, maxLen); return end
                    if callbackOnType and UserInputService:GetFocusedTextBox() == Box then InputObj:Set(Box.Text) end
                end)
                ctrlScope:Connect(Box.FocusLost, function()
                    Royalty:Animate(BoxStroke, Royalty.Tokens.Anim.Fast, { Color = Royalty.Theme.Border })
                    InputObj:Set(Box.Text)
                end)

                return InputObj
            end

            -- Aliases de compatibilidade com scripts estilo NeverLose
            Section.Toggle = Section.AddToggle
            Section.Slider = Section.AddSlider
            Section.Dropdown = Section.AddDropdown
            Section.Keybind = Section.AddKeybind
            Section.Colorpicker = Section.AddColorPicker
            Section.Button = Section.AddButton
            Section.Input = Section.AddInput
            Section.Label = Section.AddLabel

            return Section
        end

        Tab.CreateSection = Tab.AddSection
        return Tab
    end

    Window.CreatePage = Window.AddTab

    -- ========================================================================
    -- 8. ABA DE CONFIGURAÇÕES (COLUNA ÚNICA AMPLA + GRUPOS CLAROS)
    -- ========================================================================
    function Window:AddSettingsTab(tabTitle: string?)
        local SettingsTab = self:AddTab(tabTitle or "Configurações", true)
        local AppearanceSec = SettingsTab:AddSection("Aparência", "Left")
        local InterfaceSec = SettingsTab:AddSection("Interface e Comportamento", "Left")
        local ProfileSec = SettingsTab:AddSection("Perfis e Sessão", "Left")

        AppearanceSec:AddDropdown({
            Name = "Tema da Interface",
            Description = "Alterna o esquema de cores entre grafite escuro e claro.",
            Options = { "Escuro", "Claro" },
            Default = (Royalty.Theme.Name == "Claro") and "Claro" or "Escuro",
            Flag = "Royalty_ThemeMode",
            Callback = function(selected) Royalty:SetTheme(selected) end
        })

        AppearanceSec:AddColorPicker({
            Name = "Cor de Destaque",
            Description = "Define a cor ativa para seleções, foco e barras de progresso.",
            Default = Royalty.Theme.Accent,
            Flag = "Royalty_AccentColor",
            Callback = function(color) Royalty:SetAccentColor(color) end
        })

        AppearanceSec:AddToggle({
            Name = "Desfoque de Fundo (Blur)",
            Description = "Escurece e desfoca o ambiente 3D enquanto a janela está visível.",
            Default = self.UseBlur,
            Flag = "Royalty_UseBlur",
            CallOnInit = false,
            Callback = function(state)
                self.UseBlur = state
                Royalty:_syncBlur()
            end
        })

        InterfaceSec:AddDropdown({
            Name = "Modo de Layout",
            Description = "Adapta a navegação entre janela Desktop e layout compacto para toque.",
            Options = { "Desktop", "Mobile" },
            Default = self.LayoutMode,
            Flag = "Royalty_LayoutMode",
            Callback = function(mode) self:SetLayoutMode(mode) end
        })

        InterfaceSec:AddSlider({
            Name = "Escala da Janela",
            Description = "Ajusta o tamanho proporcional de toda a interface.",
            Min = 0.80,
            Max = 1.20,
            Default = self.Scale,
            Rounding = 2,
            Suffix = "x",
            Flag = "Royalty_UIScale",
            Callback = function(scaleVal) self:SetScale(scaleVal) end
        })

        InterfaceSec:AddToggle({
            Name = "Movimento Reduzido",
            Description = "Substitui animações longas por transições instantâneas.",
            Default = Royalty.ReducedMotion,
            Flag = "Royalty_ReducedMotion",
            CallOnInit = false,
            Callback = function(state) Royalty:SetReducedMotion(state) end
        })

        InterfaceSec:AddToggle({
            Name = "Exibir Notificações",
            Description = "Habilita avisos flutuantes no canto inferior direito.",
            Default = Royalty.NotificationsEnabled,
            Flag = "Royalty_NotificationsEnabled",
            CallOnInit = false,
            Callback = function(state) Royalty.NotificationsEnabled = state end
        })

        InterfaceSec:AddKeybind({
            Name = "Atalho para Ocultar Menu",
            Description = "Tecla usada para abrir ou recolher a janela principal.",
            Default = self.ToggleKey,
            Mode = "Toggle",
            Flag = "Royalty_ToggleKey",
            ChangedCallback = function(newKey) self:SetToggleKey(newKey) end
        })

        local profileInput = ProfileSec:AddInput({
            Name = "Nome do Perfil",
            Placeholder = "Padrao",
            Default = "Padrao",
            MaxLength = 24,
            Flag = "Royalty_ProfileName"
        })

        ProfileSec:AddButton({
            Name = "Salvar Configuração Atual",
            Description = Royalty.StorageAdapter and "Grava os estados atuais via StorageAdapter." or "Salva os estados na memória desta sessão.",
            Callback = function()
                local ok, msg = Royalty:SaveConfiguration(profileInput:Get())
                Royalty:Notify({ Title = "Perfis", Content = msg, Type = ok and "Sucesso" or "Erro", Duration = 3 })
            end
        })

        ProfileSec:AddButton({
            Name = "Carregar Configuração",
            Description = "Restaura todos os controles salvos no perfil informado.",
            Callback = function()
                local ok, msg = Royalty:LoadConfiguration(profileInput:Get())
                Royalty:Notify({ Title = "Perfis", Content = msg, Type = ok and "Sucesso" or "Aviso", Duration = 3 })
            end
        })

        ProfileSec:AddDivider()

        ProfileSec:AddButton({
            Name = "Encerrar Interface (Unload)",
            Description = "Desconecta todos os eventos e remove a janela da sessão.",
            Destructive = true,
            Callback = function()
                self:Confirm({
                    Title = "Encerrar Royalty UI?",
                    Content = "Todos os atalhos e janelas ativos serão desconectados imediatamente.",
                    ConfirmText = "Encerrar",
                    CancelText = "Voltar",
                    Destructive = true,
                    OnConfirm = function()
                        self:Destroy()
                    end
                })
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
        if win then win:Destroy() end
    end
    table.clear(self.Windows)
    table.clear(self._themeListeners)
    table.clear(self._registeredKeybinds)
    self._scope:Destroy()
end

return Royalty
