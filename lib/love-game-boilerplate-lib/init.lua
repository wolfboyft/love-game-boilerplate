local path = (...):gsub("%.init$", "")

require(path .. ".monkeypatch")

local suit = require(path .. ".lib.suit")

local settings = require(path .. ".settings")
local config = require(path .. ".config")
local input = require(path .. ".input")
local assets = require(path .. ".assets")
local ui = require(path .. ".ui")

local takeScreenshot = require(path .. ".takeScreenshot")

local boilerplate = {}

boilerplate.settingsTypes = settings("meta")

function boilerplate.remakeWindow()
	local width = config.canvasSystemWidth * settings.graphics.scale
	local height = config.canvasSystemHeight * settings.graphics.scale
	love.window.setMode(width, height, {
		vsync = settings.graphics.vsync,
		fullscreen = settings.graphics.fullscreen,
		borderless = settings.graphics.fullscreen and settings.graphics.borderlessFullscreen,
		display = settings.graphics.display
	})
end

local function paused()
	return ui.current and ui.current.causesPause
end

function boilerplate.init(initConfig, arg)
	love.graphics.setDefaultFilter("nearest", "nearest")
	
	-- TODO: Make a table for all the input options and verify their presence, perhaps even validate them
	
	config.canvasSystemWidth, config.canvasSystemHeight = initConfig.canvasSystemWidth, initConfig.canvasSystemHeight
	
	-- Merge library-owned frame commands into frameCommands
	
	local frameCommands = initConfig.frameCommands
	
	frameCommands.pause = frameCommands.pause or "onRelease"
	
	frameCommands.toggleMouseGrab = frameCommands.toggleMouseGrab or "onRelease"
	frameCommands.takeScreenshot = frameCommands.takeScreenshot or "onRelease"
	frameCommands.toggleInfo = frameCommands.toggleInfo or "onRelease"
	frameCommands.previousDisplay = frameCommands.previousDisplay or "onRelease"
	frameCommands.nextDisplay = frameCommands.nextDisplay or "onRelease"
	frameCommands.scaleDown = frameCommands.scaleDown or "onRelease"
	frameCommands.scaleUp = frameCommands.scaleUp or "onRelease"
	frameCommands.toggleFullscreen = frameCommands.toggleFullscreen or "onRelease"
	
	frameCommands.uiPrimary = frameCommands.uiPrimary or "whileDown"
	frameCommands.uiSecondary = frameCommands.uiSecondary or "whileDown"
	frameCommands.uiModifier = frameCommands.uiModifier or "whileDown"
	
	-- TODO: Merge library-owned settings layout into settingsUiLayout, respecting categories! It will have to be decomposed into another format and recomposed into the settingsUiLayout format.
	
	-- Merge library-owned settings into settingsTemplate
	
	local settingsTypes = boilerplate.settingsTypes
	local settingsTemplate = initConfig.settingsTemplate
	
	settingsTemplate.graphics = settingsTemplate.graphics or {}
	settingsTemplate.graphics.fullscreen = settingsTemplate.graphics.fullscreen or settingsTypes.boolean(false)
	settingsTemplate.graphics.interpolation = settingsTemplate.graphics.interpolation or settingsTypes.boolean(true)
	settingsTemplate.graphics.scale = settingsTemplate.graphics.scale or settingsTypes.natural(2)
	settingsTemplate.graphics.display = settingsTemplate.graphics.display or settingsTypes.natural(1)
	settingsTemplate.graphics.maxTicksPerFrame = settingsTemplate.graphics.maxTicksPerFrame or settingsTypes.natural(4)
	settingsTemplate.graphics.vsync = settingsTemplate.graphics.vsync or settingsTypes.boolean(true)
	
	settingsTemplate.mouse = settingsTemplate.mouse or {}
	settingsTemplate.mouse.divideByScale = settingsTypes.boolean(true)
	settingsTemplate.mouse.xSensitivity = settingsTypes.number(1)
	settingsTemplate.mouse.ySensitivity = settingsTypes.number(1)
	settingsTemplate.mouse.cursorColour = settingsTypes.rgba(1, 1, 1, 1)
	
	settingsTemplate.useScancodesForCommands = settingsTemplate.useScancodesForCommands or settingsTypes.boolean(true)
	
	settingsTemplate.frameCommands = settingsTemplate.frameCommands or settingsTypes.commands("frame", {})
	local frameCommandsSettingDefaults = settingsTemplate.frameCommands(nil) -- HACK: Get defaults by calling with settingsTemplate.frameCommands with nil
	for commandName, inputType in pairs({
		pause = "escape",
		
		toggleMouseGrab = "f1",
		takeScreenshot = "f2",
		toggleInfo = "f3",
		
		previousDisplay = "f7",
		nextDisplay = "f8",
		scaleDown = "f9",
		scaleUp = "f10",
		toggleFullscreen = "f11",
		
		uiPrimary = 1,
		uiSecondary = 2,
		uiModifier = "lalt"
	}) do
		frameCommandsSettingDefaults[commandName] = frameCommandsSettingDefaults[commandName] or inputType
	end
	
	assets("configure", initConfig.assets)
	settings("configure", initConfig.settingsUiLayout, initConfig.settingsTemplate)
	
	config.frameCommands = initConfig.frameCommands
	config.fixedCommands = initConfig.fixedCommands
	
	ui.configure(initConfig.uiNames, initConfig.uiNamePathPrefix)
	
	local mouseMovedDt
	
	function love.run()
		love.load(love.arg.parseGameArguments(arg), arg)
		local lag = initConfig.fixedUpdateTickLength
		local updatesSinceLastDraw, lastLerp = 0, 1
		local performance
		love.timer.step()
		
		return function()
			love.event.pump()
			for name, a,b,c,d,e,f in love.event.poll() do -- Events
				if name == "quit" then
					if not love.quit() then
						return a or 0
					end
				end
				love.handlers[name](a,b,c,d,e,f)
			end
			
			do -- Update
				local delta = love.timer.step()
				mouseMovedDt = delta -- HACK
				lag = math.min(lag + delta, initConfig.fixedUpdateTickLength * settings.graphics.maxTicksPerFrame)
				local frames = math.floor(lag / initConfig.fixedUpdateTickLength)
				lag = lag % initConfig.fixedUpdateTickLength
				if not paused() then
					local start = love.timer.getTime()
					for _=1, frames do
						updatesSinceLastDraw = updatesSinceLastDraw + 1
						love.fixedUpdate(initConfig.fixedUpdateTickLength)
					end
					if frames ~= 0 then
						performance = (love.timer.getTime() - start) / (frames * initConfig.fixedUpdateTickLength)
					end
				else
					performance = nil
					if previousFramePaused then
						input.clearFixedCommandsList()
					end
				end
				love.update(dt, performance)
			end
			
			if love.graphics.isActive() then -- Rendering
				love.graphics.origin()
				love.graphics.clear(love.graphics.getBackgroundColor())
				
				local lerp = lag / initConfig.fixedUpdateTickLength
				deltaDrawTime = ((lerp + updatesSinceLastDraw) - lastLerp) * initConfig.fixedUpdateTickLength
				love.draw(lerp, deltaDrawTime, performance)
				updatesSinceLastDraw, lastLerp = 0, lerp
				
				love.graphics.present()
			end
			
			love.timer.sleep(0.001)
		end
	end
	
	function love.load(arg, unfilteredArg)
		settings("load")
		settings("apply")
		settings("save")
		assets("load")
		love.graphics.setFont(assets.ui.font.value)
		boilerplate.inputCanvas = love.graphics.newCanvas(config.canvasSystemWidth, config.canvasSystemHeight)
		boilerplate.outputCanvas = love.graphics.newCanvas(config.canvasSystemWidth, config.canvasSystemHeight)
		boilerplate.infoCanvas = love.graphics.newCanvas(config.canvasSystemWidth, config.canvasSystemHeight)
		input.clearRawCommands()
		input.clearFixedCommandsList()
		if boilerplate.load then
			boilerplate.load(arg, unfilteredArg)
		end
	end
	
	function love.update(dt)
		if input.didFrameCommand("pause") then
			if ui.current then
				if not ui.current.ignorePausePress then
					ui.destroy()
				end
			else
				ui.construct("plainPause")
			end
		end
		
		if input.didFrameCommand("toggleMouseGrab") then
			love.mouse.setRelativeMode(not love.mouse.getRelativeMode())
		end
		
		if input.didFrameCommand("takeScreenshot") then
			-- If uiModifier is held then takeScreenshot will include HUD et cetera.
			local screenshotCanvas
			takeScreenshot(input.didFrameCommand("uiModifier") and boilerplate.outputCanvas or boilerplate.inputCanvas)
		end
		
		if not ui.current or ui.current.type ~= "settings" then
			if input.didFrameCommand("toggleInfo") then
				settings.graphics.showPerformance = not settings.graphics.showPerformance
				settings("save")
			end
			
			if input.didFrameCommand("previousDisplay") and love.window.getDisplayCount() > 1 then
				settings.graphics.display = (settings.graphics.display - 2) % love.window.getDisplayCount() + 1
				settings("apply") -- TODO: Test thingy... y'know, "press enter to save or wait 5 seconds to revert"
				settings("save")
			end
			
			if input.didFrameCommand("nextDisplay") and love.window.getDisplayCount() > 1 then
				settings.graphics.display = (settings.graphics.display) % love.window.getDisplayCount() + 1
				settings("apply")
				settings("save")
			end
			
			if input.didFrameCommand("scaleDown") and settings.graphics.scale > 1 then
				settings.graphics.scale = settings.graphics.scale - 1
				settings("apply")
				settings("save")
			end
			
			if input.didFrameCommand("scaleUp") then
				settings.graphics.scale = settings.graphics.scale + 1
				settings("apply")
				settings("save")
			end
			
			if input.didFrameCommand("toggleFullscreen") then
				settings.graphics.fullscreen = not settings.graphics.fullscreen
				settings("apply")
				settings("save")
			end
		end
		
		if ui.current then
			ui.update()
		end
		
		if boilerplate.update then
			boilerplate.update(dt)
		end
		
		input.stepRawCommands(paused())
	end
	
	function love.fixedUpdate(dt)
		if boilerplate.fixedUpdate then
			boilerplate.fixedUpdate(dt)
		end
		
		boilerplate.fixedMouseDx, boilerplate.fixedMouseDy = 0, 0
		input.clearFixedCommandsList()
	end
	
	function love.draw(lerp, dt, performance)
		assert(boilerplate.outputCanvas:getWidth() == config.canvasSystemWidth)
		assert(boilerplate.outputCanvas:getHeight() == config.canvasSystemHeight)
		if settings.graphics.showPerformance then
			love.graphics.setCanvas(boilerplate.infoCanvas)
			love.graphics.clear(0, 0, 0, 0)
			love.graphics.print(
				"FPS: " .. love.timer.getFPS() .. "\n" ..
				-- "Garbage: " .. collectgarbage("count") * 1024 -- counts all memory for some reason
				"Tick time: " .. (performance and math.floor(performance * 100 + 0.5) .. "%" or "N/A"),
			1, 1)
		end
		if boilerplate.draw and not paused() then
			-- Draw to input canvas
			boilerplate.draw(settings.graphics.interpolation and lerp or 1, dt, performance)
		end
		love.graphics.setCanvas(boilerplate.outputCanvas)
		love.graphics.clear()
		if ui.current then love.graphics.setColor(initConfig.uiTint or {1, 1, 1}) end
		love.graphics.draw(boilerplate.inputCanvas)
		if settings.graphics.showPerformance then
			love.graphics.setColor(1, 1, 1)
			love.graphics.setShader(boilerplate.outlineShader)
			love.graphics.draw(boilerplate.infoCanvas, 1, 1)
			love.graphics.setShader()
		end
		if ui.current then
			suit.draw()
			if ui.current.draw then
				ui.current.draw() -- stuff SUIT can't do: rectangles, lines, etc
			end
			love.graphics.setColor(settings.mouse.cursorColour)
			love.graphics.draw(assets.ui.cursor.value, math.floor(ui.current.mouseX), math.floor(ui.current.mouseY))
		else
			-- draw HUD
		end
		love.graphics.setColor(1, 1, 1)
		love.graphics.setCanvas()
		
		love.graphics.draw(boilerplate.outputCanvas,
			love.graphics.getWidth() / 2 - (config.canvasSystemWidth * settings.graphics.scale) / 2, -- topLeftX == centreX - width / 2
			love.graphics.getHeight() / 2 - (config.canvasSystemHeight * settings.graphics.scale) / 2,
			0, settings.graphics.scale
		)
	end
	
	function love.quit()
		if not (boilerplate.quit and boilerplate.quit()) then
			if boilerplate.getUnsaved and boilerplate.getUnsaved() then
				-- TODO: Add config option for disabling double alt-f4 to quit without saving
				if ui.current and ui.current.type == "quitConfirmation" then
					return false
				else
					ui.construct("quitConfirmation")
					return true
				end
			end
		end
	end
	
	function love.mousemoved(x, y, dx, dy)
		if love.window.hasFocus() and love.window.hasMouseFocus() and love.mouse.getRelativeMode() then
			if ui.current then
				ui.mouse(dx, dy)
			else
				boilerplate.fixedMouseDx = boilerplate.fixedMouseDx + dx * mouseMovedDt
				boilerplate.fixedMouseDy = boilerplate.fixedMouseDy + dy * mouseMovedDt
			end
		end
	end
end

return boilerplate