--[[
	PRZYKŁAD: Jak używać własnych UI prefabów z ReplicatedStorage
	
	ZAMIAST tworzyć UI kodem, możesz:
	1. Stworzyć Frame/TextLabel/itp w Roblox Studio
	2. Wrzucić go do ReplicatedStorage (np. ReplicatedStorage.UIPrefabs.TooltipTemplate)
	3. Klonować i modyfikować w kodzie
	
	ZALETY:
	✅ Łatwiejsze projektowanie wizualne w Studio
	✅ Szybsze iteracje (nie trzeba reloadować skryptu)
	✅ Mniej kodu do utrzymania
	✅ Można robić bardziej skomplikowane UI z ImageLabels, UIGradients itp.
]]

-- ===== PRZYKŁAD 1: Tooltip z prefabu =====

-- W Studio stwórz:
-- ReplicatedStorage
--   └─ UIPrefabs
--       └─ TooltipTemplate (Frame)
--           ├─ Title (TextLabel)
--           └─ Description (TextLabel)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Zamiast tworzyć tooltip kodem:
function CreateTooltipOLD()
	local tooltip = Instance.new("Frame")
	tooltip.Size = UDim2.new(0, 200, 0, 100)
	tooltip.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
	-- ... 50 linii kodu ...
	return tooltip
end

-- Używasz prefabu:
function CreateTooltipNEW()
	local template = ReplicatedStorage.UIPrefabs.TooltipTemplate
	local tooltip = template:Clone()
	
	-- Tylko zmieniasz co potrzebujesz:
	tooltip.Title.Text = "Nowy tytuł"
	tooltip.Description.Text = "Nowy opis"
	
	return tooltip
end

-- ===== PRZYKŁAD 2: Item Frame z prefabu =====

-- W Studio stwórz:
-- ReplicatedStorage
--   └─ UIPrefabs
--       └─ ItemFrameTemplate (Frame)
--           ├─ UICorner
--           ├─ ItemIcon (ImageLabel) -- możesz dodać ikony!
--           └─ ItemName (TextLabel)

function CreateItemFrameFromPrefab(itemDef, x, y, width, height)
	local template = ReplicatedStorage.UIPrefabs.ItemFrameTemplate
	local frame = template:Clone()
	
	-- Ustaw pozycję i rozmiar
	frame.Position = UDim2.new(0, (x - 1) * 62, 0, (y - 1) * 62)
	frame.Size = UDim2.new(0, width * 60, 0, height * 60)
	
	-- Ustaw kolor i tekst
	frame.BackgroundColor3 = itemDef.Color
	frame.ItemName.Text = itemDef.Name
	
	-- Jeśli masz ikonę w itemDef:
	if itemDef.IconAsset then
		frame.ItemIcon.Image = itemDef.IconAsset
	end
	
	return frame
end

-- ===== PRZYKŁAD 3: Cały inventory container z prefabu =====

-- Możesz nawet stworzyć cały layout w Studio:
-- ReplicatedStorage
--   └─ UIPrefabs
--       └─ InventoryContainer (Frame)
--           ├─ Title (TextLabel)
--           ├─ GridContainer (Frame)
--           ├─ ItemContainer (Frame)
--           └─ EquippedSlot (Frame)

function CreateInventoryFromPrefab(parent)
	local template = ReplicatedStorage.UIPrefabs.InventoryContainer
	local container = template:Clone()
	container.Parent = parent
	
	-- Możesz nadal dodawać rzeczy kodem:
	local gridContainer = container.GridContainer
	for y = 1, 8 do
		for x = 1, 6 do
			local slot = Instance.new("Frame")
			slot.Name = string.format("Slot_%d_%d", x, y)
			-- ... konfiguracja slotu
			slot.Parent = gridContainer
		end
	end
	
	return container
end

-- ===== JAK TO ZASTOSOWAĆ W TWOIM KODZIE =====

--[[
W InventoryUI.client.lua:

1. Zamiast tworzyć tooltip kodem w _CreateUI():
   -- Stary sposób:
   self._tooltipFrame = Instance.new("Frame")
   self._tooltipFrame.Size = UDim2.new(0, 200, 0, 0)
   -- ... 40 linii ...
   
   -- Nowy sposób:
   local tooltipTemplate = ReplicatedStorage.UIPrefabs.TooltipTemplate
   self._tooltipFrame = tooltipTemplate:Clone()
   self._tooltipFrame.Visible = false
   self._tooltipFrame.Parent = self._screenGui
   
   -- Referencje do dzieci:
   self._tooltipTitle = self._tooltipFrame.Title
   self._tooltipDescription = self._tooltipFrame.Description

2. W ShowTooltip() tylko zmieniasz tekst:
   self._tooltipTitle.Text = itemDef.Name
   self._tooltipDescription.Text = itemDef.Description
   
   -- Wszystkie kolory, czcionki, rozmiary są już w prefabie!
]]

-- ===== PODSUMOWANIE =====

--[[
✅ UŻYWAJ PREFABÓW GDY:
   - Masz skomplikowane UI (gradient, cienie, ikony)
   - Chcesz szybko iterować design
   - Masz dużo podobnych elementów (item slots, buttony)
   
❌ TWÓRZ KODEM GDY:
   - Potrzebujesz dynamicznej ilości elementów (grid slots)
   - Element jest bardzo prosty (pojedynczy Frame)
   - Chcesz parametryzować wszystko (różne rozmiary, kolory)

💡 NAJLEPSZE PODEJŚCIE:
   - Prefab dla "template" (wygląd, struktura)
   - Kod dla "instance" (pozycja, kolor, tekst)
   - Hybrid: grid slots kodem, item frames z prefabu
]]
