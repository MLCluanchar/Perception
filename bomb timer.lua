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

local my_font = render.create_font("Verdana", 10, 400)

local offset = {
    Entity_identity = 0x10,
    m_bBeingDefused = dumps.C_PlantedC4.m_bBeingDefused,
    m_flDefuseCountDown = dumps.C_PlantedC4.m_flDefuseCountDown,
    m_nBombSite = dumps.C_PlantedC4.m_nBombSite,
    m_flC4Blow = dumps.C_PlantedC4.m_flC4Blow,
    m_bBombDefused = dumps.C_PlantedC4.m_bBombDefused,
    m_flTimerLength = dumps.C_PlantedC4.m_flTimerLength,
    flCurtime = 0x18 + 28
}

function GetSchemaName(thisPtr)
    local uEntityIdentity = proc.read_int64(thisPtr + 0x10)
    if not uEntityIdentity or uEntityIdentity == 0 then
        return ""
    end

    local uEntityClassInfo = proc.read_int64(uEntityIdentity + 0x8)
    if not uEntityClassInfo or uEntityClassInfo == 0 then return 0 end

    local uSchemaClassInfoData = proc.read_int64(uEntityClassInfo + 0x28)
    if not uSchemaClassInfoData or uSchemaClassInfoData == 0 then return 0 end

    local uNamePointer = proc.read_int64(uSchemaClassInfoData + 0x8)
    if not uNamePointer or uNamePointer == 0 then return 0 end

    local strSchemaName = proc.read_string(uNamePointer, 32)
    if not strSchemaName or strSchemaName == "" then
        return ""
    end

    return strSchemaName
end

local function clamp(value, minVal, maxVal)
    if value < minVal then
        return minVal
    elseif value > maxVal then
        return maxVal
    end
    return value
end

local function get_entity(index)
    local entity_game_system = cs2.get_entity_list()
    if not entity_game_system or entity_game_system == 0 then
        return 0
    end

    if index > 32766 or (index // 512) > 0x3F then
        return 0
    end

    local ptr = proc.read_int64(entity_game_system + 8 * (index // 512) + 16)
    if not ptr or ptr == 0 then
        return 0
    end

    local v3 = 120 * (index % 512) + ptr
    if v3 == 0 then
        return 0
    end

    local entity_ptr = proc.read_int64(v3)
    if not entity_ptr or entity_ptr == 0 then
        return 0
    end

    return entity_ptr
end

local function bomb_colour(time)
	if time >= 10 then
		return {50,  255, 50}
	elseif time >= 5 then
		return {255, 180, 0}
	else
		return {255, 22, 22}
	end
end

local function defuse_colour(bool)
    if not bool then
        return {30, 30, 220}
    else
        return {255, 22, 22}
    end
end

local progress_bar = function(screen_h, bar_x, bar_y, percentage, bar_width, color, time, bg)
    local fill_height = (percentage * screen_h)
    local fill_y = screen_h - fill_height
    local bar_max_height = screen_h * 1
    if bg then
        render.draw_rectangle(
            bar_x,
            bar_y,
            bar_width,
            bar_max_height,
            50, 50, 50, 180,
            1,
            true
        )
    end
    render.draw_rectangle(
        bar_x,
        fill_y,
        bar_width,
        fill_height,
        color[1], color[2], color[3], 180, 
        1,
        true
    )

    local text_str = string.format("%.1f", time)
    local textWidth = render.measure_text(my_font, text_str)
    local text_x = bar_x - (textWidth / 2)  + 11  
    local text_y = fill_y - 12
    render.draw_text(my_font, text_str, text_x, text_y, 255, 255, 255, 255, 0, 0, 0, 0, 0)
end

local get_projectales = function()
    local highest_index = cs2.get_highest_entity_index()
    local global_vars = cs2.get_global_vars()
    local flCurtime = proc.read_float(global_vars + 0x18 + 28)
    for i = 0, highest_index do
        local entity = get_entity(i)
        local Schema_name = GetSchemaName(entity)
        if Schema_name == "C_PlantedC4" then
            local m_flTimerLength = proc.read_float(get_entity(i) + offset.m_flTimerLength)
            local m_bBeingDefused = proc.read_int8(get_entity(i) + offset.m_bBeingDefused)
            local m_flDefuseCountDown = proc.read_float(get_entity(i) + offset.m_flDefuseCountDown)
            local m_flC4Blow = proc.read_float(get_entity(i) + offset.m_flC4Blow)
            local m_bBombDefused = proc.read_int8(get_entity(i) + offset.m_bBombDefused)
            local explode_time = m_flC4Blow - flCurtime
            local defuse_time = m_flDefuseCountDown -flCurtime
            local flTimePercentage = clamp(explode_time / m_flTimerLength, 0, 1)
            local flDefusePercentage = clamp(defuse_time / m_flTimerLength, 0, 1)
            local screen_w, screen_h = render.get_viewport_size()
            if flTimePercentage ~= 0 and m_bBombDefused == 0 then
                local bomb_set = {
                    x = 0, y = 0,
                    width = 22, color = bomb_colour(explode_time)
                }
                progress_bar(screen_h, bomb_set.x, bomb_set.y, flTimePercentage, bomb_set.width, bomb_set.color, explode_time, true)
                if m_bBeingDefused ~= 0 then
                    local defuse_set = {
                        x = 0 + bomb_set.width + bomb_set.x, y = 0,
                        width = 22, color = defuse_colour(defuse_time > explode_time)
                    }
                    progress_bar(screen_h, defuse_set.x, defuse_set.y, flDefusePercentage, defuse_set.width, defuse_set.color, defuse_time, false)
                end
            end
        end
    end
end

engine.register_on_engine_tick(get_projectales)