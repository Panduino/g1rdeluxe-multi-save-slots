-- Multiple Save Slots for Gen 3.
-- Uses FireRed's native Start menu and native Save screen.
-- This mod only chooses which SaveData slot the native save/load code uses.

return function(mod)
  local SaveData = require("src.core.SaveData")
  local GameVersion = require("src.core.GameVersion")
  local Runtime = require("src.mods.Runtime")

  local function versionFor(game, session)
    return (session and session.version)
      or (game and game.version)
      or GameVersion.get()
  end

  local function isGen3(version)
    return GameVersion.generation(version) == 3
  end

  local function slots(version)
    if not isGen3(version) then return {} end
    return SaveData.listSlots(version) or {}
  end

  local function slotLabel(slot)
    local label = slot.name
    if type(label) ~= "string" or label == "" then
      label = slot.id
    end
    return label
  end

  local function makeRows(version, includeNew)
    local rows = {}

    for _, slot in ipairs(slots(version)) do
      rows[#rows + 1] = {
        id = slot.id,
        label = slot.id .. "  " .. slotLabel(slot),
        exists = slot.exists == true,
        active = slot.id == SaveData.activeSlot(version),
      }
    end

    if includeNew then
      rows[#rows + 1] = {
        id = "__new__",
        label = "NEW SAVE SLOT",
      }
    end

    return rows
  end

  local function pushList(game, title, rows, onSelect)
    local Stack = require("src.ui.game3.stack")
    local Window = require("src.ui.game3.window")
    local ListMenu = require("src.ui.game3.list_menu")
    local FrlgFont = require("src.ui.game3.frlg_font")

    local menu = ListMenu.new({
      template = Window.template(4, 4, 22, math.min(14, (#rows * 2) + 2)),
      items = rows,
      maxShowed = math.min(6, math.max(1, #rows)),
      itemX = 8,
      cursorX = 0,
      rowHeight = 16,
      onSelect = function(item)
        if onSelect then onSelect(item) end
      end,
      onCancel = function()
        Stack.pop("gen3_multi_save_slots")
      end,
    })

    local oldDraw = menu.draw
    menu.draw = function(self)
      oldDraw(self)
      local tpl = self.template
      local titleX = (tpl.left or 4) * 8 + 8
      local titleY = (tpl.top or 4) * 8 - 12
      FrlgFont.draw(title, titleX, titleY, {
        colors = FrlgFont.COLOR.NORMAL,
      })
    end

    Stack.push("gen3_multi_save_slots", menu, { hideBelow = true })
  end

  local function openSelectSlot(game, session)
    local version = versionFor(game, session)
    local rows = makeRows(version, true)

    if #rows == 0 then
      mod.log:warn("No Gen 3 save slots available for %s", tostring(version))
      return
    end

    pushList(game, "SELECT SAVE SLOT", rows, function(item)
      local Stack = require("src.ui.game3.stack")

      if item.id == "__new__" then
        local id = SaveData.createSlot(version)
        if not id then
          mod.log:warn("Could not create a Gen 3 save slot")
          Stack.pop("gen3_multi_save_slots")
          return
        end
        SaveData.setActiveSlot(version, id)
      else
        SaveData.setActiveSlot(version, item.id)
      end

      Stack.pop("gen3_multi_save_slots")
    end)
  end

  local function openManageSlots(game, session)
    local version = versionFor(game, session)
    local rows = {}

    for _, slot in ipairs(slots(version)) do
      rows[#rows + 1] = {
        id = slot.id,
        label = slot.id .. (slot.id == SaveData.activeSlot(version) and "  ACTIVE" or ""),
        locked = slot.id == SaveData.activeSlot(version),
      }
    end

    if #rows == 0 then
      mod.log:warn("No Gen 3 save slots to manage")
      return
    end

    pushList(game, "MANAGE SAVE SLOTS", rows, function(item)
      if item.locked then
        return
      end

      local Stack = require("src.ui.game3.stack")
      local Message = require("src.ui.game3.message")

      -- Use the native Gen 3 message/choice infrastructure for confirmation.
      -- The slot is not deleted until the player confirms.
      if Message and Message.show then
        Message.show(
          "DELETE " .. item.id .. "?",
          function()
            SaveData.deleteSlot(version, item.id)
            Stack.pop("gen3_multi_save_slots")
          end,
          function() end
        )
      else
        SaveData.deleteSlot(version, item.id)
        Stack.pop("gen3_multi_save_slots")
      end
    end)
  end

  -- FireRed's native Start menu calls this hook before displaying its entries.
  -- Do not replace the native SAVE entry: its SaveMenu performs the actual
  -- FireRed save flow, including the save confirmation and write.
  if not mod._gen3SaveSlotsStartMenuHook then
    mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
      items = next(game, items) or items

      local session = game and game.session
      local version = versionFor(game, session)
      if not isGen3(version) then
        return items
      end

      local saveIndex
      for i, item in ipairs(items) do
        if item.id == "save" then
          saveIndex = i
          break
        end
      end

      if not saveIndex then
        return items
      end

      table.insert(items, saveIndex, {
        id = "save_slot",
        label = "SAVE SLOT",
        onSelect = function(g, s)
          openSelectSlot(g, s)
        end,
      })

      table.insert(items, saveIndex + 1, {
        id = "manage_save_slots",
        label = "MANAGE SAVES",
        onSelect = function(g, s)
          openManageSlots(g, s)
        end,
      })

      return items
    end)

    mod._gen3SaveSlotsStartMenuHook = true
  end

  -- The active slot must be resolved before any ordinary Gen 3 save/load.
  mod.events:on("game.ready", function(payload)
    local game = payload and payload.game or payload
    local session = game and game.session
    local version = versionFor(game, session)

    if not isGen3(version) then return end

    pcall(SaveData.refreshSlotResolution, version)
    pcall(SaveData.activeSlot, version)
  end)

  mod.exports.version = "1.1.0"
  mod.log:info("GEN3_MULTI_SAVE_SLOTS 1.1.0")
end
