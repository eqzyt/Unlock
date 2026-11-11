--!strict
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer

-- ============================================================================
-- 1. GERENCIADOR DE ESCOPO E CICLO DE VIDA (SCOPE)
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
-- 2. DEFINIÇÃO DA BIBLIOTECA E TEMAS (ROYALTY)
-- ============================================================================
local Royalty = {}
Royalty.__index = Royalty
Royalty.Name = "Royalty"
Royalty.Version = "2.1.0"

Royalty.Themes = {
    Escuro = {
        Name = "Escuro",
        Accent = Color3.fromRGB(88, 124, 244),
        Background = Color3.fromRGB(16, 18, 24),
        Sidebar = Color3.fromRGB(20, 22, 30),
        Surface = Color3.fromRGB(24, 27, 37),
        SurfaceElevated = Color3.fromRGB(31, 35, 48),
        SurfaceHover = Color3.fromRGB(38, 43, 58),
        Border = Color3.fromRGB(48, 54, 72),
        BorderSubtle = Color3.fromRGB(34, 38, 52),
        Text = Color3.fromRGB(244, 246, 250),
        SubText = Color3.fromRGB(176, 182, 198),
        Muted = Color3.fromRGB(116, 124, 142),
        Success = Color3.fromRGB(48, 194, 118),
        Warning = Color3.fromRGB(242, 164, 36),
        Error = Color3.fromRGB(236, 82, 78)
    },
    Claro = {
        Name = "Claro",
        Accent = Color3.fromRGB(54, 96, 224),
        Background = Color3.fromRGB(244, 246, 250),
        Sidebar = Color3.fromRGB(235, 239, 246),
        Surface = Color3.fromRGB(255, 255, 255),
        SurfaceElevated = Color3.fromRGB(240, 243, 249),
        SurfaceHover = Color3.fromRGB(230, 235, 244),
        Border = Color3.fromRGB(206, 213, 226),
        BorderSubtle = Color3.fromRGB(224, 229, 238),
        Text = Color3.fromRGB(20, 24, 33),
        SubText = Color3.fromRGB(74, 82, 98),
        Muted = Color3.fromRGB(128, 136, 154),
        Success = Color3.fromRGB(32, 158, 92),
        Warning = Color3.fromRGB(212, 128, 16),
        Error = Color3.fromRGB(210, 56, 52)
    }
}

-- Alias de compatibilidade para códigos que passarem "Dark" ou "Light"
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
Royalty.StorageAdapter = nil

-- ============================================================================
-- 3. UTILITÁRIOS DE SEGURANÇA, ÍCONES GEOMÉTRICOS E ANIMAÇÃO
-- ============================================================================
local function safeCall(label: string, fn: ((...any) -> ...any)?, ...: any): (boolean, ...any)
    if type(fn) ~= "function" then
        return true
    end
    local args = table.pack(...)
    local results = table.pack(xpcall(function()
        return fn(table.unpack(args, 1, args.n))
    end, function(err)
        return debug.traceback(tostring(err), 2)
    end))
    local ok = results[1]
    if not ok then
        warn(string.format("[Royalty] Erro no callback '%s':\n%s", label, tostring(results[2])))
        return false, results[2]
    end
    return true, table.unpack(results, 2, results.n)
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

-- Cria um ícone de seta (chevron) geométrico puro com 2 barras (nunca vira quadrado de fonte)
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
    }, {
        create("UICorner", { CornerRadius = UDim.new(1, 0) })
    })

    local rightBar = create("Frame", {
        Size = UDim2.fromOffset(6, 2),
        Position = UDim2.fromOffset(6, 6),
        AnchorPoint = Vector2.new(0, 0.5),
        Rotation = -40,
        BorderSizePixel = 0,
        Parent = holder
    }, {
        create("UICorner", { CornerRadius = UDim.new(1, 0) })
    })

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

-- Cria um ícone "X" geométrico puro para botões de fechar
local function createCloseIcon(parent: Instance): (TextButton, (color: Color3) -> ())
    local btn = create("TextButton", {
        Size = UDim2.fromOffset(18, 18),
        Position = UDim2.new(1, -18, 0, 0),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        Parent = parent
    })

    local bar1 = create("Frame", {
        Size = UDim2.fromOffset(12, 2),
        Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Rotation = 45,
        BorderSizePixel = 0,
        Parent = btn
    }, {
        create("UICorner", { CornerRadius = UDim.new(1, 0) })
    })

    local bar2 = create("Frame", {
        Size = UDim2.fromOffset(12, 2),
        Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Rotation = -45,
        BorderSizePixel = 0,
        Parent = btn
    }, {
        create("UICorner", { CornerRadius = UDim.new(1, 0) })
    })

    local function setColor(color: Color3)
        bar1.BackgroundColor3 = color
        bar2.BackgroundColor3 = color
    end

    return btn, setColor
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

    local actualDuration = self.ReducedMotion and 0 or (duration or self.Tokens.Anim.Normal)
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
            style or self.Tokens.Anim.Style,
            direction or self.Tokens.Anim.Dir
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
                self:Animate(instance, self.Tokens.Anim.Fast, { [property] = color })
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
        warn("[Royalty] Tema inválido em SetTheme: " .. tostring(themeNameOrTable))
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
        warn("[Royalty] SetAccentColor requer um Color3.")
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
    if not keyEnum then return "Nenhum" end
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
-- 4. PERSISTÊNCIA (ADAPTADOR OPCIONAL + MEMÓRIA)
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
    local trimmed = string.gsub(tostring(profileName or ""), "^%s*(.-)%s*$", "%1")
    local key = (trimmed ~= "") and trimmed or "Padrao"
    local payload = self:_serializeFlags()

    if self.StorageAdapter and type(self.StorageAdapter.Save) == "function" then
        local ok, status, err = safeCall("StorageAdapter.Save", self.StorageAdapter.Save, key, payload)
        if not ok or status == false then
            return false, tostring(err or "Falha ao gravar no adaptador.")
        end
        return true, string.format("Perfil '%s' salvo com sucesso.", key)
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
            return false, string.format("Não foi possível carregar o perfil '%s'.", key)
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
-- 5. CONTAINER RAIZ, BLUR + ESCURECIMENTO DE FUNDO E NOTIFICAÇÕES
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

    local backdropDim = create("Frame", {
        Name = "BackdropDim",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.fromRGB(6, 8, 12),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 0,
        Parent = gui
    })
    self._backdropDim = backdropDim

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
        Size = UDim2.new(0, 290, 1, -32),
        Position = UDim2.new(1, -306, 0, 16),
        BackgroundTransparency = 1,
        ZIndex = 100,
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
            self:Animate(self._blurEffect, self.Tokens.Anim.Normal, { Size = 14 })
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
            self:Animate(self._backdropDim, self.Tokens.Anim.Normal, { BackgroundTransparency = 0.45 })
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
    if nType == "success" or nType == "sucesso" then
        typeToken = "Success"
    elseif nType == "warning" or nType == "aviso" then
        typeToken = "Warning"
    elseif nType == "error" or nType == "erro" then
        typeToken = "Error"
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
        Position = UDim2.new(0, 20, 0, 0),
        BackgroundColor3 = self.Theme.Surface,
        BackgroundTransparency = 1,
        ClipsDescendants = true,
        Parent = wrapper
    }, {
        create("UICorner", { CornerRadius = self.Tokens.Corner.Section })
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

    local statusDot = create("Frame", {
        Size = UDim2.fromOffset(8, 8),
        Position = UDim2.new(0, 2, 0.5, -4),
        BackgroundColor3 = self.Theme[typeToken],
        BorderSizePixel = 0,
        Parent = topRow
    }, {
        create("UICorner", { CornerRadius = self.Tokens.Corner.Pill })
    })
    self:BindThemeProperty(notifScope, statusDot, "BackgroundColor3", typeToken)

    local titleLbl = create("TextLabel", {
        Size = UDim2.new(1, -38, 1, 0),
        Position = UDim2.new(0, 16, 0, 0),
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
    self:OnThemeChanged(notifScope, function(theme)
        setCloseColor(theme.Muted)
    end)

    if contentText ~= "" then
        local bodyLbl = create("TextLabel", {
            LayoutOrder = 2,
            Size = UDim2.new(1, -16, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            Position = UDim2.new(0, 16, 0, 0),
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

    self:Animate(card, self.Tokens.Anim.Normal, {
        Position = UDim2.new(0, 0, 0, 0),
        BackgroundTransparency = 0
    })
    self:Animate(stroke, self.Tokens.Anim.Normal, { Transparency = 0 })

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
        local tw = self:Animate(card, self.Tokens.Anim.Fast, {
            Position = UDim2.new(0, 20, 0, 0),
            BackgroundTransparency = 1
        })
        self:Animate(stroke, self.Tokens.Anim.Fast, { Transparency = 1 })
        if tw then
            tw.Completed:Once(function()
                notifScope:Destroy()
            end)
        else
            notifScope:Destroy()
        end
    end

    notifScope:Connect(closeBtn.Activated, dismiss)
    notifScope:Add(task.delay(duration, dismiss))

    return {
        Dismiss = dismiss
    }
end

-- ============================================================================
-- 6. CRIAÇÃO DE JANELA E NAVEGAÇÃO
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
    local subTitleText = tostring(cfg.SubTitle or "v2.1")
    local rawSize: UDim2 = typeof(cfg.Size) == "UDim2" and cfg.Size or UDim2.fromOffset(640, 440)
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

    local function computeCenteredBounds(requestedSize: UDim2): (UDim2, UDim2)
        local cam = workspace.CurrentCamera
        local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
        local w = requestedSize.X.Scale * vp.X + requestedSize.X.Offset
        local h = requestedSize.Y.Scale * vp.Y + requestedSize.Y.Offset
        w = math.clamp(w, 380, math.max(400, vp.X - 32))
        h = math.clamp(h, 280, math.max(300, vp.Y - 48))
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
        ZIndex = 10,
        Parent = self._rootGui
    }, {
        create("UICorner", { CornerRadius = self.Tokens.Corner.Window })
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

    -- Sidebar Lateral
    local Sidebar = create("Frame", {
        Name = "Sidebar",
        Size = UDim2.new(0, 164, 1, 0),
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
        Name = "BrandHeader",
        Size = UDim2.new(1, 0, 0, 56),
        BackgroundTransparency = 1,
        Parent = Sidebar
    })

    local BrandIndicator = create("Frame", {
        Size = UDim2.fromOffset(6, 20),
        Position = UDim2.fromOffset(14, 18),
        BackgroundColor3 = self.Theme.Accent,
        BorderSizePixel = 0,
        Parent = BrandHeader
    }, {
        create("UICorner", { CornerRadius = self.Tokens.Corner.Pill })
    })
    self:BindThemeProperty(winScope, BrandIndicator, "BackgroundColor3", "Accent")

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
        Position = UDim2.fromOffset(12, 0),
        BackgroundColor3 = self.Theme.BorderSubtle,
        BorderSizePixel = 0,
        Parent = FooterFrame
    })
    self:BindThemeProperty(winScope, FooterDivider, "BackgroundColor3", "BorderSubtle")

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

    -- Área de Conteúdo
    local ContentArea = create("Frame", {
        Name = "ContentArea",
        Size = UDim2.new(1, -164, 1, 0),
        Position = UDim2.fromOffset(164, 0),
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
        Size = UDim2.new(1, -210, 1, 0),
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

    local SearchContainer = create("Frame", {
        Size = UDim2.fromOffset(176, 30),
        Position = UDim2.new(1, -194, 0.5, -15),
        BackgroundColor3 = self.Theme.Surface,
        Parent = TopHeaderBar
    }, {
        create("UICorner", { CornerRadius = self.Tokens.Corner.Control })
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
        Size = UDim2.new(1, 0, 1, -52),
        Position = UDim2.fromOffset(0, 52),
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

    -- Arrasto da Janela
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

            local minX = -math.floor(absSize.X * 0.6)
            local maxX = math.floor(vp.X - absSize.X * 0.4)
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

    -- Busca em Tempo Real
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
                sec:_updateHeight()
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
            sec:_updateHeight()
            if sec.Frame.Visible then
                anyMatchInTab = true
            end
        end

        EmptySearchBanner.Visible = not anyMatchInTab
        activeTab:_updateColumns()
    end

    winScope:Connect(SearchBox:GetPropertyChangedSignal("Text"), applySearchFilter)
    winScope:Connect(SearchBox.Focused, function()
        Royalty:Animate(SearchStroke, Royalty.Tokens.Anim.Fast, { Color = Royalty.Theme.Accent })
    end)
    winScope:Connect(SearchBox.FocusLost, function()
        Royalty:Animate(SearchStroke, Royalty.Tokens.Anim.Fast, { Color = Royalty.Theme.BorderSubtle })
    end)

    -- Métodos de Janela
    function Window:SetScale(newScale: number)
        self.Scale = math.clamp(tonumber(newScale) or 1, 0.75, 1.35)
        Royalty.Flags["Royalty_UIScale"] = self.Scale
        if self.Visible then
            Royalty:Animate(WinScale, Royalty.Tokens.Anim.Fast, { Scale = self.Scale })
        end
        if self.ActiveTab then
            task.defer(function()
                if self.ActiveTab then
                    self.ActiveTab:_updateColumns()
                end
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

    -- Tela de Carregamento Opcional
    local initTasks = cfg.InitTasks
    local showLoading = (cfg.LoadingScreen ~= false) and (type(initTasks) == "table" and #initTasks > 0 or type(initTasks) == "function")

    if showLoading then
        local LoadingOverlay = create("Frame", {
            Name = "LoadingOverlay",
            Size = UDim2.fromScale(1, 1),
            BackgroundColor3 = self.Theme.Background,
            ZIndex = 50,
            Active = true,
            Parent = Main
        })
        self:BindThemeProperty(winScope, LoadingOverlay, "BackgroundColor3", "Background")

        local LoadTitle = create("TextLabel", {
            Size = UDim2.new(1, -48, 0, 24),
            Position = UDim2.new(0, 24, 0.5, -50),
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
            Position = UDim2.new(0, 24, 0.5, -22),
            BackgroundTransparency = 1,
            ZIndex = 51,
            Text = "Inicializando...",
            TextColor3 = self.Theme.SubText,
            Font = self.Tokens.Font.Regular,
            TextSize = self.Tokens.TextSize.Description,
            Parent = LoadingOverlay
        })
        self:BindThemeProperty(winScope, LoadStatus, "TextColor3", "SubText")

        local BarTrack = create("Frame", {
            Size = UDim2.fromOffset(240, 5),
            Position = UDim2.new(0.5, -120, 0.5, 6),
            BackgroundColor3 = self.Theme.SurfaceElevated,
            BorderSizePixel = 0,
            ZIndex = 51,
            ClipsDescendants = true,
            Parent = LoadingOverlay
        }, {
            create("UICorner", { CornerRadius = self.Tokens.Corner.Pill })
        })

        local BarFill = create("Frame", {
            Size = UDim2.fromScale(0, 1),
            BackgroundColor3 = self.Theme.Accent,
            BorderSizePixel = 0,
            ZIndex = 52,
            Parent = BarTrack
        }, {
            create("UICorner", { CornerRadius = self.Tokens.Corner.Pill })
        })
        self:BindThemeProperty(winScope, BarFill, "BackgroundColor3", "Accent")

        local SkipBtn = create("TextButton", {
            Size = UDim2.fromOffset(110, 28),
            Position = UDim2.new(0.5, -55, 0.5, 26),
            BackgroundColor3 = self.Theme.SurfaceElevated,
            ZIndex = 51,
            Visible = (cfg.AllowSkipLoading == true),
            Text = "Pular",
            TextColor3 = self.Theme.SubText,
            Font = self.Tokens.Font.Medium,
            TextSize = self.Tokens.TextSize.Small,
            Parent = LoadingOverlay
        }, {
            create("UICorner", { CornerRadius = self.Tokens.Corner.Control }),
            create("UIStroke", { Color = self.Theme.Border, Thickness = 1 })
        })

        local overlayClosed = false
        local function closeLoadingOverlay()
            if overlayClosed or not LoadingOverlay or not LoadingOverlay.Parent then return end
            overlayClosed = true
            local tw = self:Animate(LoadingOverlay, self.Tokens.Anim.Normal, { BackgroundTransparency = 1 })
            for _, desc in ipairs(LoadingOverlay:GetDescendants()) do
                if desc:IsA("TextLabel") or desc:IsA("TextButton") then
                    self:Animate(desc, self.Tokens.Anim.Fast, { TextTransparency = 1, BackgroundTransparency = 1 })
                elseif desc:IsA("Frame") then
                    self:Animate(desc, self.Tokens.Anim.Fast, { BackgroundTransparency = 1 })
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
                    local ok = safeCall("InitTask:" .. taskName, taskFn)
                    if not ok then
                        LoadStatus.Text = "Falha em '" .. taskName .. "'. Clique para continuar."
                        LoadStatus.TextColor3 = self.Theme.Error
                        SkipBtn.Text = "Continuar"
                        SkipBtn.Visible = true
                        return
                    end
                    local ratio = math.clamp(idx / total, 0, 1)
                    self:Animate(BarFill, self.Tokens.Anim.Fast, { Size = UDim2.fromScale(ratio, 1) })
                end
                closeLoadingOverlay()
            elseif type(initTasks) == "function" then
                BarFill.Size = UDim2.fromScale(0.35, 1)
                local pulseRunning = true
                task.spawn(function()
                    while pulseRunning and not overlayClosed and not Window._destroyed do
                        local t1 = self:Animate(BarFill, 0.5, { Position = UDim2.fromScale(0.65, 0) })
                        if t1 then t1.Completed:Wait() else task.wait(0.2) end
                        local t2 = self:Animate(BarFill, 0.5, { Position = UDim2.fromScale(0, 0) })
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
                    LoadStatus.Text = "Erro na inicialização. Clique para abrir."
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

    -- Entrada Inicial da Janela
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
    -- 7. CRIAÇÃO DE ABAS, CÁLCULO EXATO DE COLUNAS E CONTROLES
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
            Size = UDim2.new(1, 0, 0, 34),
            BackgroundColor3 = Royalty.Theme.Surface,
            BackgroundTransparency = 1,
            AutoButtonColor = false,
            Text = "",
            Parent = TabList
        }, {
            create("UICorner", { CornerRadius = Royalty.Tokens.Corner.Control })
        })
        Royalty:BindThemeProperty(tabScope, TabBtn, "BackgroundColor3", "Surface")

        local ActiveBar = create("Frame", {
            Size = UDim2.fromOffset(3, 0),
            Position = UDim2.new(0, 0, 0.5, 0),
            AnchorPoint = Vector2.new(0, 0.5),
            BackgroundColor3 = Royalty.Theme.Accent,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Parent = TabBtn
        }, {
            create("UICorner", { CornerRadius = Royalty.Tokens.Corner.Pill })
        })
        Royalty:BindThemeProperty(tabScope, ActiveBar, "BackgroundColor3", "Accent")

        local TabTitle = create("TextLabel", {
            Size = UDim2.new(1, -24, 1, 0),
            Position = UDim2.fromOffset(14, 0),
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
                PaddingBottom = UDim.new(0, 18),
                PaddingLeft = UDim.new(0, 16),
                PaddingRight = UDim.new(0, 20)
            })
        })
        Royalty:BindThemeProperty(tabScope, PageScroll, "ScrollBarImageColor3", "Border")

        local ColumnsContainer = create("Frame", {
            Name = "ColumnsContainer",
            Size = UDim2.new(1, 0, 0, 0),
            BackgroundTransparency = 1,
            Parent = PageScroll
        })

        local LeftColumn = create("Frame", {
            Name = "LeftColumn",
            Size = UDim2.new(1, 0, 0, 0),
            Position = UDim2.fromOffset(0, 0),
            BackgroundTransparency = 1,
            Parent = ColumnsContainer
        })
        local LeftLayout = create("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 12),
            Parent = LeftColumn
        })

        local RightColumn = create("Frame", {
            Name = "RightColumn",
            Size = UDim2.new(1, 0, 0, 0),
            Position = UDim2.fromOffset(0, 0),
            BackgroundTransparency = 1,
            Parent = ColumnsContainer
        })
        local RightLayout = create("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 12),
            Parent = RightColumn
        })

        -- Cálculo determinístico de colunas e CanvasSize (nunca corta embaixo nem ultrapassa a direita)
        function Tab:_updateColumns()
            local rawScrollW = PageScroll.AbsoluteSize.X
            local innerW = math.max(220, rawScrollW - 36)

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

            local leftH = hasLeft and LeftLayout.AbsoluteContentSize.Y or 0
            local rightH = hasRight and RightLayout.AbsoluteContentSize.Y or 0

            -- Usa duas colunas somente se a aba não for forçada a 1 coluna, tiver os dois lados e houver espaço amplo (>= 520px internos)
            local useTwoColumns = (not self.ForceSingleColumn) and hasLeft and hasRight and (innerW >= 520)

            if useTwoColumns then
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
                PageScroll.CanvasSize = UDim2.fromOffset(0, totalH + 36)
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
                PageScroll.CanvasSize = UDim2.fromOffset(0, totalH + 36)
            end
        end

        tabScope:Connect(PageScroll:GetPropertyChangedSignal("AbsoluteSize"), function()
            Tab:_updateColumns()
        end)
        tabScope:Connect(LeftLayout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
            Tab:_updateColumns()
        end)
        tabScope:Connect(RightLayout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
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
                Royalty:Animate(other.Btn, Royalty.Tokens.Anim.Fast, { BackgroundTransparency = 1 })
                Royalty:Animate(other.Title, Royalty.Tokens.Anim.Fast, { TextColor3 = Royalty.Theme.SubText })
                Royalty:Animate(other.ActiveBar, Royalty.Tokens.Anim.Fast, {
                    Size = UDim2.fromOffset(3, 0),
                    BackgroundTransparency = 1
                })
            end

            self.Active = true
            Window.ActiveTab = self
            ActivePageTitle.Text = self.Name

            TabTitle.Font = Royalty.Tokens.Font.Semibold
            Royalty:Animate(TabBtn, Royalty.Tokens.Anim.Fast, { BackgroundTransparency = 0 })
            Royalty:Animate(TabTitle, Royalty.Tokens.Anim.Fast, { TextColor3 = Royalty.Theme.Text })
            Royalty:Animate(ActiveBar, Royalty.Tokens.Anim.Normal, {
                Size = UDim2.fromOffset(3, 18),
                BackgroundTransparency = 0
            })

            PageScroll.Visible = true
            applySearchFilter()
            self:_updateColumns()

            if not Royalty.ReducedMotion then
                ColumnsContainer.Position = UDim2.fromOffset(0, 6)
                Royalty:Animate(ColumnsContainer, Royalty.Tokens.Anim.Fast, {
                    Position = UDim2.fromOffset(0, 0)
                })
            else
                ColumnsContainer.Position = UDim2.fromOffset(0, 0)
            end
        end

        tabScope:Connect(TabBtn.MouseEnter, function()
            if not Tab.Active then
                Royalty:Animate(TabBtn, Royalty.Tokens.Anim.Fast, { BackgroundTransparency = 0.5 })
            end
        end)
        tabScope:Connect(TabBtn.MouseLeave, function()
            if not Tab.Active then
                Royalty:Animate(TabBtn, Royalty.Tokens.Anim.Fast, { BackgroundTransparency = 1 })
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
            sectionName = tostring(sectionName or "Seção")
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
                Size = UDim2.new(1, 0, 0, 44),
                BackgroundColor3 = Royalty.Theme.Surface,
                ClipsDescendants = true,
                Parent = parentColumn
            }, {
                create("UICorner", { CornerRadius = Royalty.Tokens.Corner.Section }),
                create("UIPadding", {
                    PaddingTop = UDim.new(0, 12),
                    PaddingBottom = UDim.new(0, 12),
                    PaddingLeft = UDim.new(0, 14),
                    PaddingRight = UDim.new(0, 14)
                })
            })
            Royalty:BindThemeProperty(secScope, SecFrame, "BackgroundColor3", "Surface")

            local SecLayout = create("UIListLayout", {
                SortOrder = Enum.SortOrder.LayoutOrder,
                Padding = UDim.new(0, 10),
                Parent = SecFrame
            })

            local SecStroke = create("UIStroke", {
                Color = Royalty.Theme.BorderSubtle,
                Thickness = 1,
                Parent = SecFrame
            })
            Royalty:BindThemeProperty(secScope, SecStroke, "Color", "BorderSubtle")

            local HeaderHolder = create("Frame", {
                LayoutOrder = 0,
                Size = UDim2.new(1, 0, 0, 22),
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

            function Section:_updateHeight()
                if not SecFrame or not SecFrame.Parent then return end
                local contentH = SecLayout.AbsoluteContentSize.Y
                SecFrame.Size = UDim2.new(1, 0, 0, contentH + 24)
                Tab:_updateColumns()
            end

            secScope:Connect(SecLayout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
                Section:_updateHeight()
            end)

            Section.Frame = SecFrame
            table.insert(Tab.Sections, Section)
            Section:_updateHeight()

            local itemOrder = 0
            local function registerSectionItem(inst: Instance, searchLabel: string)
                itemOrder += 1
                (inst :: any).LayoutOrder = itemOrder
                table.insert(Section.Items, {
                    Instance = inst,
                    SearchText = searchLabel
                })
                Section:_updateHeight()
            end

            -- ----------------------------------------------------------------
            -- 1. LABEL
            -- ----------------------------------------------------------------
            function Section:AddLabel(textOrCfg: string | { Text: string?, Description: string? })
                local ctrlScope = secScope:NewChild()
                local mainText = type(textOrCfg) == "table" and tostring(textOrCfg.Text or "") or tostring(textOrCfg or "")
                local descText = type(textOrCfg) == "table" and textOrCfg.Description and tostring(textOrCfg.Description) or nil

                local Holder = create("Frame", {
                    Size = UDim2.new(1, 0, 0, 20),
                    AutomaticSize = Enum.AutomaticSize.Y,
                    BackgroundTransparency = 1,
                    Parent = SecFrame
                }, {
                    create("UIListLayout", {
                        SortOrder = Enum.SortOrder.LayoutOrder,
                        Padding = UDim.new(0, 2)
                    })
                })

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
                    local DescLbl = create("TextLabel", {
                        LayoutOrder = 2,
                        Size = UDim2.new(1, 0, 0, 16),
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

                registerSectionItem(Holder, mainText .. " " .. (descText or ""))

                local LabelObj = {}
                function LabelObj:Set(newText: string)
                    mainText = tostring(newText or "")
                    Lbl.Text = mainText
                    Section:_updateHeight()
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
                local bName = tostring(bCfg.Name or "Botão")
                local bDesc = bCfg.Description and tostring(bCfg.Description) or nil
                local disabled = (bCfg.Disabled == true)
                local loading = false
                local callback = bCfg.Callback

                local hasDesc = (bDesc ~= nil and bDesc ~= "")

                local BtnFrame = create("TextButton", {
                    Size = UDim2.new(1, 0, 0, hasDesc and 48 or 34),
                    BackgroundColor3 = Royalty.Theme.SurfaceElevated,
                    AutoButtonColor = false,
                    Text = "",
                    Parent = SecFrame
                }, {
                    create("UICorner", { CornerRadius = Royalty.Tokens.Corner.Control }),
                    create("UIPadding", {
                        PaddingLeft = UDim.new(0, 12),
                        PaddingRight = UDim.new(0, 12)
                    })
                })

                local BtnStroke = create("UIStroke", {
                    Color = Royalty.Theme.Border,
                    Thickness = 1,
                    Parent = BtnFrame
                })
                Royalty:BindThemeProperty(ctrlScope, BtnStroke, "Color", "Border")

                local TitleLbl = create("TextLabel", {
                    Size = UDim2.new(1, -24, 0, 18),
                    Position = hasDesc and UDim2.fromOffset(0, 7) or UDim2.new(0, 0, 0.5, -9),
                    BackgroundTransparency = 1,
                    Text = bName,
                    TextColor3 = disabled and Royalty.Theme.Muted or Royalty.Theme.Text,
                    Font = Royalty.Tokens.Font.Medium,
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

                -- Indicador geométrico discreto à direita (sem caracteres Unicode quebrados)
                local RightDot = create("Frame", {
                    Size = UDim2.fromOffset(6, 6),
                    Position = UDim2.new(1, -6, 0.5, -3),
                    BackgroundColor3 = Royalty.Theme.SubText,
                    BorderSizePixel = 0,
                    Parent = BtnFrame
                }, {
                    create("UICorner", { CornerRadius = Royalty.Tokens.Corner.Pill })
                })

                registerSectionItem(BtnFrame, bName .. " " .. (bDesc or ""))

                local hovered = false
                local function refreshVisual()
                    local targetBg = (hovered and not disabled and not loading) and Royalty.Theme.SurfaceHover or Royalty.Theme.SurfaceElevated
                    local targetText = (disabled or loading) and Royalty.Theme.Muted or Royalty.Theme.Text
                    local targetDot = loading and Royalty.Theme.Accent or (hovered and not disabled and Royalty.Theme.Accent or Royalty.Theme.Muted)
                    Royalty:Animate(BtnFrame, Royalty.Tokens.Anim.Fast, { BackgroundColor3 = targetBg })
                    Royalty:Animate(TitleLbl, Royalty.Tokens.Anim.Fast, { TextColor3 = targetText })
                    Royalty:Animate(RightDot, Royalty.Tokens.Anim.Fast, { BackgroundColor3 = targetDot })
                end

                Royalty:OnThemeChanged(ctrlScope, refreshVisual)

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
                            Royalty:Animate(BtnStroke, Royalty.Tokens.Anim.Fast, { Color = Royalty.Theme.Border })
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
                        Size = UDim2.new(1, -54, 0, 16),
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
                }, {
                    create("UICorner", { CornerRadius = Royalty.Tokens.Corner.Pill })
                })

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
                }, {
                    create("UICorner", { CornerRadius = Royalty.Tokens.Corner.Pill })
                })

                registerSectionItem(RowBtn, tName .. " " .. (tDesc or ""))

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
            -- 5. SLIDER (COM RECUO DE TRILHO PARA NUNCA TRANSBORDAR À DIREITA)
            -- ----------------------------------------------------------------
            function Section:AddSlider(sCfg: { Name: string?, Description: string?, Min: number?, Max: number?, Default: number?, Rounding: number?, Suffix: string?, CallbackOnRelease: boolean?, Flag: string?, Callback: ((val: number) -> ())? }?)
                sCfg = sCfg or {}
                local ctrlScope = secScope:NewChild()
                local sName = tostring(sCfg.Name or "Ajuste")
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

                local hasDesc = (sDesc ~= nil and sDesc ~= "")

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
                    Size = UDim2.new(1, 0, 0, hasDesc and 56 or 38),
                    BackgroundTransparency = 1,
                    Parent = SecFrame
                })

                local TopRow = create("Frame", {
                    Size = UDim2.new(1, 0, 0, 18),
                    BackgroundTransparency = 1,
                    Parent = Container
                })

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

                -- Recuo de 6px em cada lado para que a bolinha (12px) nunca saia da seção
                local Track = create("Frame", {
                    Size = UDim2.new(1, -12, 0, 6),
                    Position = UDim2.new(0, 6, 0.5, -3),
                    BackgroundColor3 = Royalty.Theme.SurfaceElevated,
                    BorderSizePixel = 0,
                    Parent = TrackHitbox
                }, {
                    create("UICorner", { CornerRadius = Royalty.Tokens.Corner.Pill })
                })
                Royalty:BindThemeProperty(ctrlScope, Track, "BackgroundColor3", "SurfaceElevated")

                local TrackStroke = create("UIStroke", {
                    Color = Royalty.Theme.Border,
                    Thickness = 1,
                    Parent = Track
                })
                Royalty:BindThemeProperty(ctrlScope, TrackStroke, "Color", "Border")

                local Fill = create("Frame", {
                    Size = UDim2.fromScale(0, 1),
                    BackgroundColor3 = Royalty.Theme.Accent,
                    BorderSizePixel = 0,
                    Parent = Track
                }, {
                    create("UICorner", { CornerRadius = Royalty.Tokens.Corner.Pill })
                })
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

                registerSectionItem(Container, sName .. " " .. (sDesc or ""))

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
            -- 6. DROPDOWN (COM CHEVRON E CHECKBOX GEOMÉTRICOS PUROS)
            -- ----------------------------------------------------------------
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
                    for _, item in ipairs(dCfg.Options) do
                        table.insert(cleanOptions, tostring(item))
                    end
                end

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
                    Size = UDim2.new(1, 0, 0, 52),
                    BackgroundTransparency = 1,
                    Parent = SecFrame
                })
                local WrapperLayout = create("UIListLayout", {
                    SortOrder = Enum.SortOrder.LayoutOrder,
                    Padding = UDim.new(0, 5),
                    Parent = Wrapper
                })

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
                }, {
                    create("UICorner", { CornerRadius = Royalty.Tokens.Corner.Control })
                })
                Royalty:BindThemeProperty(ctrlScope, HeaderBtn, "BackgroundColor3", "SurfaceElevated")

                local HeaderStroke = create("UIStroke", {
                    Color = Royalty.Theme.Border,
                    Thickness = 1,
                    Parent = HeaderBtn
                })
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
                Royalty:OnThemeChanged(ctrlScope, function(theme)
                    setChevronColor(theme.SubText)
                end)

                local DropdownPanel = create("Frame", {
                    LayoutOrder = 4,
                    Size = UDim2.new(1, 0, 0, 120),
                    BackgroundColor3 = Royalty.Theme.Sidebar,
                    Visible = false,
                    Parent = Wrapper
                }, {
                    create("UICorner", { CornerRadius = Royalty.Tokens.Corner.Control }),
                    create("UIPadding", {
                        PaddingTop = UDim.new(0, 6),
                        PaddingBottom = UDim.new(0, 6),
                        PaddingLeft = UDim.new(0, 6),
                        PaddingRight = UDim.new(0, 6)
                    })
                })
                Royalty:BindThemeProperty(ctrlScope, DropdownPanel, "BackgroundColor3", "Sidebar")

                local PanelLayout = create("UIListLayout", {
                    SortOrder = Enum.SortOrder.LayoutOrder,
                    Padding = UDim.new(0, 4),
                    Parent = DropdownPanel
                })

                local PanelStroke = create("UIStroke", {
                    Color = Royalty.Theme.Border,
                    Thickness = 1,
                    Parent = DropdownPanel
                })
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

                local OptionsListLayout = create("UIListLayout", {
                    SortOrder = Enum.SortOrder.LayoutOrder,
                    Padding = UDim.new(0, 2),
                    Parent = OptionsScroll
                })

                local function syncWrapperHeight()
                    DropdownPanel.Size = UDim2.new(1, 0, 0, PanelLayout.AbsoluteContentSize.Y + 12)
                    Wrapper.Size = UDim2.new(1, 0, 0, WrapperLayout.AbsoluteContentSize.Y)
                    Section:_updateHeight()
                end

                ctrlScope:Connect(WrapperLayout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
                    Wrapper.Size = UDim2.new(1, 0, 0, WrapperLayout.AbsoluteContentSize.Y)
                    Section:_updateHeight()
                end)

                registerSectionItem(Wrapper, dName .. " " .. (dDesc or ""))

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
                        SelectedLbl.Text = (#list > 0) and table.concat(list, ", ") or "Nenhum"
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
                                Size = UDim2.new(1, -4, 0, 28),
                                BackgroundColor3 = isSelected and Royalty.Theme.SurfaceElevated or Royalty.Theme.Sidebar,
                                BackgroundTransparency = isSelected and 0 or 1,
                                AutoButtonColor = false,
                                Text = "",
                                Parent = OptionsScroll
                            }, {
                                create("UICorner", { CornerRadius = UDim.new(0, 4) })
                            })

                            create("TextLabel", {
                                Size = UDim2.new(1, -30, 1, 0),
                                Position = UDim2.fromOffset(8, 0),
                                BackgroundTransparency = 1,
                                Text = opt,
                                TextColor3 = isSelected and Royalty.Theme.Text or Royalty.Theme.SubText,
                                Font = isSelected and Royalty.Tokens.Font.Semibold or Royalty.Tokens.Font.Regular,
                                TextSize = Royalty.Tokens.TextSize.Description,
                                TextTruncate = Enum.TextTruncate.AtEnd,
                                TextXAlignment = Enum.TextXAlignment.Left,
                                Parent = OptBtn
                            })

                            -- Indicador geométrico puro de item selecionado (sem glifos Unicode)
                            local CheckBox = create("Frame", {
                                Size = UDim2.fromOffset(12, 12),
                                Position = UDim2.new(1, -18, 0.5, -6),
                                BackgroundColor3 = isSelected and Royalty.Theme.Accent or Royalty.Theme.Surface,
                                BorderSizePixel = 0,
                                Parent = OptBtn
                            }, {
                                create("UICorner", { CornerRadius = isMulti and UDim.new(0, 3) or Royalty.Tokens.Corner.Pill }),
                                create("UIStroke", {
                                    Color = isSelected and Royalty.Theme.Accent or Royalty.Theme.Border,
                                    Thickness = 1
                                })
                            })

                            if isSelected then
                                create("Frame", {
                                    Size = UDim2.fromOffset(6, 6),
                                    Position = UDim2.fromScale(0.5, 0.5),
                                    AnchorPoint = Vector2.new(0.5, 0.5),
                                    BackgroundColor3 = Color3.fromRGB(255, 255, 255),
                                    BorderSizePixel = 0,
                                    Parent = CheckBox
                                }, {
                                    create("UICorner", { CornerRadius = Royalty.Tokens.Corner.Pill })
                                })
                            end

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
                                    setChevronOpen(false)
                                    syncWrapperHeight()
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
                        OptionsScroll.CanvasSize = UDim2.fromOffset(0, 28)
                    else
                        local contentH = visibleCount * 30
                        local targetH = math.min(contentH, 136)
                        OptionsScroll.Size = UDim2.new(1, 0, 0, targetH)
                        OptionsScroll.CanvasSize = UDim2.fromOffset(0, contentH)
                    end
                    syncWrapperHeight()
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
                    setChevronOpen(DropObj.Open)
                    if DropObj.Open then
                        rebuildOptionButtons()
                    else
                        syncWrapperHeight()
                    end
                end)

                updateHeaderText()
                rebuildOptionButtons()
                return DropObj
            end

            -- ----------------------------------------------------------------
            -- 7. KEYBIND (VISUAL LIMPO E FOCO DE TEXTO RESPEITADO)
            -- ----------------------------------------------------------------
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
                local KeyObj = {
                    Key = currentKey,
                    Mode = currentMode,
                    Active = false,
                    Binding = false
                }
                Window._controlsByFlag[flag] = KeyObj

                local Row = create("Frame", {
                    Size = UDim2.new(1, 0, 0, hasDesc and 42 or 26),
                    BackgroundTransparency = 1,
                    Parent = SecFrame
                })

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

                registerSectionItem(Row, kName .. " " .. (kDesc or ""))

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
                end

                function KeyObj:GetMode(): string
                    return self.Mode
                end

                ctrlScope:Connect(KeyBtn.Activated, function()
                    KeyObj.Binding = true
                    Window._isBindingKey = true
                    KeyBtn.Text = "[ ... ]"
                    Royalty:Animate(KeyStroke, Royalty.Tokens.Anim.Fast, { Color = Royalty.Theme.Accent })
                end)

                ctrlScope:Connect(UserInputService.InputBegan, function(input, gameProcessed)
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
            -- 8. COLOR PICKER (HSV PRECISO + BARRAS RECUADAS SEM OVERFLOW)
            -- ----------------------------------------------------------------
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
                local ColorObj = {
                    Value = currentColor,
                    Open = false
                }
                Window._controlsByFlag[flag] = ColorObj

                local Wrapper = create("Frame", {
                    Size = UDim2.new(1, 0, 0, 26),
                    BackgroundTransparency = 1,
                    Parent = SecFrame
                })
                local WrapperLayout = create("UIListLayout", {
                    SortOrder = Enum.SortOrder.LayoutOrder,
                    Padding = UDim.new(0, 6),
                    Parent = Wrapper
                })

                local TopRow = create("TextButton", {
                    LayoutOrder = 1,
                    Size = UDim2.new(1, 0, 0, 26),
                    BackgroundTransparency = 1,
                    AutoButtonColor = false,
                    Text = "",
                    Parent = Wrapper
                })

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
                    create("UIPadding", {
                        PaddingTop = UDim.new(0, 10),
                        PaddingBottom = UDim.new(0, 10),
                        PaddingLeft = UDim.new(0, 10),
                        PaddingRight = UDim.new(0, 10)
                    }),
                    create("UIListLayout", {
                        SortOrder = Enum.SortOrder.LayoutOrder,
                        Padding = UDim.new(0, 8)
                    })
                })
                Royalty:BindThemeProperty(ctrlScope, PickerPanel, "BackgroundColor3", "Sidebar")

                ctrlScope:Connect(WrapperLayout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
                    Wrapper.Size = UDim2.new(1, 0, 0, WrapperLayout.AbsoluteContentSize.Y)
                    Section:_updateHeight()
                end)

                registerSectionItem(Wrapper, cName .. " " .. (cDesc or ""))

                local function createHSVBar(order: number, labelText: string)
                    local row = create("Frame", {
                        LayoutOrder = order,
                        Size = UDim2.new(1, 0, 0, 18),
                        BackgroundTransparency = 1,
                        Parent = PickerPanel
                    })
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

                    -- Recuo de 4px à direita para o cursor nunca ultrapassar a caixa
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

                local BottomRow = create("Frame", {
                    LayoutOrder = 4,
                    Size = UDim2.new(1, 0, 0, 24),
                    BackgroundTransparency = 1,
                    Parent = PickerPanel
                })

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

                    SatGrad.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), pureHue)
                    ValGrad.Color = ColorSequence.new(Color3.fromRGB(0, 0, 0), fullValColor)

                    HueCursor.Position = UDim2.fromScale(math.clamp(h, 0, 1), 0.5)
                    SatCursor.Position = UDim2.fromScale(math.clamp(s, 0, 1), 0.5)
                    ValCursor.Position = UDim2.fromScale(math.clamp(v, 0, 1), 0.5)

                    local c = ColorObj.Value
                    SwatchBtn.BackgroundColor3 = c
                    RGBLabel.Text = string.format(
                        "RGB: %d, %d, %d",
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
                    Wrapper.Size = UDim2.new(1, 0, 0, WrapperLayout.AbsoluteContentSize.Y)
                    Section:_updateHeight()
                end)

                syncPickerVisuals()
                return ColorObj
            end

            -- ----------------------------------------------------------------
            -- 9. INPUT (TEXTBOX)
            -- ----------------------------------------------------------------
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
                if maxLen and #currentText > maxLen then
                    currentText = string.sub(currentText, 1, maxLen)
                end

                Royalty.Flags[flag] = currentText
                local InputObj = { Value = currentText }
                Window._controlsByFlag[flag] = InputObj

                local Container = create("Frame", {
                    Size = UDim2.new(1, 0, 0, hasDesc and 70 or 52),
                    BackgroundTransparency = 1,
                    Parent = SecFrame
                })

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
                }, {
                    create("UICorner", { CornerRadius = Royalty.Tokens.Corner.Control })
                })
                Royalty:BindThemeProperty(ctrlScope, BoxHolder, "BackgroundColor3", "SurfaceElevated")

                local BoxStroke = create("UIStroke", {
                    Color = Royalty.Theme.Border,
                    Thickness = 1,
                    Parent = BoxHolder
                })
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

                registerSectionItem(Container, iName .. " " .. (iDesc or ""))

                function InputObj:Set(newText: string, silent: boolean?)
                    local str = tostring(newText or "")
                    if maxLen and #str > maxLen then
                        str = string.sub(str, 1, maxLen)
                    end
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
                    Royalty:Animate(BoxStroke, Royalty.Tokens.Anim.Fast, { Color = Royalty.Theme.Accent })
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
                    Royalty:Animate(BoxStroke, Royalty.Tokens.Anim.Fast, { Color = Royalty.Theme.Border })
                    InputObj:Set(Box.Text)
                end)

                return InputObj
            end

            return Section
        end

        return Tab
    end

    -- ========================================================================
    -- 8. ABA DE CONFIGURAÇÕES (COLUNA ÚNICA AMPLA + ROLAGEM COMPLETA)
    -- ========================================================================
    function Window:AddSettingsTab(tabTitle: string?)
        -- Usa ForceSingleColumn = true para nunca espremer controles nas configurações
        local SettingsTab = self:AddTab(tabTitle or "Configurações", true)
        local AppearanceSec = SettingsTab:AddSection("Aparência e Tema", "Left")
        local SystemSec = SettingsTab:AddSection("Interface e Perfis", "Left")

        AppearanceSec:AddDropdown({
            Name = "Tema da Interface",
            Options = { "Escuro", "Claro" },
            Default = (Royalty.Theme.Name == "Claro") and "Claro" or "Escuro",
            Flag = "Royalty_ThemeMode",
            Callback = function(selected)
                Royalty:SetTheme(selected)
            end
        })

        local AccentPicker = AppearanceSec:AddColorPicker({
            Name = "Cor de Destaque",
            Default = Royalty.Theme.Accent,
            Flag = "Royalty_AccentColor",
            Callback = function(color)
                Royalty:SetAccentColor(color)
            end
        })

        AppearanceSec:AddDropdown({
            Name = "Predefinição de Cor",
            Options = { "Azul Royalty", "Esmeralda", "Âmbar", "Carmesim", "Violeta" },
            Default = "Azul Royalty",
            Flag = "Royalty_AccentPreset",
            Callback = function(preset)
                local map = {
                    ["Azul Royalty"] = Color3.fromRGB(88, 124, 244),
                    ["Esmeralda"] = Color3.fromRGB(48, 194, 118),
                    ["Âmbar"] = Color3.fromRGB(242, 164, 36),
                    ["Carmesim"] = Color3.fromRGB(236, 82, 78),
                    ["Violeta"] = Color3.fromRGB(152, 104, 252)
                }
                if map[preset] then
                    AccentPicker:Set(map[preset])
                end
            end
        })

        AppearanceSec:AddToggle({
            Name = "Desfoque de Fundo (Blur)",
            Description = "Desfoca e escurece o cenário enquanto o menu estiver aberto.",
            Default = self.UseBlur,
            Flag = "Royalty_UseBlur",
            CallOnInit = false,
            Callback = function(state)
                self.UseBlur = state
                Royalty:_syncBlur()
            end
        })

        AppearanceSec:AddToggle({
            Name = "Movimento Reduzido",
            Default = Royalty.ReducedMotion,
            Flag = "Royalty_ReducedMotion",
            CallOnInit = false,
            Callback = function(state)
                Royalty:SetReducedMotion(state)
            end
        })

        SystemSec:AddSlider({
            Name = "Escala da Janela",
            Min = 0.80,
            Max = 1.20,
            Default = self.Scale,
            Rounding = 2,
            Suffix = "x",
            Flag = "Royalty_UIScale",
            Callback = function(scaleVal)
                self:SetScale(scaleVal)
            end
        })

        SystemSec:AddKeybind({
            Name = "Atalho para Ocultar Menu",
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
            Placeholder = "Padrao",
            Default = "Padrao",
            MaxLength = 24,
            Flag = "Royalty_ProfileName"
        })

        SystemSec:AddButton({
            Name = "Salvar Configuração",
            Callback = function()
                local ok, msg = Royalty:SaveConfiguration(profileInput:Get())
                Royalty:Notify({
                    Title = "Configurações",
                    Content = msg,
                    Type = ok and "Sucesso" or "Erro",
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
                    Type = ok and "Sucesso" or "Aviso",
                    Duration = 3
                })
            end
        })

        SystemSec:AddButton({
            Name = "Encerrar Interface",
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
