local dump = cs2.get_schema_dump()
if not dump then
    engine.log("Schema dump not available.", 255, 0, 0, 255)
    return
end
local url = "https://csnades.gg/_next/static/media/smoke-icon.a2d4dd7a.png"
local icon = render.create_bitmap_from_url(url) 
local config = {
    bar_width = 40,
    bar_height = 5,
    background_color = {
        r = 30,
        g = 30,
        b = 30,
        a = 255
    },
    progress_color = {
        r = 255,
        g = 255,
        b = 255,
        a = 255
    },
    outline_color = {
        r = 30,
        g = 30,
        b = 30,
        a = 255,
    }

}
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
    Entity_identity = 0x10,
    m_designerName = dumps.CEntityIdentity.m_designerName,
    m_pGameSceneNode = dumps.C_BaseEntity.m_pGameSceneNode,
    m_vecOrigin = dumps.CGameSceneNode.m_vecOrigin,
    m_flSimulationTime = dumps.C_BaseEntity.m_flSimulationTime,
    m_nSmokeEffectTickBegin = dumps.C_SmokeGrenadeProjectile.m_nSmokeEffectTickBegin,
    flCurtime = 0x18 + 28
}
local function log(text)
    engine.log(tostring(text), 255, 255, 255, 255)
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

local function readVector(address) --- From @casey, thank you!
    local origin = {
        x = proc.read_float(address) or 0,
        y = proc.read_float(address + 4) or 0,
        z = proc.read_float(address + 8) or 0,
    }
    return origin
end


local get_projectales = function()
    local highest_index = cs2.get_highest_entity_index()
    local global_vars = cs2.get_global_vars()
    local flCurtime = proc.read_float(global_vars + 0x18 + 28)
    for i = 0, highest_index do
        local entity_identity = proc.read_int64(get_entity(i) + 0x10)
        if entity_identity ~= 0 then
            local designerentry = proc.read_int64(entity_identity + offset.m_designerName)
            if designerentry ~= 0 then
                local desginername = proc.read_string(designerentry, 32)
                if desginername == "smokegrenade_projectile" then
                    local m_pGameSceneNode = proc.read_int64(get_entity(i) + offset.m_pGameSceneNode)
                    local m_vecOrigin = readVector(m_pGameSceneNode + offset.m_vecOrigin)
                    local m_nSmokeEffectTickBegin = proc.read_int32(get_entity(i) + offset.m_nSmokeEffectTickBegin)
                    local ticks_to_time = m_nSmokeEffectTickBegin * 0.015625
                    local flFraction = clamp((flCurtime - ticks_to_time) / 22.0, 0.0, 1.0)
                    local smoke_pos_x, smoke_pos_y = cs2.world_to_screen(m_vecOrigin.x, m_vecOrigin.y, m_vecOrigin.z)

                    if m_nSmokeEffectTickBegin ~= 0 then

                        local bar_width  = config.bar_width
                        local bar_height = config.bar_height

                        render.draw_rectangle(
                            smoke_pos_x - bar_width / 2, 
                            smoke_pos_y,            
                            bar_width,
                            bar_height,
                            config.background_color.r, config.background_color.g, 
                            config.background_color.b, config.background_color.a, 
                            1,
                            true
                        )

                        local filled_width = (1 - flFraction) * bar_width

                        render.draw_rectangle(
                            smoke_pos_x - bar_width / 2,
                            smoke_pos_y,
                            filled_width,
                            bar_height,
                            config.progress_color.r, config.progress_color.g, 
                            config.progress_color.b, config.progress_color.a,
                            1,
                            true
                        )

                        render.draw_rectangle(
                            smoke_pos_x - bar_width / 2, smoke_pos_y, bar_width, bar_height,
                            config.outline_color.r, config.outline_color.g,
                            config.outline_color.b, config.outline_color.a,
                            1,
                            false
                        )

                        local icon_w = 32
                        local icon_h = 32

                        local icon_x = smoke_pos_x - (icon_w / 2)
                        local icon_y = smoke_pos_y - icon_h - 5

                        render.draw_bitmap(icon, icon_x, icon_y, icon_w, icon_h, 255)
                    end
                end
            end
        end
    end
end

engine.register_on_engine_tick(get_projectales)