local pconfig = ...
local luapath = pconfig.path .. "lua/"
local util = dofile(luapath .. "utils.lua")
local devices = dofile(luapath .. "device.lua")
dofile(luapath .. "json.lua")
dofile(luapath .. "net.lua")
local resources = dofile(luapath .. "resources.lua")
local refreshStates = dofile(luapath .. "refreshState.lua")
local timers = util.timerQueue()
local format = string.format

print(os.date("Lua loader started %c"))
local lldebugger
if os.getenv("LOCAL_LUA_DEBUGGER_VSCODE") == "1" then
    print("Waiting for debugger to attach...")
    local dname = os.getenv("LOCAL_LUA_DEBUGGER_FILEPATH")
    assert(dname, "Please set LOCAL_LUA_DEBUGGER_FILEPATH")
    local file = io.open(dname, "r")
    assert(file, "Could not open " .. dname)
    local data = file:read("*all")
    lldebugger = load(data)()
    lldebugger.start()
    print("Debugger attached")
else
    print("Not waiting for debugger")
end

local config
do
    local f = io.open("config.json", "r")
    assert(f, "Can't open config.json")
    config = json.decode(f:read("*all"))
    f:close()
    for k, v in pairs(pconfig) do if config[k] == nil then config[k] = v end end
    config.creds = util.basicAuthorization(config.user, config.password)
end

QA, DIR = { config = config }, {}
local gID = 5000

os.milliclock = config.hooks.clock
local clock = config.hooks.clock
os.http = config.hooks.http
os.refreshStates = config.hooks.refreshStates
config.hooks = nil
devices.init(luapath .. "devices.json")
resources.init(refreshStates)
resources.refresh(true)
refreshStates.init(resources)
refreshStates.start(config)

function QA.syslog(typ, fmt, ...)
    util.debug({ color = true }, typ, format(fmt, ...), "SYS")
end

local function systemTimer(fun, ms)
    local t = clock() + ms / 1000
    return timers.add(-1, t, fun, { type = 'timer', fun = fun, ms = t, log = "system" })
end

function string.split(str, sep)
    local fields, s = {}, sep or "%s"
    str:gsub("([^" .. s .. "]+)", function(c) fields[#fields + 1] = c end)
    return fields
end

local function log(fmt, ...) util.debug({color=true}, "", format(fmt, ...), "SYS") end
local function logerr(fmt, ...) util.debug({color=true}, "", format("Error : %s", format(fmt, ...)), "SYS") end

local function installQA(fname, id)
    local f = io.open(fname, "r")
    if not f then
        logerr("Install %s - %s", fname, "File not found")
        return
    end
    local code = f:read("*all")
    f:close()

    local name, ftype = fname:match("([%w_]+)%.([luafq]+)$")
    assert(ftype == "lua", "Unsupported file type - " .. tostring(ftype))


    local qaFiles = {}
    local chandler = {}
    function chandler.name(var, val, dev) dev.name = val end
    function chandler.type(var, val, dev) dev.type = val end
    function chandler.id(var, val, dev) dev.id = tonumber(id) end
    function chandler.file(var, val, dev)
        local fn, qn = table.unpack(val:sub(1, -2):split(","))
        dev.files = dev.files or {}
        dev.files[#dev.files + 1] = { fname = fn, qaname = qn }
    end

    local vars = {}
    code:gsub("%-%-%%%%([%w_]+)=(.-)[\n\r]", function(var, val)
        if chandler[var] then
            chandler[var](var, val, vars)
        else
            logerr("Load", "%s - Unknown header variable '%s'", fname, var)
        end
    end)
    table.insert(vars.files, { code = code, fname = fname, qaname = 'main' })

    if vars.id == nil then
        vars.id = gID; gID = gID + 1
    end
    id = vars.id

    local dev = devices.getDeviceStruct(vars.type or "com.fibaro.binarySwitch")
    dev.name = vars.name or "APP"
    dev.id = vars.id
    dev.properties.quickAppVariables = {}
    dev.interfaces = {}
    dev.parentId = 0

end

local function createQAstruct(fname, id)
    local env = {}
    local debugFlags, fmt = {}, string.format
    debugFlags.color = true

    local function log(str, fmt, ...) util.debug(debugFlags, env.__TAG, format("%s %s", str, format(fmt, ...)), "SYS") end
    local function logerr(str, fmt, ...) env.fibaro.error(env.__TAG, format("%s Error : %s", str, format(fmt, ...))) end

    local function setTimer(f, ms, log)
        assert(type(f) == 'function', "setTimeout first arg need to be function")
        assert(type(ms) == 'number', "setTimeout second arg need to be a number")
        local t = clock() + ms / 1000
        return timers.add(id, t, DIR[id].f, { type = 'timer', fun = f, ms = t, log = log or "" })
    end
    local function clearTimer(ref)
        assert(type(ref) == 'number', "clearTimeout ref need to be number")
        timers.remove(ref)
    end

    local funs = {
        "os", "pairs", "ipairs", "select", "print", "math", "string", "pcall", "xpcall", "table", "error",
        "next", "json", "tostring", "tonumber", "assert", "unpack", "utf8", "collectgarbage", "type",
        "setmetatable", "getmetatable", "rawset", "rawget", "coroutine" -- extra stuff
    }
    for _, k in ipairs(funs) do env[k] = _G[k] end
    env._G = env

    env.setTimeout = setTimer
    env.clearTimeout = clearTimer

    function env.__fibaroSleep(ms) end

    function env.__fibaro_get_global_variable(name) return resources.getResource("globalVariables", name) end

    function env.__fibaro_get_device(id) return resources.getResource("devices", id) end

    function env.__fibaro_get_devices() return util.toarray(resources.getResource("devices") or {}) end

    function env.__fibaro_get_room(id) return resources.getResource("rooms", id) end

    function env.__fibaro_get_scene(id) return resources.getResource("scenes", id) end

    function env.__fibaro_get_device_property(id, prop)
        local d = resources.getResource("devices", id)
        if d then
            local pv = (d.properties or {})[prop]
            return { value = pv, modified = d.modified or 0 }
        end
    end

    function env.__fibaro_get_breached_partitions() end

    function env.__fibaro_add_debug_message(tag, str, typ)
        assert(str, "Missing tag for debug")
        util.debug(debugFlags, tag, str, typ)
    end

    local f = io.open(fname, "r")
    if not f then
        logerr("Load", "%s - %s", fname, "File not found")
        return
    end
    local code = f:read("*all")
    f:close()

    local name, ftype = fname:match("([%w_]+)%.([luafq]+)$")
    local dev = {
        name = name,
        id = id,
        type = 'com.fibaro.binarySwitch',
        properties = { quickAppVariables = {}, value = {} },
        interfaces = {},
        parentId = 0
    }
    assert(ftype == "lua", "Unsupported file type - " .. tostring(ftype))

    local qaFiles = {}
    local chandler = {}
    function chandler.name(var, val, dev) dev.name = val end

    function chandler.type(var, val, dev) dev.type = val end

    function chandler.id(var, val, dev) dev.idtype = tonumber(id) end

    function chandler.file(var, val, dev)
        local fn, qn = table.unpack(val:sub(1, -2):split(","))
        qaFiles[#qaFiles + 1] = { fname = fn, qaname = qn }
    end

    code:gsub("%-%-%%%%([%w_]+)=(.-)[\n\r]", function(var, val)
        if chandler[var] then
            chandler[var](var, val, dev)
        else
            logerr("Load", "%s - Unknown header variable '%s'", fname, var)
        end
    end)

    if dev.id == nil then
        dev.id = gID; gID = gID + 1
    end
    id = dev.id

    env.plugin = { mainDeviceId = dev.id }
    env.__TAG = "QUICKAPP" .. dev.id

    for _, l in ipairs({ "json.lua", "class.lua", "net.lua", "fibaro.lua", "quickApp.lua" }) do
        log("Load", "library " .. luapath .. l)
        local stat, res = pcall(function() loadfile(luapath .. l, "t", env)() end)
        if not stat then
            logerr("Load", "%s - %s", fname, res)
            QA.delete(id)
            return
        end
    end

    env.fibaro.debugFlags = debugFlags
    env.fibaro.config = config
    if debugFlags.dark or config.dark then util.fibColors['TEXT'] = util.fibColors['TEXT'] or 'white' end

    table.insert(qaFiles, { code = code, fname = fname, qaname = 'main' })

    for _, qf in ipairs(qaFiles) do
        if qf.code == nil then
            local file = io.open(qf.fname, "r")
            assert(file, "File not found:" .. qf.fname)
            qf.code = file:read("*all")
            file:close()
        end
        log("Load", "loading user file " .. qf.fname)
        local qa, res = load(qf.code, qf.fname, "t", env) -- Load QA
        if not qa then
            logerr("Load", "%s - %s", qf.fname, res)
            return
        end
        qf.qa = qa
        qf.code = nil
        if qf.qaname == "main" and config['break'] and lldebugger then
            qf.qa = function() lldebugger.call(qa, true) end
        end
    end

    return { qafiles = qaFiles, env = env, dev = dev, logerr = logerr, log = log }
end

local function runner(fname, fc, id)
    local qastr = createQAstruct(fname, id)
    local qaf, env, dev, log, logerr = qastr.qafiles, qastr.env, qastr.dev, qastr.log, qastr.logerr
    local errfun = env.fibaro.error
    id = dev.id
    local function checkErr(str, f, ...)
        local ok, err = pcall(f, ...)
        if not ok then env.fibaro.error(env.__TAG, format("%s Error: %s", str, err)) end
    end

    DIR[dev.id] = { f = fc, fname = fname, env = env, dev = dev }
    resources.createDevice(dev)
    collectgarbage("collect")
    for _, q in ipairs(qaf) do
        log("Running", "%s", q.fname)
        local stat, err = pcall(q.qa) -- Start QA
        if not stat then
            logerr("Start", "%s - %s - restarting in 5s", q.fname, err)
            QA.delete(id)
            systemTimer(function() QA.start(fname, id) end, 5000)
        end
    end

    local stat, err = pcall(function()
        local qo = env.QuickApp(dev)
        env.quickApp = qo
    end)
    if not stat then
        logerr(":onInit()", "%s - restarting in 5s", err)
        QA.delete(id)
        systemTimer(function() QA.start(fname, id) end, 5000)
    end

    local ok, err
    while true do -- QA coroutine loop
        local task = coroutine.yield({ type = 'next', log = "X" })
        ::foo::
        if task.type == 'timer' then
            ok, err = pcall(task.fun)
            if not ok then errfun(env.__TAG, format("%s Error: %s", "timer", err)) end
            task = coroutine.yield({ type = 'next' })
            goto foo
            -- if task.type == 'timer' then
            --     checkErr("setTimeout", task.fun)
        elseif task.type == 'onAction' then
            checkErr("onAction", env.onAction, id, task)
        elseif task.type == 'UIEvent' then
            checkErr("UIEvent", env.onUIEvent, id, task)
        end
    end
end

local function createQA(runner, fname, id)
    local c = coroutine.create(runner)
    local function t(task)
        local res, task = coroutine.resume(c, task)
        --print("X",task.type,task.log,coroutine.status(c))
        if task.type == 'timer' then
            timers.add(id, clock() + task.ms, t, task)
            coroutine.resume(c)
        end
    end
    local stat, res = coroutine.resume(c, fname, t, id) -- Start QA
    if not stat then print(res) end
end

function QA.install(fname, id)
    installQA(fname, id)
    createQA(runner, fname, id)
end

function QA.start(fname, id)
    createQA(runner, fname, id)
end

function QA.restart(id)
    if DIR[id] then
        local fname = DIR[id].fname
        QA.delete(id)
        QA.start(fname, id)
    end
end

function QA.delete(id)
    if DIR[id] then
        timers.removeId(id)
        DIR[id] = nil
    end
    resources.removeDevice(id)
end

local eventHandler = {}

function eventHandler.onAction(event)
    local id = event.deviceId
    if not DIR[id] then return end
    timers.add(id, 0, DIR[id].f,
        { type = 'onAction', deviceId = id, actionName = event.actionName, args = event.args })
end

function eventHandler.uiEvent(event)
    local id = event.deviceId
    if not DIR[id] then return end
    timers.add(id, clock(), DIR[id].f,
        {
            type = 'UIEvent',
            deviceId = id,
            elementName = event.elementName,
            eventType = event.eventType,
            values = event.values or {}
        })
end

function eventHandler.updateView(event)
    print("UV", json.encode(event))
end

function eventHandler.refreshStates(event)
    refreshStates.newEvent(event.event)
end

function QA.onEvent(event) -- dispatch to event handler
    event = json.decode(event)
    local h = eventHandler[event.type]
    if h then h(event) else print("Unknown event", event.type) end
end

QA.fun = {}
for name, fun in pairs(resources) do QA.fun[name] = fun end -- export resource functions

function QA.loop()
    local t, c, task = timers.peek()
    local cl = clock()
    --if t then print("loop",task.type,t-cl) else print("loop") end
    if t then
        local diff = t - cl
        if diff <= 0 then
            timers.pop()
            c(task)
            return 0
        else
            return diff
        end
    end
    return 0.5
end
