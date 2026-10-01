-- Multiple Save Slots for Gen 3.
-- CONTINUE loads a selected slot and SAVE writes to a selected slot.
-- NEW SAVE creates a slot immediately before the normal save runs.
-- MANAGE lets the player delete non-active slots.

return function(mod)
  local SaveData = require("src.core.SaveData")
  local GameVersion = require("src.core.GameVersion")
  local Strings = require("src.core.Strings")
  local TextBox = require("src.render.TextBox")
  local ChoiceBox = require("src.ui.ChoiceBox")
  local ListMenu = require("src.ui.ListMenu")
  local TitleState = require("src.ui.TitleState")
  local Game = require("src.core.Game")

  local function currentVersion(game)
    return (game and game.version) or GameVersion.get()
  end

  local function isGen3(version)
    return GameVersion.generation(version) == 3
  end

  local function syncOptions()
    local disk = SaveData.loadOptions()
    if disk and disk.saveSlots
        and Game and Game.save and Game.save.options then
      Game.save.options.saveSlots = disk.saveSlots
    end
  end

  -- Keep slot registries that were added by another save operation instead
  -- of letting an older in-memory options table erase them.
  local function mergeSaveSlots(diskSlots, memorySlots)
    local out = {}

    local function add(source)
      if type(source) ~= "table" then return end

      for version, registry in pairs(source) do
        if type(version) == "string" and type(registry) == "table"
            and isGen3(version) then
          local dst = out[version] or {
            list = {},
            active = nil,
            names = {},
          }

          local seen = {}
          for _, id in ipairs(dst.list) do
            seen[id] = true
          end

          for _, id in ipairs(registry.list or {}) do
            if type(id) == "string" and not seen[id] then
              dst.list[#dst.list + 1] = id
              seen[id] = true
            end
          end

          if type(registry.names) == "table" then
            for id, name in pairs(registry.names) do
              dst.names[id] = name
            end
          end

          if registry.active and seen[registry.active] then
            dst.active = registry.active
          elseif not dst.active and registry.active then
            dst.active = registry.active
          end

          out[version] = dst
        end
      end
    end

    add(diskSlots)
    add(memorySlots)

    for _, registry in pairs(out) do
      table.sort(registry.list, function(a, b)
        local na = tonumber(tostring(a):match("^slot(%d+)$")) or 0
        local nb = tonumber(tostring(b):match("^slot(%d+)$")) or 0
        return na < nb
      end)

      if registry.names and next(registry.names) == nil then
        registry.names = nil
      end

      if registry.active then
        local valid = false
        for _, id in ipairs(registry.list) do
          if id == registry.active then
            valid = true
            break
          end
        end
        if not valid then
          registry.active = registry.list[1]
        end
      elseif registry.list[1] then
        registry.active = registry.list[1]
      end
    end

    return out
  end

  -- SaveData already owns the actual Gen 3 slot files. This wrapper only
  -- protects the shared options registry from stale in-memory writes.
  if not SaveData._gen3MultiSlotOptionsWrapped then
    local stockSaveOptions = SaveData.saveOptions

    function SaveData.saveOptions(options, fs)
      if SaveData._gen3MultiSlotAuthoritative then
        local result = stockSaveOptions(options, fs)
        if result and Game and Game.save and Game.save.options
            and result.saveSlots then
          Game.save.options.saveSlots = result.saveSlots
        end
        return result
      end

      options = options or {}
      local disk = SaveData.loadOptions(fs)

      if disk and disk.saveSlots then
        options.saveSlots = mergeSaveSlots(
          disk.saveSlots,
          options.saveSlots
        )
      end

      local result = stockSaveOptions(options, fs)

      if result and Game and Game.save and Game.save.options
          and result.saveSlots then
        Game.save.options.saveSlots = result.saveSlots
      end

      return result
    end

    SaveData._gen3MultiSlotOptionsWrapped = true
  end

  if not SaveData._gen3MultiSlotDeleteWrapped then
    local stockDelete = SaveData.deleteSlot

    function SaveData.deleteSlot(version, slotId)
      if not isGen3(version or GameVersion.get()) then
        return stockDelete(version, slotId)
      end

      SaveData._gen3MultiSlotAuthoritative = true
      local ok, err = stockDelete(version, slotId)
      SaveData._gen3MultiSlotAuthoritative = false
      syncOptions()

      return ok, err
    end

    SaveData._gen3MultiSlotDeleteWrapped = true
  end

  if not SaveData._gen3MultiSlotCreateWrapped then
    local stockCreate = SaveData.createSlot

    function SaveData.createSlot(version)
      if not isGen3(version or GameVersion.get()) then
        return stockCreate(version)
      end

      SaveData._gen3MultiSlotAuthoritative = true
      local id = stockCreate(version)
      SaveData._gen3MultiSlotAuthoritative = false
      syncOptions()

      return id
    end

    SaveData._gen3MultiSlotCreateWrapped = true
  end

  local function slotRows(version, allowNew, allowManage)
    if not isGen3(version) then return {} end

    local rows = {}
    local active = SaveData.activeSlot(version)

    for _, slot in ipairs(SaveData.listSlots(version) or {}) do
      if slot.exists then
        local mark = slot.id == active and "*" or " "
        local name = slot.name or "SAVE"

        rows[#rows + 1] = {
          label = Strings("%s%s %s", mark, slot.id, name),
          value = slot.id,
          exists = true,
        }
      end
    end

    if allowNew then
      rows[#rows + 1] = {
        label = Strings("NEW SAVE"),
        value = "__new__",
      }
    end

    if allowManage then
      rows[#rows + 1] = {
        label = Strings("MANAGE"),
        value = "__manage__",
      }
    end

    return rows
  end

  local function confirmDelete(game, slotId, callback)
    local prompts = {
      Strings("Delete %s?", slotId),
      Strings("Are you sure?"),
      Strings("Last chance!\nDelete forever?"),
    }

    local function ask(index)
      game.stack:push(TextBox.new(game, prompts[index], function()
        game.stack:push(ChoiceBox.new(game, function(yes)
          if not yes then return end
          if index >= #prompts then
            callback()
          else
            ask(index + 1)
          end
        end))
      end))
    end

    ask(1)
  end

  local function openManageSlots(game, version, refresh)
    local function buildRows()
      local rows = {}
      local active = SaveData.activeSlot(version)

      for _, slot in ipairs(SaveData.listSlots(version) or {}) do
        if slot.exists then
          if slot.id == active then
            rows[#rows + 1] = {
              label = Strings("%s *ACTIVE", slot.id),
              value = slot.id,
              locked = true,
            }
          else
            rows[#rows + 1] = {
              label = Strings("DEL %s", slot.id),
              value = slot.id,
              locked = false,
            }
          end
        end
      end

      return rows
    end

    local rows = buildRows()

    if #rows == 0 then
      game.stack:push(TextBox.new(game, Strings("No slots.")))
      return
    end

    local menu
    menu = ListMenu.new(game, Strings("DELETE SLOT"), rows, {
      onChoose = function(item)
        if item.locked then
          game.stack:push(TextBox.new(
            game,
            Strings("Can't delete the active slot.\fSwitch first.")
          ))
          return
        end

        confirmDelete(game, item.value, function()
          local ok, err = SaveData.deleteSlot(version, item.value)

          if ok then
            menu.items = buildRows()
            menu.index = math.max(
              1,
              math.min(menu.index or 1, #menu.items)
            )
            menu.scroll = 0

            if refresh then refresh() end

            game.stack:push(TextBox.new(game, Strings("Deleted.")))
          else
            game.stack:push(TextBox.new(
              game,
              Strings("Couldn't delete.\n%s", tostring(err or ""))
            ))
          end
        end)
      end,
    })

    game.stack:push(menu)
  end

  local function openSlotPicker(game, options)
    local version = currentVersion(game)
    if not isGen3(version) then return end

    local rows = slotRows(
      version,
      options.allowNew,
      options.allowManage
    )

    if #rows == 0 then
      game.stack:push(TextBox.new(game, Strings("No save slots.")))
      return
    end

    local menu

    local function rebuild()
      menu.items = slotRows(
        version,
        options.allowNew,
        options.allowManage
      )
      menu.index = math.max(
        1,
        math.min(menu.index or 1, #menu.items)
      )
      menu.scroll = 0
    end

    menu = ListMenu.new(game, options.title or Strings("SLOTS"), rows, {
      onChoose = function(item)
        if item.value == "__manage__" then
          openManageSlots(game, version, rebuild)
          return
        end

        if item.value == "__new__" then
          local id = SaveData.createSlot(version)

          if not id then
            game.stack:push(TextBox.new(
              game,
              Strings("Can't create.")
            ))
            return
          end

          SaveData.setActiveSlot(version, id)
          syncOptions()

          if menu.close then menu:close() end
          if options.onPick then
            options.onPick(id, true)
          end
          return
        end

        SaveData.setActiveSlot(version, item.value)
        syncOptions()

        if menu.close then menu:close() end
        if options.onPick then
          options.onPick(item.value, false)
        end
      end,
    })

    game.stack:push(menu)
  end

  -- Replace the Gen 3 title-screen CONTINUE action with a slot picker.
  if not TitleState._gen3MultiSlotWrapped then
    local originalOpenMenu = TitleState.openMenu

    function TitleState:openMenu()
      originalOpenMenu(self)

      if not isGen3(currentVersion(self.game)) then return end

      local top = self.game.stack and self.game.stack:top()
      if not (top and top.items) then return end

      for _, item in ipairs(top.items) do
        if tostring(item.label or ""):find("CONTINUE", 1, true) then
          local originalSelect = item.onSelect

          item.onSelect = function()
            openSlotPicker(self.game, {
              title = Strings("LOAD SLOT"),
              allowNew = false,
              allowManage = true,
              onPick = function()
                if originalSelect then
                  originalSelect()
                end
              end,
            })
          end

          break
        end
      end
    end

    TitleState._gen3MultiSlotWrapped = true
  end

  -- Replace the in-game SAVE action with a slot picker.
  mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
    items = next(game, items) or items

    if not isGen3(currentVersion(game)) then
      return items
    end

    for _, item in ipairs(items) do
      local label = tostring(item.label or "")

      if label == "SAVE"
          or (label:find("SAVE", 1, true)
              and not label:find("SLOT", 1, true)) then
        local originalSelect = item.onSelect

        item.onSelect = function()
          openSlotPicker(game, {
            title = Strings("SAVE TO"),
            allowNew = true,
            allowManage = true,
            onPick = function()
              if originalSelect then
                originalSelect()
              end
            end,
          })
        end

        break
      end
    end

    return items
  end)

  mod.events:on("game.ready", function()
    local version = currentVersion(Game)
    if not isGen3(version) then return end
    pcall(SaveData.refreshSlotResolution, version)
    pcall(syncOptions)
  end)

  mod.exports.version = "1.0.0"
  mod.log:info("GEN3_MULTI_SAVE_SLOTS 1.0.0")
end
