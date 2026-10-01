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

    if input:wasPressed("up") then
      picker.index = ((picker.index - 2) % #picker.rows) + 1
      return true
    end
    if input:wasPressed("down") then
      picker.index = (picker.index % #picker.rows) + 1
      return true
    end
    if input:wasPressed("a") then
      selectPickerRow()
      return true
    end
    if input:wasPressed("b") then
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

  local function pickerItems(version, allowNew)
    local items = {}
    for _, slot in ipairs(existingSlots(version)) do
      items[#items + 1] = {
        label = string.format("%s%s  %s", slot.id,
          slot.id == SaveData.activeSlot(version) and " *" or "  ",
          slot.label or slot.name or "SAVE"),
        value = slot.id,
      }
    end
    if allowNew then
      items[#items + 1] = { label = "NEW SAVE", value = "__new__" }
    end
    return items
  end

  local function openNativeSave(game, session)
    local Screens = require("src.ui.game3.screens")
    local SaveMenu = Screens.get("save", session)
    SaveMenu.show({ session = session, game = game })
  end

  local function playMenuSe(name)
    pcall(function()
      local Audio = require("src.core.game3.audio")
      local SE = require("src.core.game3.se_ids")
      local id = SE.resolve(name)
      if id then Audio.playSe(id) end
    end)
  end

  -- The Gen 3 UI has its own modal stack. Use that stack for the slot picker
  -- so it sits in front of the native FireRed start menu and can hand control
  -- straight back to the native Save screen.
  local function openGame3SavePicker(game, session)
    local Stack = require("src.ui.game3.stack")
    local Window = require("src.ui.game3.window")
    local ListMenu = require("src.ui.game3.list_menu")
    local version = versionOf(game, session)
    local items = pickerItems(version, true)
    if #items == 0 then
      items = {{ label = "NEW SAVE", value = "__new__" }}
    end

    local id = "Gen3MultiSaveSlotsSavePicker"
    local menu
    menu = ListMenu.new({
      template = Window.template(4, 3, 22, math.min(14, #items + 2)),
      items = items,
      maxShowed = math.min(8, #items),
      itemX = 8,
      cursorX = 0,
      onSelect = function(item)
        local slotId = item and item.value
        if slotId == "__new__" then
          slotId = SaveData.createSlot(version)
        end
        if not slotId then return end

        SaveData.setActiveSlot(version, slotId)
        Stack.pop(id)
        openNativeSave(game, session)
      end,
      onCancel = function()
        Stack.pop(id)
      end,
    })

    Stack.push(id, menu, { hideBelow = true })
  end

  local function openGame3LoadPicker(game, session)
    local Stack = require("src.ui.game3.stack")
    local Window = require("src.ui.game3.window")
    local ListMenu = require("src.ui.game3.list_menu")
    local version = versionOf(game, session)
    local items = pickerItems(version, false)
    if #items == 0 then
      items = {{ label = "NO SAVES", value = "__none__", disabled = true }}
    end

    local id = "Gen3MultiSaveSlotsLoadPicker"
    local menu
    menu = ListMenu.new({
      template = Window.template(4, 3, 22, math.min(14, #items + 2)),
      items = items,
      maxShowed = math.min(8, #items),
      itemX = 8,
      cursorX = 0,
      onSelect = function(item)
        local slotId = item and item.value
        if slotId and slotId ~= "__none__" then
          SaveData.setActiveSlot(version, slotId)
          Stack.pop(id)
        end
      end,
      onCancel = function()
        Stack.pop(id)
      end,
    })

    Stack.push(id, menu, { hideBelow = true })
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
          openGame3SavePicker(g, s)
        end
        break
      end
    end
    return out
  end)

  -- Add SELECT SAVE to the native FireRed menu without replacing the
  -- title screen. The engine keeps menuItems local, so the extra row is
  -- handled only by this small input/draw shim.
  local Boot = require("src.ui.game3.boot")
  if not Boot._multiSaveSlotsWrapped then
    local originalUpdate = Boot.update
    local originalDraw = Boot.draw

    Boot.update = function(state, input, dt)
      if picker.open then
        handlePickerInput(input)
        return nil
      end

      if state.phase == Boot.PHASE.MENU and state.hasContinue and input
          and input.wasPressed then
        local pressed = function(k) return input:wasPressed(k) end

        if pressed("up") and state.menuIndex > 1 then
          state.menuIndex = state.menuIndex - 1
          state.menuScroll = state.menuIndex >= 4 and 4 or 0
          playMenuSe("SE_SELECT")
          return nil
        end
        if pressed("down") then
          local maxIndex = 5
          if state.menuIndex < maxIndex then
            state.menuIndex = state.menuIndex + 1
          end
          state.menuScroll = state.menuIndex >= 4 and 4 or 0
          playMenuSe("SE_SELECT")
          return nil
        end

        if pressed("a") or pressed("start") then
          if state.menuIndex == 2 then
            local game = state.game
            local Runtime = require("src.core.game3.runtime")
            if not game then game = Runtime._game end
            local session = game and game.session
            playMenuSe("SE_SELECT")
            openPicker(game, session, "load")
            return nil
          end

          -- Translate our inserted row out before giving native FireRed
          -- choices back to the original Boot implementation.
          local nativeIndex = state.menuIndex > 2 and state.menuIndex - 1
            or state.menuIndex
          state.menuIndex = nativeIndex
          local result = originalUpdate(state, input, dt)
          state.menuIndex = nativeIndex > 1 and nativeIndex + 1 or nativeIndex
          return result
        end
      end

      return originalUpdate(state, input, dt)
    end

    Boot.draw = function(state)
      originalDraw(state)

      if state.phase ~= Boot.PHASE.MENU or not state.hasContinue
          or state.saveError then
        if picker.open then drawPicker() end
        return
      end

      local Window = require("src.ui.game3.window")
      local RomText = require("src.core.game3.rom_text")
      local info = state.continueInfo or {}
      local frameType = info.frameType or 0
      local scroll = (state.menuScroll or 0) * 8

      -- Leave the native CONTINUE box completely untouched. Only replace the
      -- small option rows underneath it so SELECT SAVE takes one row.
      love.graphics.setColor(139 / 255, 148 / 255, 255 / 255, 1)
      love.graphics.rectangle("fill", 20, 96 - scroll, 204, 136)
      love.graphics.setColor(1, 1, 1, 1)

      local labels = {
        "SELECT SAVE",
        RomText.plain("gText_NewGame"),
        RomText.plain("gText_MysteryGift"),
        RomText.plain("gText_MenuExit"),
      }
      local ys = { 104, 136, 168, 200 }

      for i = 1, 4 do
        local yy = ys[i] - scroll
        Window.userFrame(Window.template(3, math.floor(yy / 8), 24, 2), frameType)
        local text = labels[i]
        Window.printPx(text, 26, yy + 2, {
          colors = {
            fg = {98 / 255, 98 / 255, 98 / 255, 1},
            shadow = {213 / 255, 213 / 255, 205 / 255, 1},
            bg = {1, 1, 1, 1},
          },
        })
      end

      if state.menuIndex > 1 then
        -- FireRed dims everything outside the selected option's row.
        local row = state.menuIndex - 2
        local y0 = 98 + row * 32 - scroll
        local y1 = 126 + row * 32 - scroll
        love.graphics.setColor(0, 0, 0, 7 / 16)
        love.graphics.rectangle("fill", 0, 0, 240, math.max(0, y0))
        love.graphics.rectangle("fill", 0, y1, 240, 240 - y1)
        love.graphics.rectangle("fill", 0, y0, 18, y1 - y0)
        love.graphics.rectangle("fill", 222, y0, 18, y1 - y0)
        love.graphics.setColor(1, 1, 1, 1)
      end

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
