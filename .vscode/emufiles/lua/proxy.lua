local fmt = string.format
local ui = fibaro.fibemu.libs.ui
function urlencode(str) -- very useful
  if str then
    str = str:gsub("\n", "\r\n")
    str = str:gsub("([^%w %-%_%.%~])", function(c)
      return ("%%%02X"):format(string.byte(c))
    end)
    str = str:gsub(" ", "%%20")
  end
  return str
end

local function copy(obj)
  if type(obj) == 'table' then
    local res = {} for k,v in pairs(obj) do res[k] = copy(v) end
    return res
  else return obj end
end

local function annotateUI(UI)
  local res, map = {}, {}
  for _, e in ipairs(UI) do
    if e[1] == nil then e = { e } end
    for _, e2 in ipairs(e) do
      e2.type = e2.button and 'button' or e2.slider and 'slider' or e2.label and 'label' or e2.select and 'select' or e2.switch and 'switch' or e2.multi and 'multi'
      map[e2[e2.type]] = e2
    end
    res[#res + 1] = e
  end
  return res, map
end

local sortKeys = {
  "button", "slider", "label","select","switch","multi",
  "text",
  "min", "max", "value",
  "visible",
  "onRelease", "onChanged",
}
local sortOrder = {}
for i, s in ipairs(sortKeys) do sortOrder[s] = "\n" .. string.char(i + 64) .. " " .. s end
local function keyCompare(a, b)
  local av, bv = sortOrder[a] or a, sortOrder[b] or b
  return av < bv
end

local function toLua(t)
  if type(t) == 'table' and t[1] then
    local res = {}
    for _, v in ipairs(t) do
      res[#res + 1] = toLua(v)
    end
    return "{" .. table.concat(res, ",") .. "}"
  else
    local res, keys = {}, {}
    for k, _ in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, keyCompare)
    for _, k in ipairs(keys) do
      local tk = type(t[k]) == 'table' and toLua(t[k]) 
        or (type(t[k]) == 'boolean' or type(t[k])=='number') and tostring(t[k])
        or '"'..t[k]..'"'
      res[#res + 1] = string.format('%s=%s', k, tk)
    end
    return "{" .. table.concat(res, ",") .. "}"
  end
end

fibaro.fibemu.toLua = toLua

function QuickApp:createProxy(id,name)
  local code = [[
  local fmt = string.format
  
  function QuickApp:onInit()
    self:debug("Started", self.name, self.id)
    quickApp = self
    local ip = nil
    local remoteID = nil
    local function urlencode (str)
      return str and string.gsub(str ,"([^% w])",function(c) return string.format("%%% 02X",string.byte(c))  end)
    end
  
    --setTimeout(function() fibaro.call(self.id,"foo",4,5,6) end,2000)
    local IGNORE={updateView=true,setVariable=true,updateProperty=true,MEMORYWATCH=true,PROXY=true,APIPOST=true,APIPUT=true,APIGET=true,_addInterfaces=true,_deleteInterfaces=true,_publishEvent} -- Rewrite!!!!
  
    local function CALLIDE(path,payload)
      local url = ip..path
      print(url)
      net.HTTPClient():request(url,{options={method="POST",data=payload and json.encode(payload) or nil}})
    end
  
    function quickApp:actionHandler(action)
      if IGNORE[action.actionName] then
        print(action.actionName)
        return quickApp:callAction(action.actionName, table.unpack(action.args))
      end
      if ip and remoteID then
        print(json.encode(action))
        CALLIDE("/api/devices/"..remoteID.."/action/_ProxyOnAction",{args = {action}})
      end
    end
  
     function quickApp:UIHandler(ev)
      if ip and remoteID then
        CALLIDE("/api/devices/"..remoteID.."/action/_ProxyUIHandler",{ args = {ev} })
      end
    end

    function QuickApp:_addInterfaces(id,ifs)
        api.post("/plugins/interfaces",{
          action="add",deviceId=id,interfaces=ifs
        })
     end
     function QuickApp:_deleteInterfaces(id,ifs)
             api.post("/plugins/interfaces",{
          action="delete",deviceId=id,interfaces=ifs
        })
     end
     function QuickApp:_publishEvent(data)
        api.post("/plugins/publishEvent",data)
     end
     
    function QuickApp:initChildDevices() end

    local function loop()
      local stat,res = pcall(function()
        local var,err = __fibaro_get_global_variable("FIBEMU")
        if var then
          local values =json.decode(var.value)
          ip = values.url
          local QA = values.QA or {}
          remoteID = QA[self.name]
        end
      end)
      if not stat then print(res) end
      setTimeout(loop,4000)
    end
    loop()
  end
]]
  
  local dev = api.get("/devices/"..id)
  local p = copy(dev.properties)
  p.viewLayout, p.uiView, p.uiCallbacks = ui.pruneStock(p)
  local props = {
    apiVersion = "1.3",
    quickAppVariables = p.quickAppVariables or {},
    uiCallbacks = #p.uiCallbacks > 0 and p.uiCallbacks or nil,
    viewLayout = p.viewLayout,
    uiView = p.uiView,
    useUiView=false,
    typeTemplateInitialized = true,
  }
  local fqa = {
    apiVersion = "1.3",
    name = name,
    type = dev.type,
    initialProperties = props,
    initialInterfaces = dev.interfaces,
    files = {{name="main", isMain=true, isOpen=false, type='lua', content=code}},
  }
  return api.post("/quickApp/", fqa, "hc3")
end

local function dumpUI(UI)
  local lines = {}
  for _, row in ipairs(UI or {}) do
    for _,l in ipairs(row) do l.type=nil end
    if not row[2] then row = row[1] end
    lines[#lines+1]="--%%u="..toLua(row)
  end
  print("Proxy UI:\n"..table.concat(lines,"\n"))
end

function fibaro.fibemu.dumpUIfromQA(id)
  local dev = api.get("/devices/"..id)
  if dev then 
    local p = dev.properties
    local uiStruct = ui.view2UI(p.viewLayout, p.uiCallbacks)
    dumpUI(uiStruct)
  else fibaro.error(__TAG,"Device not found:",id) end
end

function fibaro.callHC3(deviceId, actionName, ...)
  __assert_type(actionName, "string")
  __assert_type(deviceId, "number")
  local arg = { ... }; -- arg = #arg > 0 and arg or nil
  return api.post("/devices/" .. deviceId .. "/action/" .. actionName, {args = arg},"hc3")
end

function QuickApp:launchProxy(name)
  local p = api.get("/devices/?name="..urlencode(name))
  if p==nil or next(p)==nil then
    p = self:createProxy(self.id,name)
    if not p then
      self:error("Can't create proxy on HC3")
      return
    end
    self:trace("Proxy installed:",p.id,name)
  else
    p = p[1]
    self:trace("Proxy found:",p.id,name)
    -- Import UI from proxy
    local viewLayout = p.properties.viewLayout
    local uiView = p.properties.uiView
    local uiCallbacks = p.properties.uiCallbacks
    local myself = fibaro.fibemu.DIR[self.id]
    myself.dev.properties.viewLayout = viewLayout
    myself.dev.properties.uiCallbacks = uiCallbacks
    myself.dev.properties.uiView = uiView
    self.uiCallbacks = {}
    self:registerUICallbacks()
    local uiStruct = ui.view2UI( myself.dev.properties.viewLayout,  myself.dev.properties.uiCallbacks)
    local uiStruct, uiMap = annotateUI(uiStruct)
    myself.uiMap = uiMap
    myself.UI = uiStruct
    
    dumpUI(myself.UI)
  end
  self._proxyId = p.id
  local data = fibaro.fibemu.libs.refreshStates.hookVarData
  data.QA = data.QA or {}
  data.QA[name] = self.id
  
  
  api._intercept("POST","/plugins/updateView",function(m,path,data,hc3)
    if data.deviceId == self.id or self.childDevices[data.deviceId] then
      data = copy(data)
      if data.deviceId == self.id then data.deviceId = self._proxyId end
      local data2,res = api.post("/plugins/updateView",data,"hc3")
      return true,data2,res
    end
    return false
  end)
  
  api._intercept("POST","/plugins/updateProperty",function(m,path,data,hc3)
    if data.deviceId == self.id or self.childDevices[data.deviceId] then
      data = copy(data)
      if data.deviceId == self.id then data.deviceId = self._proxyId end
      local data2,res = api.post("/plugins/updateProperty",data,"hc3")
      return true,data2,res
    end
    return false
  end)

  api._intercept("POST","/plugins/publishEvent",function(m,path,data,hc3)
    if data.source == self.id or self.childDevices[data.source] then
      data = copy(data)
      if data.source == self.id then data.source = self._proxyId end
      local data2,res = fibaro.callHC3(self._proxyId,"_publishEvent",data)
      return true,data2,res
    end
    return false
  end)

  api._intercept("POST","/plugins/interfaces",function(m,path,data,hc3)
    if data.deviceId == self.id or self.childDevices[data.deviceId] then
      data = copy(data)
      if data.deviceId == self.id then data.deviceId = self._proxyId end
      --local data2,res = api.post("/plugins/interfaces",data,"hc3")
      local m = data.action == "add" and "_addInterfaces" or "_deleteInterfaces"
      local data2,res = fibaro.callHC3(data.deviceId,m,data.deviceId,data.interfaces)
      return true,data2,res
    end
    return false
  end)
  
  api._intercept("POST","/plugins/createChildDevice",function(m,path,data,hc3)
    if data.parentId == self.id then
      data = copy(data)
      data.parentId = self._proxyId
      if next(data.initialProperties) == nil then
        data.initialProperties = nil
      end
      local data2,res,h,i = api.post(path,data,"hc3")
      return true,data2,res
    end
    return false
  end)
  
  api._interceptpattern("DELETE","/plugins/removeChildDevice/(%d+)",function(m,path,data,hc3,id)
    local chs = api.get("/devices?parentId="..self.id)
    local isChild = false
    for _,ch in ipairs(chs) do
      if ch.id == tonumber(id) then
        isChild = true
        break
      end
    end
    if isChild then
      local data2,res = api.delete("/plugins/removeChildDevice/"..id,{},"hc3")
      return true,data2,res
    end
    return false
  end)

  api._intercept("GET","/devices?parentId="..self.id,function(m,path,data,hc3)
    local data2,res = api.get("/devices?parentId="..self._proxyId,"hc3")
    return true,data2,res
  end)
  
end

function QuickApp:_ProxyOnAction(action)
  if action.deviceId == self._proxyId then
    action.deviceId = self.id
  end
  onAction(action.deviceId,action)
end

function QuickApp:_ProxyUIHandler(ev)
  if ev.deviceId == self._proxyId then
    ev.deviceId = self.id
  end
  onUIEvent(ev.deviceId,ev)
end

QuickApp._hooks["proxy"] = function(self)
  local name = fibaro.fibemu.DIR[plugin.mainDeviceId].proxy
  if name then
    if name:sub(1,1) == '-' then
      name = name:sub(2)
      local p = api.get("/devices/?name="..urlencode(name),"hc3")
      if p and next(p) then
        print("/devices/"..p[1].id)
        api.delete("/devices/"..p[1].id,nil,"hc3")
        fibaro.trace(__TAG,"Proxy removed:",p[1].id,name)
      end
      return
    end
    self:launchProxy(name)
  end
end

