-- Gen 3 multiple save slots.
-- The native FireRed save screen still performs every actual save.
-- This mod only chooses the SaveData slot before SAVE or CONTINUE.

return function(mod)
  local SaveData = require("src.core.SaveData")
  local GameVersion = require("src.core.GameVersion")

  local function versionOf(game, session)
    return (session and session.version) or (game and game.version) or GameVersion.get()
  end

  local function isGen3(version)
    return GameVersion.generation(version) == 3
  end

  local function listSlots(version)
    if not isGen3(version) then return {} end
    return SaveData.listSlots(version) or {}
  end

  local function existingSlots(version)
    local out = {}
    for _, slot in ipairs(listSlots(version)) do
      if slot.exists then out[#out + 1] = slot end
    end
    return out
  end

  local function makeSlotRows(version, allowNew, allowManage)
    local rows = {}
    local active = SaveData.activeSlot(version)

    for _, slot in ipairs(existingSlots(version)) do
      rows[#rows + 1] = {
        id = slot.id,
        label = string.format("%s%s  %s", slot.id, slot.id == active and " *" or "  ",
          slot.label or slot.name or "SAVE"),
      }
    end

    if allowNew then
      rows[#rows + 1] = { id = "__new__", label = "NEW SAVE" }
    end
    if allowManage then
      rows[#rows + 1] = { id = "__manage__", label = "MANAGE SAVES" }
    end
    return rows
  end

  local picker = {
    open = false,
    mode = nil,
    game = nil,
    session = nil,
    version = nil,
    rows = {},
    index = 1,
    message = nil,
  }

  local function closePicker()
    picker.open = false
    picker.rows = {}
    picker.message = nil
  end

  local function refreshPicker()
    picker.rows = makeSlotRows(picker.version, picker.mode == "save", true)
    if #picker.rows == 0 then
      picker.rows = {{ id = "__new__", label = "NEW SAVE" }}
    end
    picker.index = math.max(1, math.min(picker.index, #picker.rows))
  end

  local function openPicker(game, session, mode)
    local version = versionOf(game, session)
    if not isGen3(version) then return end

    picker.open = true
    picker.mode = mode
    picker.game = game
    picker.session = session
    picker.version = version
    picker.index = 1
    picker.message = nil
    refreshPicker()
  end

  local function deleteSlot(slotId)
    local active = SaveData.activeSlot(picker.version)
    if slotId == active then
      picker.message = "Switch to another slot before deleting the active slot."
      return
    end

    local ok, err = SaveData.deleteSlot(picker.version, slotId)
    if not ok then
      picker.message = "Could not delete " .. tostring(slotId) .. "."
      return
    end

    refreshPicker()
    picker.message = "Deleted " .. tostring(slotId) .. "."
  end

  local function selectPickerRow()
    local row = picker.rows[picker.index]
    if not row then return end

    if row.id == "__manage__" then
      picker.mode = "manage"
      picker.index = 1
      picker.message = nil
      refreshPicker()
      return
    end

    if picker.mode == "manage" then
      if row.id == "__new__" then
        picker.mode = "load"
        picker.index = 1
        picker.message = nil
        refreshPicker()
        return
      end
      deleteSlot(row.id)
      return
    end

    if row.id == "__new__" then
      if picker.mode ~= "save" then return end
      local id = SaveData.createSlot(picker.version)
      if not id then
        picker.message = "Could not create a save slot."
        return
      end
      SaveData.setActiveSlot(picker.version, id)
      closePicker()

      local Screens = require("src.ui.game3.screens")
      local SaveMenu = Screens.get("save", picker.session)
      SaveMenu.show({ session = picker.session, game = picker.game })
      return
    end

    SaveData.setActiveSlot(picker.version, row.id)

    if picker.mode == "load" then
      local game = picker.game
      closePicker()
      if game and type(game._handleBootAction) == "function" then
        game:_handleBootAction({ action = "continue" })
      end
      return
    end

    if picker.mode == "save" then
      closePicker()
      local Screens = require("src.ui.game3.screens")
      local SaveMenu = Screens.get("save", picker.session)
      SaveMenu.show({ session = picker.session, game = picker.game })
    end
  end

  local function handlePickerInput(input)
    if not picker.open or not input then return true end

    if input.wasPressed("up") then
      picker.index = ((picker.index - 2) % #picker.rows) + 1
      return true
    end
    if input.wasPressed("down") then
      picker.index = (picker.index % #picker.rows) + 1
      return true
    end
    if input.wasPressed("a") then
      selectPickerRow()
      return true
    end
    if input.wasPressed("b") then
      closePicker()
      return true
    end
    return true
  end

  local function drawPicker()
    if not picker.open then return end

    local Window = require("src.ui.game3.window")
    local FrlgFont = require("src.ui.game3.frlg_font")
    local Display = require("src.core.game3.display")

    local h = math.min(14, math.max(5, #picker.rows + 2))
    local tpl = Window.template(4, 3, 22, h)
    Window.stdFrame(tpl)

    local title = picker.mode == "load" and "LOAD SAVE"
      or picker.mode == "manage" and "MANAGE SAVES"
      or "SAVE GAME"
    FrlgFont.draw(title, tpl.left * 8 + 8, tpl.top * 8 - 13, {
      colors = FrlgFont.COLOR.NORMAL,
    })

    local visible = math.min(#picker.rows, h - 2)
    local first = math.max(1, math.min(picker.index - visible + 1, #picker.rows - visible + 1))

    for i = 1, visible do
      local idx = first + i - 1
      local row = picker.rows[idx]
      local y = tpl.top * 8 + 2 + (i - 1) * 16
      if idx == picker.index then
        Window.cursorPx(tpl.left * 8, y)
      end
      FrlgFont.draw(row.label, tpl.left * 8 + 8, y, {
        colors = FrlgFont.COLOR.NORMAL,
      })
    end

    if picker.message then
      local bottom = Display.H - 32
      FrlgFont.draw(picker.message, 16, bottom, {
        maxWidth = Display.W - 32,
        colors = FrlgFont.COLOR.NORMAL,
      })
    end
  end

  -- Native FireRed SAVE: choose the slot first, then let the real save screen
  -- perform the write. The chosen slot remains active, so the most recently
  -- saved slot is always the active slot.
  mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
    local out = next(game, items) or items
    local session = game and game.session
    local version = versionOf(game, session)
    if not isGen3(version) then return out end

    for _, item in ipairs(out) do
      if item.id == "save" then
        item.onSelect = function(g, s)
          openPicker(g, s, "save")
        end
        break
      end
    end
    return out
  end)

  -- The FireRed continue menu is implemented directly by Boot rather than
  -- through ui.title_menu.items. Add SELECT SAVE above NEW GAME.
  local Boot = require("src.ui.game3.boot")
  if not Boot._multiSaveSlotsWrapped then
    local originalMenuItems = Boot.menuItems
    local originalUpdate = Boot.update
    local originalDraw = Boot.draw

    Boot.menuItems = function(state)
      local items = originalMenuItems(state)
      if not state.hasContinue then return items end
      local out = {}
      for _, item in ipairs(items) do
        if item == "NEW GAME" then
          out[#out + 1] = "SELECT SAVE"
        end
        out[#out + 1] = item
      end
      return out
    end

    Boot.update = function(state, input, dt)
      if picker.open then
        handlePickerInput(input)
        return nil
      end

      if state.phase == Boot.PHASE.MENU and input and input.wasPressed
          and input:wasPressed("a") then
        local items = Boot.menuItems(state)
        local choice = items[state.menuIndex]
        if choice == "SELECT SAVE" then
          local game = state.game
          local Runtime = require("src.core.game3.runtime")
          if not game then game = Runtime._game end
          local session = game and game.session
          openPicker(game, session, "load")
          return nil
        end
      end

      return originalUpdate(state, input, dt)
    end

    Boot.draw = function(state)
      originalDraw(state)

      if state.phase ~= Boot.PHASE.MENU or not state.hasContinue or state.saveError then
        if picker.open then drawPicker() end
        return
      end

      local Display = require("src.core.game3.display")
      local Window = require("src.ui.game3.window")
      local RomText = require("src.core.game3.rom_text")
      local FrlgFont = require("src.ui.game3.frlg_font")

      local info = state.continueInfo or {}
      local frameType = info.frameType or 0
      local gift = state.hasContinue
      local scroll = (state.menuIndex > 1) and (state.menuIndex >= 4 and 4 or 0) or 0
      local y = 8 - scroll * 8

      -- Cover the native menu's lower option area and redraw the four/five
      -- rows with SELECT SAVE inserted above NEW GAME.
      love.graphics.setColor(139 / 255, 148 / 255, 255 / 255, 1)
      love.graphics.rectangle("fill", 20, 88 - scroll * 8, 204, 92)
      love.graphics.setColor(1, 1, 1, 1)

      local labels = Boot.menuItems(state)
      local rowY = { 88, 104, 136, 168, 200 }
      for i, label in ipairs(labels) do
        local yy = rowY[i] - scroll * 8
        if yy >= -16 and yy < Display.H then
          Window.userFrame(Window.template(3, math.floor(yy / 8), 24, 2), frameType)
          local key = label == "SELECT SAVE" and nil
            or label == "NEW GAME" and "gText_NewGame"
            or label == "MYSTERY GIFT" and "gText_MysteryGift"
            or label == "EXIT" and "gText_MenuExit"
          local text = key and RomText.plain(key) or label
          Window.printPx(text, 24 + 2, yy + 2, {
            colors = { fg = {98 / 255, 98 / 255, 98 / 255, 1},
              shadow = {213 / 255, 213 / 255, 205 / 255, 1},
              bg = {1, 1, 1, 1} },
          })
        end
      end

      local selectedY = rowY[state.menuIndex] or rowY[1]
      selectedY = selectedY - scroll * 8
      love.graphics.setColor(0, 0, 0, 7 / 16)
      love.graphics.rectangle("fill", 18, selectedY, 204, 18)
      love.graphics.setColor(1, 1, 1, 1)

      if picker.open then drawPicker() end
    end

    Boot._multiSaveSlotsWrapped = true
  end

    mod.events:on("game.ready", function(payload)
    local game = payload and payload.game or payload
    local session = game and game.session
    local version = versionOf(game, session)
    if isGen3(version) then
      pcall(SaveData.activeSlot, version)
    end
  end)

  mod.exports.version = "1.2.0"
  mod.log:info("GEN3_MULTI_SAVE_SLOTS 1.2.0")
end
