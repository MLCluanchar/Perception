
local FOV = 120

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
    LocalPlayerPawn = cs2.get_local_player().pawn, 
    dwLocalPlayerController = cs2.get_local_player().controller,

    m_pCameraServices = dumps.C_BasePlayerPawn.m_pCameraServices,
    m_iFOV = dumps.CCSPlayerBase_CameraServices.m_iFOV,
    m_iDesiredFOV = dumps.CBasePlayerController.m_iDesiredFOV,
    m_bIsScoped = dumps.C_CSPlayerPawn.m_bIsScoped, 
}

local process = {
    is_open = false,
    client_dll = 0,
    engine_dll = 0,
    screen_x = 0,
    screen_y = 0,
}

local function log(text)
    engine.log(tostring(text), 255, 255, 255, 255)
end


local function initialize_process()
    if process.client_dll ~= 0 and process.engine_dll ~= 0 then
    
        return true
    end

    local base_address = proc.base_address()
    if base_address == nil or base_address == 0 then
        log("Failed to get base address.")
        return false
    end

    local client_address = proc.find_module("client.dll")
    if client_address == nil or client_address == 0 then
        log("Failed to find client.dll.")
        return false
    end

    local engine_address = proc.find_module("engine2.dll")
    if engine_address == nil or engine_address == 0 then
        log("Failed to find engine2.dll.")
        return false
    end
   
    process.is_open = proc.is_attached()
    if not process.is_open then
        log("Process not attached.")
        return false
    end

    process.client_dll = client_address
    process.engine_dll = engine_address
    process.screen_x, process.screen_y = render.get_viewport_size()
    
    log("Process initialized successfully.")
    return true
end


local FOV_changer = function()
    initialize_process()
    local m_pCameraServices = proc.read_int64(offset.LocalPlayerPawn + offset.m_pCameraServices)    
    local m_bIsScoped = proc.read_int8(offset.LocalPlayerPawn + offset.m_bIsScoped) == 1 and true or false

    if not m_bIsScoped then
        proc.write_int32(offset.dwLocalPlayerController + offset.m_iDesiredFOV, FOV)
        proc.write_int32(m_pCameraServices + offset.m_iFOV, FOV)
    end
end

engine.register_on_engine_tick(FOV_changer)
log("FOV Changer script loaded.")