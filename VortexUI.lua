local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

local Library = {
    Flags = {},
    Theme = {
        Accent = Color3.fromRGB(110, 135, 255),
        Background = Color3.fromRGB(14, 15, 20),
        Sidebar = Color3.fromRGB(18, 19, 26),
        Card = Color3.fromRGB(22, 24, 33),
        CardHover = Color3.fromRGB(28, 31, 42),
        Stroke = Color3.fromRGB(45, 49, 66),
        Text = Color3.fromRGB(240, 242, 248),
        SubText = Color3.fromRGB(145, 150, 168),
        Muted = Color3.fromRGB(90, 95, 112)
    },
    AccentObjects = {},
    Connections = {},
    OpenFrames = {},
    Unloaded = false
}

local function resolveParent()
    local ok, hui = pcall(function()
        return gethui and gethui()
    end)
    if ok and hui then return hui end

    local okCore, core = pcall(function()
        return game:GetService("CoreGui")
    end)
    if okCore and core then
        local test = pcall(function()
            local f = Instance.new("Folder")
            f.Parent = core
            f:Destroy()
        end)
        if test then return core end
    end

    return LocalPlayer:WaitForChild("PlayerGui")
end

local function create(className, props, children)
    local inst = Instance.new(className)
    for k, v in pairs(props or {}) do
        inst[k] = v
    end
    for _, child in ipairs(children or {}) do
        child.Parent = inst
    end
    return inst
end

local function tween(obj, duration, props, style, dir)
    local t = TweenService:Create(
        obj,
        TweenInfo.new(duration or 0.18, style or Enum.EasingStyle.Quart, dir or Enum.EasingDirection.Out),
        props
    )
    t:Play()
    return t
end

function Library:RegisterAccent(instance, property, alpha)
    table.insert(self.AccentObjects, {
        Instance = instance,
        Property = property,
        Alpha = alpha
    })
    instance[property] = self.Theme.Accent
end

function Library:SetAccentColor(newColor)
    self.Theme.Accent = newColor
    for i = #self.AccentObjects, 1, -1 do
        local item = self.AccentObjects[i]
        if item.Instance and item.Instance.Parent then
            tween(item.Instance, 0.15, { [item.Property] = newColor })
        else
            table.remove(self.AccentObjects, i)
        end
    end
end

local function formatKeyName(keyEnum)
    if not keyEnum then return "NONE" end
    local name = keyEnum.Name
    local map = {
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
        PageDown = "PgDn"
    }
    return map[name] or name
end

local function makeDraggable(topBar, mainFrame)
    local dragging = false
    local dragStart, startPos

    topBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = mainFrame.Position
        end
    end)

    topBar.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)

    table.insert(Library.Connections, UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            tween(mainFrame, 0.06, {
                Position = UDim2.new(
                    startPos.X.Scale,
                    startPos.X.Offset + delta.X,
                    startPos.Y.Scale,
                    startPos.Y.Offset + delta.Y
                )
            })
        end
    end))
end

local parentContainer = resolveParent()
for _, old in ipairs(parentContainer:GetChildren()) do
    if old.Name == "VortexGlassUI" then
        old:Destroy()
    end
end
if Lighting:FindFirstChild("VortexGlassBlur") then
    Lighting.VortexGlassBlur:Destroy()
end

local ScreenGui = create("ScreenGui", {
    Name = "VortexGlassUI",
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    IgnoreGuiInset = true,
    Parent = parentContainer
})

local Blur = create("BlurEffect", {
    Name = "VortexGlassBlur",
    Size = 0,
    Enabled = true,
    Parent = Lighting
})

local NotifHolder = create("Frame", {
    Name = "Notifications",
    Size = UDim2.new(0, 260, 1, -30),
    Position = UDim2.new(1, -275, 0, 15),
    BackgroundTransparency = 1,
    Parent = ScreenGui
}, {
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        VerticalAlignment = Enum.VerticalAlignment.Bottom,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        Padding = UDim.new(0, 8)
    })
})

function Library:Notify(cfg)
    cfg = cfg or {}
    local title = cfg.Title or "Notification"
    local content = cfg.Content or ""
    local duration = cfg.Duration or 4

    local card = create("Frame", {
        Size = UDim2.new(1, 0, 0, 58),
        Position = UDim2.new(1, 300, 0, 0),
        BackgroundColor3 = self.Theme.Background,
        BackgroundTransparency = 0.1,
        ClipsDescendants = true,
        Parent = NotifHolder
    }, {
        create("UICorner", { CornerRadius = UDim.new(0, 8) }),
        create("UIStroke", {
            Color = self.Theme.Stroke,
            Transparency = 0.25,
            Thickness = 1
        }),
        create("TextLabel", {
            Size = UDim2.new(1, -24, 0, 18),
            Position = UDim2.new(0, 12, 0, 8),
            BackgroundTransparency = 1,
            Text = title,
            TextColor3 = self.Theme.Text,
            Font = Enum.Font.GothamBold,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left
        }),
        create("TextLabel", {
            Size = UDim2.new(1, -24, 0, 22),
            Position = UDim2.new(0, 12, 0, 26),
            BackgroundTransparency = 1,
            Text = content,
            TextColor3 = self.Theme.SubText,
            Font = Enum.Font.Gotham,
            TextSize = 11,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top
        })
    })

    local bar = create("Frame", {
        Size = UDim2.new(1, 0, 0, 2),
        Position = UDim2.new(0, 0, 1, -2),
        BorderSizePixel = 0,
        Parent = card
    })
    self:RegisterAccent(bar, "BackgroundColor3")

    tween(card, 0.35, { BackgroundTransparency = 0.08 })
    tween(bar, duration, { Size = UDim2.new(0, 0, 0, 2) }, Enum.EasingStyle.Linear)

    task.delay(duration, function()
        if card and card.Parent then
            local fade = tween(card, 0.25, {
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 0)
            })
            fade.Completed:Wait()
            card:Destroy()
        end
    end)
end

function Library:CreateWindow(cfg)
    cfg = cfg or {}
    local titleText = cfg.Title or "VORTEX"
    local subTitleText = cfg.SubTitle or "build 1.0"
    local windowSize = cfg.Size or UDim2.fromOffset(560, 380)
    local toggleKey = cfg.ToggleKey or Enum.KeyCode.RightShift
    local useBlur = (cfg.Blur ~= false)

    if cfg.Accent then
        self.Theme.Accent = cfg.Accent
    end

    local Window = {
        Tabs = {},
        ActiveTab = nil,
        Visible = true,
        ToggleKey = toggleKey,
        UseBlur = useBlur
    }

    if useBlur then
        tween(Blur, 0.25, { Size = 12 })
    end

    local Main = create("Frame", {
        Name = "MainWindow",
        Size = windowSize,
        Position = UDim2.new(0.5, -windowSize.X.Offset / 2, 0.5, -windowSize.Y.Offset / 2),
        BackgroundColor3 = self.Theme.Background,
        BackgroundTransparency = 0.12,
        ClipsDescendants = true,
        Parent = ScreenGui
    }, {
        create("UICorner", { CornerRadius = UDim.new(0, 10) }),
        create("UIStroke", {
            Color = Color3.fromRGB(255, 255, 255),
            Transparency = 0.84,
            Thickness = 1
        }),
        create("UIGradient", {
            Rotation = 45,
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 185, 210))
            })
        })
    })

    local SpecularLine = create("Frame", {
        Size = UDim2.new(1, -20, 0, 1),
        Position = UDim2.new(0, 10, 0, 0),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BackgroundTransparency = 0.82,
        BorderSizePixel = 0,
        Parent = Main
    }, {
        create("UIGradient", {
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 1),
                NumberSequenceKeypoint.new(0.5, 0),
                NumberSequenceKeypoint.new(1, 1)
            })
        })
    })

    local Sidebar = create("Frame", {
        Name = "Sidebar",
        Size = UDim2.new(0, 150, 1, 0),
        BackgroundColor3 = self.Theme.Sidebar,
        BackgroundTransparency = 0.22,
        BorderSizePixel = 0,
        Parent = Main
    }, {
        create("UICorner", { CornerRadius = UDim.new(0, 10) }),
        create("Frame", {
            Size = UDim2.new(0, 1, 1, 0),
            Position = UDim2.new(1, -1, 0, 0),
            BackgroundColor3 = self.Theme.Stroke,
            BackgroundTransparency = 0.45,
            BorderSizePixel = 0
        })
    })

    local Header = create("Frame", {
        Name = "Header",
        Size = UDim2.new(1, 0, 0, 54),
        BackgroundTransparency = 1,
        Parent = Sidebar
    })

    local AccentDot = create("Frame", {
        Size = UDim2.new(0, 8, 0, 8),
        Position = UDim2.new(0, 16, 0, 20),
        BorderSizePixel = 0,
        Parent = Header
    }, {
        create("UICorner", { CornerRadius = UDim.new(1, 0) })
    })
    self:RegisterAccent(AccentDot, "BackgroundColor3")

    create("TextLabel", {
        Size = UDim2.new(1, -40, 0, 18),
        Position = UDim2.new(0, 30, 0, 14),
        BackgroundTransparency = 1,
        Text = titleText,
        TextColor3 = self.Theme.Text,
        Font = Enum.Font.GothamBold,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = Header
    })

    create("TextLabel", {
        Size = UDim2.new(1, -40, 0, 14),
        Position = UDim2.new(0, 30, 0, 30),
        BackgroundTransparency = 1,
        Text = subTitleText,
        TextColor3 = self.Theme.Muted,
        Font = Enum.Font.GothamMedium,
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = Header
    })

    local TabContainer = create("ScrollingFrame", {
        Name = "TabList",
        Size = UDim2.new(1, -16, 1, -96),
        Position = UDim2.new(0, 8, 0, 56),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 0,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Parent = Sidebar
    }, {
        create("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 4)
        })
    })

    local FooterKeyLabel = create("TextLabel", {
        Size = UDim2.new(1, -24, 0, 24),
        Position = UDim2.new(0, 12, 1, -30),
        BackgroundTransparency = 1,
        Text = "Toggle UI: [" .. formatKeyName(toggleKey) .. "]",
        TextColor3 = self.Theme.Muted,
        Font = Enum.Font.GothamMedium,
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = Sidebar
    })

    local DragArea = create("Frame", {
        Name = "DragBar",
        Size = UDim2.new(1, 0, 0, 42),
        BackgroundTransparency = 1,
        Parent = Main
    })
    makeDraggable(DragArea, Main)

    local PagesFolder = create("Frame", {
        Name = "Pages",
        Size = UDim2.new(1, -162, 1, -16),
        Position = UDim2.new(0, 156, 0, 8),
        BackgroundTransparency = 1,
        Parent = Main
    })

    function Window:SetToggleKey(newKey)
        self.ToggleKey = newKey
        FooterKeyLabel.Text = "Toggle UI: [" .. formatKeyName(newKey) .. "]"
    end

    function Window:Toggle(state)
        if state == nil then
            self.Visible = not self.Visible
        else
            self.Visible = state
        end
        Main.Visible = self.Visible
        if self.UseBlur then
            tween(Blur, 0.2, { Size = self.Visible and 12 or 0 })
        end
    end

    function Window:Destroy()
        Library.Unloaded = true
        for _, c in ipairs(Library.Connections) do
            pcall(function() c:Disconnect() end)
        end
        if Blur and Blur.Parent then Blur:Destroy() end
        if ScreenGui and ScreenGui.Parent then ScreenGui:Destroy() end
    end

    table.insert(self.Connections, UserInputService.InputBegan:Connect(function(input, gp)
        if gp then return end
        if input.KeyCode == Window.ToggleKey then
            Window:Toggle()
        end
    end))

    function Window:AddTab(tabName)
        local Tab = {
            Name = tabName,
            Active = false
        }

        local TabBtn = create("TextButton", {
            Name = tabName,
            Size = UDim2.new(1, 0, 0, 32),
            BackgroundColor3 = Library.Theme.Card,
            BackgroundTransparency = 1,
            AutoButtonColor = false,
            Text = "",
            Parent = TabContainer
        }, {
            create("UICorner", { CornerRadius = UDim.new(0, 6) })
        })

        local Indicator = create("Frame", {
            Size = UDim2.new(0, 3, 0, 0),
            Position = UDim2.new(0, 0, 0.5, 0),
            AnchorPoint = Vector2.new(0, 0.5),
            BorderSizePixel = 0,
            BackgroundTransparency = 1,
            Parent = TabBtn
        }, {
            create("UICorner", { CornerRadius = UDim.new(1, 0) })
        })
        Library:RegisterAccent(Indicator, "BackgroundColor3")

        local TabTitle = create("TextLabel", {
            Size = UDim2.new(1, -24, 1, 0),
            Position = UDim2.new(0, 14, 0, 0),
            BackgroundTransparency = 1,
            Text = tabName,
            TextColor3 = Library.Theme.SubText,
            Font = Enum.Font.GothamMedium,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = TabBtn
        })

        local Page = create("Frame", {
            Name = tabName .. "_Page",
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1,
            Visible = false,
            Parent = PagesFolder
        })

        local LeftCol = create("ScrollingFrame", {
            Name = "LeftColumn",
            Size = UDim2.new(0.5, -5, 1, 0),
            Position = UDim2.new(0, 0, 0, 0),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = 2,
            ScrollBarImageColor3 = Library.Theme.Stroke,
            CanvasSize = UDim2.new(0, 0, 0, 0),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            Parent = Page
        }, {
            create("UIListLayout", {
                SortOrder = Enum.SortOrder.LayoutOrder,
                Padding = UDim.new(0, 8)
            }),
            create("UIPadding", {
                PaddingTop = UDim.new(0, 4),
                PaddingBottom = UDim.new(0, 8),
                PaddingLeft = UDim.new(0, 2),
                PaddingRight = UDim.new(0, 4)
            })
        })

        local RightCol = create("ScrollingFrame", {
            Name = "RightColumn",
            Size = UDim2.new(0.5, -5, 1, 0),
            Position = UDim2.new(0.5, 5, 0, 0),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = 2,
            ScrollBarImageColor3 = Library.Theme.Stroke,
            CanvasSize = UDim2.new(0, 0, 0, 0),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            Parent = Page
        }, {
            create("UIListLayout", {
                SortOrder = Enum.SortOrder.LayoutOrder,
                Padding = UDim.new(0, 8)
            }),
            create("UIPadding", {
                PaddingTop = UDim.new(0, 4),
                PaddingBottom = UDim.new(0, 8),
                PaddingLeft = UDim.new(0, 2),
                PaddingRight = UDim.new(0, 4)
            })
        })

        function Tab:Activate()
            for _, t in ipairs(Window.Tabs) do
                t.Active = false
                t.Page.Visible = false
                tween(t.Btn, 0.18, { BackgroundTransparency = 1 })
                tween(t.Title, 0.18, { TextColor3 = Library.Theme.SubText })
                tween(t.Indicator, 0.18, { Size = UDim2.new(0, 3, 0, 0), BackgroundTransparency = 1 })
            end
            self.Active = true
            Page.Visible = true
            tween(TabBtn, 0.18, { BackgroundTransparency = 0.35 })
            tween(TabTitle, 0.18, { TextColor3 = Library.Theme.Text })
            tween(Indicator, 0.2, { Size = UDim2.new(0, 3, 0, 16), BackgroundTransparency = 0 })
        end

        TabBtn.Activated:Connect(function()
            Tab:Activate()
        end)

        Tab.Btn = TabBtn
        Tab.Title = TabTitle
        Tab.Indicator = Indicator
        Tab.Page = Page
        table.insert(Window.Tabs, Tab)

        if #Window.Tabs == 1 then
            Tab:Activate()
        end

        function Tab:AddSection(sectionName, side)
            local targetCol = (side and tostring(side):lower() == "right") and RightCol or LeftCol
            local Section = {}

            local SecCard = create("Frame", {
                Name = sectionName,
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundColor3 = Library.Theme.Card,
                BackgroundTransparency = 0.28,
                Parent = targetCol
            }, {
                create("UICorner", { CornerRadius = UDim.new(0, 8) }),
                create("UIStroke", {
                    Color = Library.Theme.Stroke,
                    Transparency = 0.4,
                    Thickness = 1
                }),
                create("UIPadding", {
                    PaddingTop = UDim.new(0, 8),
                    PaddingBottom = UDim.new(0, 10),
                    PaddingLeft = UDim.new(0, 10),
                    PaddingRight = UDim.new(0, 10)
                }),
                create("UIListLayout", {
                    SortOrder = Enum.SortOrder.LayoutOrder,
                    Padding = UDim.new(0, 6)
                })
            })

            create("TextLabel", {
                LayoutOrder = 0,
                Size = UDim2.new(1, 0, 0, 18),
                BackgroundTransparency = 1,
                Text = string.upper(sectionName),
                TextColor3 = Library.Theme.Muted,
                Font = Enum.Font.GothamBold,
                TextSize = 10,
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = SecCard
            })

            function Section:AddLabel(text)
                local LblObj = {}
                local lbl = create("TextLabel", {
                    Size = UDim2.new(1, 0, 0, 18),
                    AutomaticSize = Enum.AutomaticSize.Y,
                    BackgroundTransparency = 1,
                    Text = text,
                    TextColor3 = Library.Theme.SubText,
                    Font = Enum.Font.Gotham,
                    TextSize = 11,
                    TextWrapped = true,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = SecCard
                })
                function LblObj:Set(newText)
                    lbl.Text = tostring(newText)
                end
                return LblObj
            end

            function Section:AddDivider()
                create("Frame", {
                    Size = UDim2.new(1, 0, 0, 1),
                    BackgroundColor3 = Library.Theme.Stroke,
                    BackgroundTransparency = 0.5,
                    BorderSizePixel = 0,
                    Parent = SecCard
                })
            end

            function Section:AddButton(cfg)
                cfg = cfg or {}
                local bText = cfg.Name or "Button"
                local callback = cfg.Callback or function() end

                local Btn = create("TextButton", {
                    Size = UDim2.new(1, 0, 0, 28),
                    BackgroundColor3 = Library.Theme.CardHover,
                    BackgroundTransparency = 0.25,
                    AutoButtonColor = false,
                    Text = bText,
                    TextColor3 = Library.Theme.Text,
                    Font = Enum.Font.GothamMedium,
                    TextSize = 11,
                    Parent = SecCard
                }, {
                    create("UICorner", { CornerRadius = UDim.new(0, 6) }),
                    create("UIStroke", {
                        Color = Library.Theme.Stroke,
                        Transparency = 0.45,
                        Thickness = 1
                    })
                })

                Btn.MouseEnter:Connect(function()
                    tween(Btn, 0.15, { BackgroundTransparency = 0.05 })
                end)
                Btn.MouseLeave:Connect(function()
                    tween(Btn, 0.15, { BackgroundTransparency = 0.25 })
                end)
                Btn.Activated:Connect(function()
                    tween(Btn, 0.08, { BackgroundColor3 = Library.Theme.Accent })
                    task.delay(0.1, function()
                        tween(Btn, 0.18, { BackgroundColor3 = Library.Theme.CardHover })
                    end)
                    task.spawn(callback)
                end)

                return Btn
            end

            function Section:AddToggle(cfg)
                cfg = cfg or {}
                local tName = cfg.Name or "Toggle"
                local state = (cfg.Default == true)
                local flag = cfg.Flag or tName
                local callback = cfg.Callback or function() end

                Library.Flags[flag] = state
                local ToggleObj = { Value = state }

                local Row = create("TextButton", {
                    Size = UDim2.new(1, 0, 0, 26),
                    BackgroundTransparency = 1,
                    AutoButtonColor = false,
                    Text = "",
                    Parent = SecCard
                })

                local Title = create("TextLabel", {
                    Size = UDim2.new(1, -44, 1, 0),
                    BackgroundTransparency = 1,
                    Text = tName,
                    TextColor3 = state and Library.Theme.Text or Library.Theme.SubText,
                    Font = Enum.Font.GothamMedium,
                    TextSize = 11,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = Row
                })

                local SwitchBg = create("Frame", {
                    Size = UDim2.new(0, 34, 0, 18),
                    Position = UDim2.new(1, -34, 0.5, -9),
                    BackgroundColor3 = state and Library.Theme.Accent or Library.Theme.Sidebar,
                    BorderSizePixel = 0,
                    Parent = Row
                }, {
                    create("UICorner", { CornerRadius = UDim.new(1, 0) }),
                    create("UIStroke", {
                        Color = Library.Theme.Stroke,
                        Transparency = 0.35,
                        Thickness = 1
                    })
                })

                local Knob = create("Frame", {
                    Size = UDim2.new(0, 12, 0, 12),
                    Position = state and UDim2.new(1, -15, 0.5, -6) or UDim2.new(0, 3, 0.5, -6),
                    BackgroundColor3 = Color3.fromRGB(255, 255, 255),
                    BorderSizePixel = 0,
                    Parent = SwitchBg
                }, {
                    create("UICorner", { CornerRadius = UDim.new(1, 0) })
                })

                function ToggleObj:Set(val)
                    self.Value = (val == true)
                    Library.Flags[flag] = self.Value
                    tween(Title, 0.15, { TextColor3 = self.Value and Library.Theme.Text or Library.Theme.SubText })
                    tween(SwitchBg, 0.18, { BackgroundColor3 = self.Value and Library.Theme.Accent or Library.Theme.Sidebar })
                    tween(Knob, 0.18, { Position = self.Value and UDim2.new(1, -15, 0.5, -6) or UDim2.new(0, 3, 0.5, -6) })
                    task.spawn(callback, self.Value)
                end

                function ToggleObj:Get()
                    return self.Value
                end

                Row.Activated:Connect(function()
                    ToggleObj:Set(not ToggleObj.Value)
                end)

                if state then
                    task.spawn(callback, true)
                end

                return ToggleObj
            end

            function Section:AddSlider(cfg)
                cfg = cfg or {}
                local sName = cfg.Name or "Slider"
                local min = cfg.Min or 0
                local max = cfg.Max or 100
                local rounding = cfg.Rounding or 0
                local suffix = cfg.Suffix or ""
                local val = math.clamp(cfg.Default or min, min, max)
                local flag = cfg.Flag or sName
                local callback = cfg.Callback or function() end

                Library.Flags[flag] = val
                local SliderObj = { Value = val }

                local Container = create("Frame", {
                    Size = UDim2.new(1, 0, 0, 38),
                    BackgroundTransparency = 1,
                    Parent = SecCard
                })

                create("TextLabel", {
                    Size = UDim2.new(0.65, 0, 0, 16),
                    BackgroundTransparency = 1,
                    Text = sName,
                    TextColor3 = Library.Theme.SubText,
                    Font = Enum.Font.GothamMedium,
                    TextSize = 11,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = Container
                })

                local ValLabel = create("TextLabel", {
                    Size = UDim2.new(0.35, 0, 0, 16),
                    Position = UDim2.new(0.65, 0, 0, 0),
                    BackgroundTransparency = 1,
                    Text = tostring(val) .. suffix,
                    TextColor3 = Library.Theme.Text,
                    Font = Enum.Font.GothamBold,
                    TextSize = 11,
                    TextXAlignment = Enum.TextXAlignment.Right,
                    Parent = Container
                })

                local Track = create("Frame", {
                    Size = UDim2.new(1, 0, 0, 6),
                    Position = UDim2.new(0, 0, 0, 24),
                    BackgroundColor3 = Library.Theme.Sidebar,
                    BorderSizePixel = 0,
                    Parent = Container
                }, {
                    create("UICorner", { CornerRadius = UDim.new(1, 0) }),
                    create("UIStroke", {
                        Color = Library.Theme.Stroke,
                        Transparency = 0.5,
                        Thickness = 1
                    })
                })

                local initialScale = (max > min) and ((val - min) / (max - min)) or 0
                local Fill = create("Frame", {
                    Size = UDim2.new(initialScale, 0, 1, 0),
                    BorderSizePixel = 0,
                    Parent = Track
                }, {
                    create("UICorner", { CornerRadius = UDim.new(1, 0) })
                })
                Library:RegisterAccent(Fill, "BackgroundColor3")

                local Thumb = create("Frame", {
                    Size = UDim2.new(0, 12, 0, 12),
                    Position = UDim2.new(1, -6, 0.5, -6),
                    BackgroundColor3 = Color3.fromRGB(255, 255, 255),
                    BorderSizePixel = 0,
                    Parent = Fill
                }, {
                    create("UICorner", { CornerRadius = UDim.new(1, 0) })
                })

                local function roundNumber(n)
                    if rounding <= 0 then
                        return math.floor(n + 0.5)
                    end
                    local mult = 10 ^ rounding
                    return math.floor(n * mult + 0.5) / mult
                end

                function SliderObj:Set(newVal)
                    local clamped = math.clamp(roundNumber(newVal), min, max)
                    self.Value = clamped
                    Library.Flags[flag] = clamped
                    local pct = (max > min) and ((clamped - min) / (max - min)) or 0
                    ValLabel.Text = tostring(clamped) .. suffix
                    tween(Fill, 0.08, { Size = UDim2.new(pct, 0, 1, 0) })
                    task.spawn(callback, clamped)
                end

                function SliderObj:Get()
                    return self.Value
                end

                local sliding = false
                local function updateFromInput(input)
                    local rel = math.clamp((input.Position.X - Track.AbsolutePosition.X) / Track.AbsoluteSize.X, 0, 1)
                    local raw = min + (max - min) * rel
                    SliderObj:Set(raw)
                end

                Track.InputBegan:Connect(function(input)
                    if input.UserInputType == Enum.UserInputType.MouseButton1 then
                        sliding = true
                        updateFromInput(input)
                    end
                end)

                table.insert(Library.Connections, UserInputService.InputEnded:Connect(function(input)
                    if input.UserInputType == Enum.UserInputType.MouseButton1 then
                        sliding = false
                    end
                end))

                table.insert(Library.Connections, UserInputService.InputChanged:Connect(function(input)
                    if sliding and input.UserInputType == Enum.UserInputType.MouseMovement then
                        updateFromInput(input)
                    end
                end))

                return SliderObj
            end

            function Section:AddDropdown(cfg)
                cfg = cfg or {}
                local dName = cfg.Name or "Selector"
                local options = cfg.Options or {}
                local isMulti = (cfg.Multi == true)
                local flag = cfg.Flag or dName
                local callback = cfg.Callback or function() end

                local currentVal
                if isMulti then
                    currentVal = {}
                    if type(cfg.Default) == "table" then
                        for _, v in ipairs(cfg.Default) do
                            currentVal[v] = true
                        end
                    end
                else
                    currentVal = cfg.Default or options[1] or "None"
                end

                Library.Flags[flag] = currentVal
                local DropObj = {
                    Value = currentVal,
                    Options = options,
                    Open = false
                }

                local Wrapper = create("Frame", {
                    Size = UDim2.new(1, 0, 0, 46),
                    BackgroundTransparency = 1,
                    ClipsDescendants = true,
                    Parent = SecCard
                })

                create("TextLabel", {
                    Size = UDim2.new(1, 0, 0, 16),
                    BackgroundTransparency = 1,
                    Text = dName,
                    TextColor3 = Library.Theme.SubText,
                    Font = Enum.Font.GothamMedium,
                    TextSize = 11,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = Wrapper
                })

                local HeaderBtn = create("TextButton", {
                    Size = UDim2.new(1, 0, 0, 26),
                    Position = UDim2.new(0, 0, 0, 18),
                    BackgroundColor3 = Library.Theme.Sidebar,
                    AutoButtonColor = false,
                    Text = "",
                    Parent = Wrapper
                }, {
                    create("UICorner", { CornerRadius = UDim.new(0, 6) }),
                    create("UIStroke", {
                        Color = Library.Theme.Stroke,
                        Transparency = 0.4,
                        Thickness = 1
                    })
                })

                local SelectedText = create("TextLabel", {
                    Size = UDim2.new(1, -28, 1, 0),
                    Position = UDim2.new(0, 10, 0, 0),
                    BackgroundTransparency = 1,
                    Text = "",
                    TextColor3 = Library.Theme.Text,
                    Font = Enum.Font.GothamMedium,
                    TextSize = 11,
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = HeaderBtn
                })

                local Arrow = create("TextLabel", {
                    Size = UDim2.new(0, 20, 1, 0),
                    Position = UDim2.new(1, -22, 0, 0),
                    BackgroundTransparency = 1,
                    Text = "v",
                    TextColor3 = Library.Theme.Muted,
                    Font = Enum.Font.GothamBold,
                    TextSize = 10,
                    Parent = HeaderBtn
                })

                local ListFrame = create("ScrollingFrame", {
                    Size = UDim2.new(1, 0, 0, 100),
                    Position = UDim2.new(0, 0, 0, 48),
                    BackgroundColor3 = Library.Theme.Sidebar,
                    BorderSizePixel = 0,
                    ScrollBarThickness = 2,
                    ScrollBarImageColor3 = Library.Theme.Accent,
                    CanvasSize = UDim2.new(0, 0, 0, 0),
                    AutomaticCanvasSize = Enum.AutomaticSize.Y,
                    Parent = Wrapper
                }, {
                    create("UICorner", { CornerRadius = UDim.new(0, 6) }),
                    create("UIStroke", {
                        Color = Library.Theme.Stroke,
                        Transparency = 0.4,
                        Thickness = 1
                    }),
                    create("UIPadding", {
                        PaddingTop = UDim.new(0, 4),
                        PaddingBottom = UDim.new(0, 4),
                        PaddingLeft = UDim.new(0, 4),
                        PaddingRight = UDim.new(0, 4)
                    }),
                    create("UIListLayout", {
                        SortOrder = Enum.SortOrder.LayoutOrder,
                        Padding = UDim.new(0, 2)
                    })
                })

                local function formatDisplay()
                    if isMulti then
                        local items = {}
                        for _, opt in ipairs(DropObj.Options) do
                            if DropObj.Value[opt] then
                                table.insert(items, tostring(opt))
                            end
                        end
                        SelectedText.Text = (#items > 0) and table.concat(items, ", ") or "None"
                    else
                        SelectedText.Text = tostring(DropObj.Value)
                    end
                end

                local function rebuildOptions()
                    for _, ch in ipairs(ListFrame:GetChildren()) do
                        if ch:IsA("TextButton") then
                            ch:Destroy()
                        end
                    end

                    for _, opt in ipairs(DropObj.Options) do
                        local isSelected = isMulti and (DropObj.Value[opt] == true) or (DropObj.Value == opt)
                        local OptBtn = create("TextButton", {
                            Size = UDim2.new(1, 0, 0, 22),
                            BackgroundColor3 = Library.Theme.CardHover,
                            BackgroundTransparency = isSelected and 0.2 or 1,
                            AutoButtonColor = false,
                            Text = "  " .. tostring(opt),
                            TextColor3 = isSelected and Library.Theme.Accent or Library.Theme.SubText,
                            Font = isSelected and Enum.Font.GothamBold or Enum.Font.GothamMedium,
                            TextSize = 11,
                            TextXAlignment = Enum.TextXAlignment.Left,
                            Parent = ListFrame
                        }, {
                            create("UICorner", { CornerRadius = UDim.new(0, 4) })
                        })

                        OptBtn.Activated:Connect(function()
                            if isMulti then
                                DropObj.Value[opt] = not DropObj.Value[opt]
                                Library.Flags[flag] = DropObj.Value
                                formatDisplay()
                                rebuildOptions()
                                task.spawn(callback, DropObj.Value)
                            else
                                DropObj:Set(opt)
                                DropObj.Open = false
                                Arrow.Rotation = 0
                                tween(Wrapper, 0.18, { Size = UDim2.new(1, 0, 0, 46) })
                            end
                        end)
                    end
                end

                function DropObj:Set(val)
                    self.Value = val
                    Library.Flags[flag] = val
                    formatDisplay()
                    rebuildOptions()
                    task.spawn(callback, val)
                end

                function DropObj:Refresh(newOptions, newDefault)
                    self.Options = newOptions or {}
                    if newDefault ~= nil then
                        self.Value = newDefault
                    end
                    formatDisplay()
                    rebuildOptions()
                end

                function DropObj:Get()
                    return self.Value
                end

                HeaderBtn.Activated:Connect(function()
                    DropObj.Open = not DropObj.Open
                    Arrow.Rotation = DropObj.Open and 180 or 0
                    local listHeight = math.min(#DropObj.Options * 24 + 8, 110)
                    ListFrame.Size = UDim2.new(1, 0, 0, listHeight)
                    tween(Wrapper, 0.2, {
                        Size = DropObj.Open and UDim2.new(1, 0, 0, 52 + listHeight) or UDim2.new(1, 0, 0, 46)
                    })
                end)

                formatDisplay()
                rebuildOptions()
                return DropObj
            end

            function Section:AddKeybind(cfg)
                cfg = cfg or {}
                local kName = cfg.Name or "Keybind"
                local key = cfg.Default or Enum.KeyCode.X
                local mode = cfg.Mode or "Toggle" -- "Toggle" | "Hold"
                local flag = cfg.Flag or kName
                local callback = cfg.Callback or function() end
                local onChanged = cfg.ChangedCallback or function() end

                local KeyObj = {
                    Key = key,
                    Mode = mode,
                    Active = false,
                    Binding = false
                }
                Library.Flags[flag] = key

                local Row = create("Frame", {
                    Size = UDim2.new(1, 0, 0, 26),
                    BackgroundTransparency = 1,
                    Parent = SecCard
                })

                create("TextLabel", {
                    Size = UDim2.new(1, -75, 1, 0),
                    BackgroundTransparency = 1,
                    Text = kName,
                    TextColor3 = Library.Theme.SubText,
                    Font = Enum.Font.GothamMedium,
                    TextSize = 11,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = Row
                })

                -- Estilo de Keycap Mecânica
                local KeycapBtn = create("TextButton", {
                    Size = UDim2.new(0, 58, 0, 22),
                    Position = UDim2.new(1, -58, 0.5, -11),
                    BackgroundColor3 = Library.Theme.Sidebar,
                    AutoButtonColor = false,
                    Text = "[" .. formatKeyName(key) .. "]",
                    TextColor3 = Library.Theme.Text,
                    Font = Enum.Font.Code,
                    TextSize = 11,
                    Parent = Row
                }, {
                    create("UICorner", { CornerRadius = UDim.new(0, 5) }),
                    create("UIStroke", {
                        Color = Library.Theme.Stroke,
                        Transparency = 0.2,
                        Thickness = 1.2
                    })
                })

                function KeyObj:Set(newKey)
                    self.Key = newKey
                    Library.Flags[flag] = newKey
                    KeycapBtn.Text = "[" .. formatKeyName(newKey) .. "]"
                    task.spawn(onChanged, newKey)
                end

                function KeyObj:Get()
                    return self.Key
                end

                KeycapBtn.Activated:Connect(function()
                    KeyObj.Binding = true
                    KeycapBtn.Text = "[ ... ]"
                    tween(KeycapBtn, 0.15, { TextColor3 = Library.Theme.Accent })
                end)

                table.insert(Library.Connections, UserInputService.InputBegan:Connect(function(input, gp)
                    if KeyObj.Binding then
                        if input.KeyCode == Enum.KeyCode.Escape then
                            KeyObj.Binding = false
                            KeyObj:Set( nil )
                            tween(KeycapBtn, 0.15, { TextColor3 = Library.Theme.Text })
                            return
                        end
                        local chosen = (input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode)
                            or (input.UserInputType.Name:find("MouseButton") and input.UserInputType)
                        if chosen and chosen ~= Enum.KeyCode.Unknown then
                            KeyObj.Binding = false
                            KeyObj:Set(chosen)
                            tween(KeycapBtn, 0.15, { TextColor3 = Library.Theme.Text })
                        end
                        return
                    end

                    if gp or not KeyObj.Key then return end
                    local match = (input.KeyCode == KeyObj.Key) or (input.UserInputType == KeyObj.Key)
                    if match then
                        if KeyObj.Mode == "Hold" then
                            KeyObj.Active = true
                            task.spawn(callback, true)
                        else
                            KeyObj.Active = not KeyObj.Active
                            task.spawn(callback, KeyObj.Active)
                        end
                    end
                end))

                table.insert(Library.Connections, UserInputService.InputEnded:Connect(function(input)
                    if not KeyObj.Key or KeyObj.Mode ~= "Hold" then return end
                    local match = (input.KeyCode == KeyObj.Key) or (input.UserInputType == KeyObj.Key)
                    if match and KeyObj.Active then
                        KeyObj.Active = false
                        task.spawn(callback, false)
                    end
                end))

                return KeyObj
            end

            function Section:AddColorPicker(cfg)
                cfg = cfg or {}
                local cName = cfg.Name or "Color"
                local defaultColor = cfg.Default or Library.Theme.Accent
                local flag = cfg.Flag or cName
                local callback = cfg.Callback or function() end

                local h, s, v = Color3.toHSV(defaultColor)
                local ColorObj = {
                    Value = defaultColor,
                    Open = false
                }
                Library.Flags[flag] = defaultColor

                local Wrapper = create("Frame", {
                    Size = UDim2.new(1, 0, 0, 26),
                    BackgroundTransparency = 1,
                    ClipsDescendants = true,
                    Parent = SecCard
                })

                create("TextLabel", {
                    Size = UDim2.new(1, -45, 0, 26),
                    BackgroundTransparency = 1,
                    Text = cName,
                    TextColor3 = Library.Theme.SubText,
                    Font = Enum.Font.GothamMedium,
                    TextSize = 11,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = Wrapper
                })

                local PreviewBtn = create("TextButton", {
                    Size = UDim2.new(0, 32, 0, 18),
                    Position = UDim2.new(1, -32, 0, 4),
                    BackgroundColor3 = defaultColor,
                    AutoButtonColor = false,
                    Text = "",
                    Parent = Wrapper
                }, {
                    create("UICorner", { CornerRadius = UDim.new(0, 5) }),
                    create("UIStroke", {
                        Color = Library.Theme.Stroke,
                        Transparency = 0.3,
                        Thickness = 1
                    })
                })

                local PickerBox = create("Frame", {
                    Size = UDim2.new(1, 0, 0, 88),
                    Position = UDim2.new(0, 0, 0, 30),
                    BackgroundColor3 = Library.Theme.Sidebar,
                    BorderSizePixel = 0,
                    Parent = Wrapper
                }, {
                    create("UICorner", { CornerRadius = UDim.new(0, 6) }),
                    create("UIStroke", {
                        Color = Library.Theme.Stroke,
                        Transparency = 0.4,
                        Thickness = 1
                    })
                })

                local HueBar = create("Frame", {
                    Size = UDim2.new(1, -16, 0, 12),
                    Position = UDim2.new(0, 8, 0, 10),
                    BackgroundColor3 = Color3.fromRGB(255, 255, 255),
                    BorderSizePixel = 0,
                    Parent = PickerBox
                }, {
                    create("UICorner", { CornerRadius = UDim.new(1, 0) }),
                    create("UIGradient", {
                        Color = ColorSequence.new({
                            ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 0, 0)),
                            ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 255, 0)),
                            ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 255, 0)),
                            ColorSequenceKeypoint.new(0.50, Color3.fromRGB(0, 255, 255)),
                            ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 0, 255)),
                            ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 0, 255)),
                            ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 0, 0))
                        })
                    })
                })

                local SatBar = create("Frame", {
                    Size = UDim2.new(1, -16, 0, 12),
                    Position = UDim2.new(0, 8, 0, 30),
                    BackgroundColor3 = Color3.fromHSV(h, 1, 1),
                    BorderSizePixel = 0,
                    Parent = PickerBox
                }, {
                    create("UICorner", { CornerRadius = UDim.new(1, 0) }),
                    create("UIGradient", {
                        Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 255, 255))
                    })
                })

                local ValBar = create("Frame", {
                    Size = UDim2.new(1, -16, 0, 12),
                    Position = UDim2.new(0, 8, 0, 50),
                    BackgroundColor3 = Color3.fromRGB(255, 255, 255),
                    BorderSizePixel = 0,
                    Parent = PickerBox
                }, {
                    create("UICorner", { CornerRadius = UDim.new(1, 0) }),
                    create("UIGradient", {
                        Color = ColorSequence.new(Color3.fromRGB(20, 20, 20), Color3.fromRGB(255, 255, 255))
                    })
                })

                local HexLabel = create("TextLabel", {
                    Size = UDim2.new(1, -16, 0, 16),
                    Position = UDim2.new(0, 8, 0, 66),
                    BackgroundTransparency = 1,
                    Text = string.format("RGB: %d, %d, %d", math.floor(defaultColor.R * 255), math.floor(defaultColor.G * 255), math.floor(defaultColor.B * 255)),
                    TextColor3 = Library.Theme.Muted,
                    Font = Enum.Font.Code,
                    TextSize = 10,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = PickerBox
                })

                function ColorObj:Set(newColor)
                    self.Value = newColor
                    Library.Flags[flag] = newColor
                    PreviewBtn.BackgroundColor3 = newColor
                    HexLabel.Text = string.format("RGB: %d, %d, %d", math.floor(newColor.R * 255), math.floor(newColor.G * 255), math.floor(newColor.B * 255))
                    task.spawn(callback, newColor)
                end

                function ColorObj:Get()
                    return self.Value
                end

                local function bindBar(bar, onRel)
                    local dragging = false
                    bar.InputBegan:Connect(function(inp)
                        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
                            dragging = true
                            local rel = math.clamp((inp.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
                            onRel(rel)
                        end
                    end)
                    table.insert(Library.Connections, UserInputService.InputEnded:Connect(function(inp)
                        if inp.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
                    end))
                    table.insert(Library.Connections, UserInputService.InputChanged:Connect(function(inp)
                        if dragging and inp.UserInputType == Enum.UserInputType.MouseMovement then
                            local rel = math.clamp((inp.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
                            onRel(rel)
                        end
                    end))
                end

                bindBar(HueBar, function(rel)
                    h = rel
                    ColorObj:Set(Color3.fromHSV(h, s, v))
                end)
                bindBar(SatBar, function(rel)
                    s = rel
                    ColorObj:Set(Color3.fromHSV(h, s, v))
                end)
                bindBar(ValBar, function(rel)
                    v = rel
                    ColorObj:Set(Color3.fromHSV(h, s, v))
                end)

                PreviewBtn.Activated:Connect(function()
                    ColorObj.Open = not ColorObj.Open
                    tween(Wrapper, 0.2, {
                        Size = ColorObj.Open and UDim2.new(1, 0, 0, 122) or UDim2.new(1, 0, 0, 26)
                    })
                end)

                return ColorObj
            end

            function Section:AddInput(cfg)
                cfg = cfg or {}
                local iName = cfg.Name or "Input"
                local placeholder = cfg.Placeholder or "Digite..."
                local defaultText = cfg.Default or ""
                local flag = cfg.Flag or iName
                local callback = cfg.Callback or function() end

                Library.Flags[flag] = defaultText
                local InputObj = { Value = defaultText }

                local Container = create("Frame", {
                    Size = UDim2.new(1, 0, 0, 44),
                    BackgroundTransparency = 1,
                    Parent = SecCard
                })

                create("TextLabel", {
                    Size = UDim2.new(1, 0, 0, 16),
                    BackgroundTransparency = 1,
                    Text = iName,
                    TextColor3 = Library.Theme.SubText,
                    Font = Enum.Font.GothamMedium,
                    TextSize = 11,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = Container
                })

                local Box = create("TextBox", {
                    Size = UDim2.new(1, 0, 0, 24),
                    Position = UDim2.new(0, 0, 0, 18),
                    BackgroundColor3 = Library.Theme.Sidebar,
                    Text = defaultText,
                    PlaceholderText = placeholder,
                    PlaceholderColor3 = Library.Theme.Muted,
                    TextColor3 = Library.Theme.Text,
                    Font = Enum.Font.GothamMedium,
                    TextSize = 11,
                    ClearTextOnFocus = false,
                    Parent = Container
                }, {
                    create("UICorner", { CornerRadius = UDim.new(0, 5) }),
                    create("UIStroke", {
                        Color = Library.Theme.Stroke,
                        Transparency = 0.4,
                        Thickness = 1
                    }),
                    create("UIPadding", {
                        PaddingLeft = UDim.new(0, 8),
                        PaddingRight = UDim.new(0, 8)
                    })
                })

                function InputObj:Set(txt)
                    self.Value = tostring(txt)
                    Library.Flags[flag] = self.Value
                    Box.Text = self.Value
                    task.spawn(callback, self.Value)
                end

                function InputObj:Get()
                    return self.Value
                end

                Box.FocusLost:Connect(function()
                    InputObj:Set(Box.Text)
                end)

                return InputObj
            end

            return Section
        end

        return Tab
    end

    return Window
end

return Library
