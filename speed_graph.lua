local min, max, abs, sqrt, floor, acos, pi, pow = math.min, math.max, math.abs, math.sqrt, math.floor, math.acos, math.pi, math.pow
local graph_config = {
    jump = true,
    alpha = 230,
    MaxY = 400,
    Width = 400,
    Compression = 3,
    Frequency = 10,
    Spread = 15,
}

local process = {
    is_open = false,
    client_dll = 0,
    engine_dll = 0,
    screen_x = 0,
    screen_y = 0,
}

local dump = cs2.get_schema_dump()

if not dump then
    engine.log("Schema dump not available.", 255, 0, 0, 255)
    return
end

local dumps = {}

for _, entry in ipairs(dump) do
    local className, fieldName = entry.name:match("(.*)::(.*)")
    if className and fieldName then
        if not dumps[className] then
            dumps[className] = {}
        end
        dumps[className][fieldName] = entry.offset
    end
end

local offset = {
    local_pawn = cs2.get_local_player().pawn,
    m_lifeState = dumps.C_BaseEntity.m_lifeState,
    m_MoveType  = dumps.C_BaseEntity.m_MoveType,
    m_nActualMoveType = dumps.C_BaseEntity.m_nActualMoveType, 
    m_vecVelocity = dumps.C_BaseEntity.m_vecVelocity,
    m_vOldOrigin = dumps.C_BasePlayerPawn.m_vOldOrigin,
    m_fFlags = dumps.C_BaseEntity.m_fFlags,
}

local delayedCalls = {}

local small_font = render.create_font("Smallest Pixel-7", 10, 400)
local my_font = render.create_font("Verdana", 25, 400)

local function delay_call(delay_ms, callback)
    local now = winapi.get_tickcount64()

    local exec_time = now + delay_ms
    table.insert(delayedCalls, { time = exec_time, func = callback })
end

local function update_delayed_calls()
    local now = winapi.get_tickcount64()
    local i = 1
    while i <= #delayedCalls do
        local call = delayedCalls[i]
        if now >= call.time then
            table.remove(delayedCalls, i)
            call.func()
        else
            i = i + 1
        end
    end
end

local function initialize_process()
    local base_address = proc.base_address()
    if base_address == nil or base_address == 0 then
        return
    end

    local client_address = proc.find_module("client.dll")
    if client_address == nil or client_address == 0 then
        return
    end

    local engine_address = proc.find_module("engine2.dll")
    if engine_address == nil or engine_address == 0 then
        return
    end
    
    process.is_open = proc.is_attached()
    process.client_dll = client_address
    process.engine_dll = engine_address

    process.screen_x, process.screen_y = render.get_viewport_size()
end

local function colour(dist)
	if dist >= 235 then
		return {255, 137, 34}
	elseif dist >= 230 then
		return {255, 33, 33}
	elseif dist >= 227 then
		return {57, 204, 96}
	elseif dist >= 225 then
		return {91, 225, 255}
	else
		return {170, 170, 170}
	end
end

local lastVel = 0
local tickPrev = 0
local history = {}
local lastGraph = 0

local jumping = false
local jumpPos
local landPos
local jumpSpeed

local lastJump = 0
local graphSetJump = false
local graphSetLand = false


local function round(number, decimals)
	local power = 10^decimals
	return math.floor(number * power) / power
end

local function readVector(address) --- From @casey, thank you!
    local origin = {
        x = proc.read_float(address) or 0,
        y = proc.read_float(address + 4) or 0,
        z = proc.read_float(address + 8) or 0,
    }
    return origin
end

local function setup_command(cmd)

    local local_pawn = offset.local_pawn
	local localplayer = local_pawn
	if localplayer == nil then return end

	local flags = (math.floor(proc.read_int32(local_pawn + offset.m_fFlags)))
    local onground = ((flags - math.floor(flags / 2) * 2) == 1)

    local movetype = (proc.read_int32(local_pawn + offset.m_MoveType))
    if movetype == 2313 then -- ladder
		jumping = false
		landPos = {nil, nil, nil}
		graphSetLand = true
		return
	end

	if not onground and not jumping then

		local origin = readVector(local_pawn + offset.m_vOldOrigin)
		if origin.x == nil then return end

		local velocity = readVector(local_pawn + offset.m_vecVelocity)
		if velocity.x == nil then return end

		graphSetJump = true
		jumping = true
		jumpPos = {origin.x, origin.y, origin.z}
		jumpSpeed = floor(min(10000, sqrt(velocity.x*velocity.x + velocity.y*velocity.y) + 0.5))

		local thisTick = winapi.get_tickcount64()
		lastJump = thisTick

        delay_call(4000, function()
			if lastJump == thisTick then
				jumpSpeed = nil
			end
		end)
	end

    if jumping and onground then
		local origin = readVector(local_pawn + offset.m_vOldOrigin)
		if origin.x == nil then return end

		jumping = false
		landPos = {origin.x, origin.y, origin.z}
		graphSetLand = true
	end        
end


local function speedgraph(ctx, vel, x, y, tickNow)

    local local_pawn = offset.local_pawn
    local velocity = readVector(local_pawn + offset.m_vecVelocity)
    local vel = floor(min(10000, sqrt(velocity.x*velocity.x + velocity.y*velocity.y) + 0.5))

    x = process.screen_x/2
    y = process.screen_y/1.2

	local alpha = graph_config.alpha
	local graphMaxY = graph_config.MaxY

	local w = graph_config.Width

	local graphCompression = graph_config.Compression

	local graphFreq = graph_config.Frequency
	local graphSpread = graph_config.Spread/10

	x = x - w/2

    tickNow = winapi.get_tickcount64()

	if lastGraph + graphFreq < tickNow then
		local temp = {}
		temp.vel = min(vel, graphMaxY)
		if graphSetJump then
			graphSetJump = false
			temp.jump = true
			temp.jumpSpeed = jumpSpeed
			temp.jumpPos = jumpPos
		end

		if graphSetLand then
			graphSetLand = false
			temp.landed = true
			temp.landPos = landPos
		end

		table.insert(history, temp)
		lastGraph = tickNow
	end

	local over = #history - w / graphSpread
	if over > 0 then
		table.remove(history, 1)
	end

	for i = 2, #history, 1 do
		local val = history[i].vel
		local prevVal = history[i - 1].vel

		local curX = x + ((i * graphSpread))
		local prevX = x + ((i - 1) * graphSpread)

		local curY = y - (val / graphCompression)
		local prevY = y - (prevVal / graphCompression)

		-- show jumps
		if graph_config.jump then
			if history[i].jump then
				local index
				-- local jumpbug = false
				for q = i + 1, #history, 1 do
					if history[q].jump then
						index = q
						-- jumpbug = true
						break
					end

					if history[q].landed then
						index = q
						break
					end
				end

				local above = 13

				if index then
					if history[index].landPos and history[index].landPos[1] then
						local jSpeed = history[i].jumpSpeed
						local lSpeed = history[index].vel
						local speedGain = lSpeed - jSpeed
						if speedGain > -100 then
							local jPos = history[i].jumpPos
							local lPos = history[index].landPos
							local distX = abs(lPos[1] - jPos[1])
							local distY = abs(lPos[2] - jPos[2])
							local distZ = abs(lPos[3] - jPos[3]) -- up/down
                            local distance = math.sqrt((distX * distX) + (distY * distY)) + 32
							if distance > 150 then
								local jumpX = curX - 1
								local jumpY = curY

								local landX = x + ((index * graphSpread))
								local landY = y - (history[index].vel / graphCompression)

								local topY = landY - above
								if topY > jumpY or topY > jumpY - above then
									topY = jumpY - above
								end

								render.draw_line(jumpX, jumpY, jumpX, topY, 255, 255, 255, max(alpha - 55, 50), 1)
								render.draw_line(landX, topY, landX, landY, 255, 255, 255, max(alpha - 55, 50), 1)

								local text = speedGain > 0 and "+" or ""
								text = text .. tostring(speedGain)

								local middleX = (jumpX + landX) / 2

								local textWidth = render.measure_text(small_font, text)
								render.draw_text(
									small_font,
									text,
									middleX - textWidth * 0.5,
									topY - 13,
									255, 255, 255, alpha,
									0,
									255, 255, 255, 255
								)

								local ljColour = colour(distance)
								local distanceText = "(" .. round(distance, 0) .. ")"
								local distanceWidth = render.measure_text(small_font, distanceText)
								render.draw_text(
									small_font,
									distanceText,
									middleX - distanceWidth * 0.5,
									topY,
									ljColour[1], ljColour[2], ljColour[3], alpha,
									0,
									ljColour[1], ljColour[2], ljColour[3], alpha
								)
							end
						end
					end
				end			
            end
		end
		render.draw_line(prevX, prevY, curX, curY, 255, 255, 255, alpha, 1)
	end
end

local function on_engine_tick()
    local local_pawn = offset.local_pawn
    local velocity = readVector(local_pawn + offset.m_vecVelocity)
    local speed = floor(min(10000, sqrt(velocity.x*velocity.x + velocity.y*velocity.y) + 0.5))
	if speed == nil then return end

    update_delayed_calls()
    setup_command()
    
    local sx, sy = process.screen_x, process.screen_y
    local x = sx/2
    local y = sy/1.2
    local tickNow = winapi.get_tickcount64()

    speedgraph(speed, process.screen_x, process.screen_y - 27, tickNow)

    local r, g, b = 255, 255, 255

    if lastVel < speed then
        r, g, b = 30, 255, 109
    end

    if lastVel == speed then
        r, g, b = 255, 199, 89
    end

    if lastVel > speed then
        r, g, b = 255, 119, 119
    end

    local text = tostring(speed)

    if jumpSpeed then
        text = text .. " (" .. jumpSpeed .. ")"
    end

	local distanceWidth = render.measure_text(my_font, text)
    render.draw_text(
        my_font, text, x - distanceWidth * 0.5, y,
        r, g, b, 255, 1, r, g, b, 255       
    )

    if tickPrev + 5 < tickNow then
        lastVel = speed
        tickPrev = tickNow
    end

end

initialize_process()
engine.register_on_engine_tick(on_engine_tick)