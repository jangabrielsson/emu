local format = string.format
local function arrayify(t)
  if type(t)=='table' then json.util.InitArray(t) end 
  return t
end

local function map(f,l) for _,v in ipairs(l) do f(v) end end
local function traverse(o,f)
  if type(o) == 'table' and o[1] then
    for _,e in ipairs(o) do traverse(e,f) end
  else f(o) end
end

local ELMS = {
  button = function(d,w)
    return {name=d.name,visible=true,style={weight=d.weight or w or "0.50"},text=d.text,type="button"}
  end,
  select = function(d,w)
    arrayify(d.options)
    if d.options then map(function(e) e.type='option' end,d.options) end
    return {name=d.name,style={weight=d.weight or w or "0.50"},text=d.text,type="select", visible=true, selectionType='single',
      options = d.options or arrayify({}),
      values = arrayify(d.values) or arrayify({})
    }
  end,
  multi = function(d,w)
    arrayify(d.options)
    if d.options then map(function(e) e.type='option' end,d.options) end
    return {name=d.name,style={weight=d.weight or w or "0.50"},text=d.text,type="select",visible=true, selectionType='multi',
      options = d.options or arrayify({}),
      values = arrayify(d.values) or arrayify({})
    }
  end,
  image = function(d,_)
    return {name=d.name,style={dynamic="1"},type="image", url=d.url}
  end,
  switch = function(d,w)
    d.value = d.value == nil and "false" or tostring(d.value)
    return {name=d.name,visible=true,style={weight=w or d.weight or "0.50"},text=d.text,type="switch", value=d.value}
  end,
  option = function(d,_)
    return {name=d.name, type="option", value=d.value or "Hupp"}
  end,
  slider = function(d,w)
    return {name=d.name,visible=true,step=tostring(d.step or 1),value=tostring(d.value or 0),max=tostring(d.max or 100),min=tostring(d.min or 0),style={weight=d.weight or w or "1.2"},text=d.text,type="slider"}
  end,
  label = function(d,w)
    return {name=d.name,visible=true,style={weight=d.weight or w or "1.2"},text=d.text,type="label"}
  end,
  space = function(_,w)
    return {style={weight=w or "0.50"},type="space"}
  end
}

local function mkRow(elms,weight)
  local comp = {}
  if elms[1] then
    local c = {}
    local width = format("%.2f",1/#elms)
    if width:match("%.00") then width=width:match("^(%d+)") end
    for _,e in ipairs(elms) do c[#c+1]=ELMS[e.type](e,width) end
    if #elms > 1 then comp[#comp+1]={components=c,style={weight="1.2"},type='horizontal'}
    else comp[#comp+1]=c[1] end
    comp[#comp+1]=ELMS['space']({},"0.5")
  else
    comp[#comp+1]=ELMS[elms.type](elms,"1.2")
    comp[#comp+1]=ELMS['space']({},"0.5")
  end
  return {components=comp,style={weight=weight or "1.2"},type="vertical"}
end

local function UI2NewUiView(UI,child)
  local uiView = {}
  for _,row in ipairs(UI) do
    local urow = {
      style = { weight = "1.0"},
      type = "horizontal",
    }
    row = #row==0 and {row} or row
    local weight = ({'1.0','0.5','0.25','0.33','0.20'})[#row]
    local uels = {}
    for _,el in ipairs(row) do
      local name = el.button or el.slider or el.label or el.select or el.switch or el.multi
      local typ = el.button and 'button' or el.slider and 'slider' or 
        el.label and 'label' or el.select and 'select' or el.switch and 'switch' or el.multi and 'multi'
      if typ == "select" then
        --print(json.encode(el))
      end
      local function mkBinding(name,action,fun,actionName)
        local r = {
          params = {
            actionName = (not child) and actionName or "UIAction",
            args = (not child) and actionName and {} or {action,name,fun}
          },
          type = "deviceAction"
        }
        return (r.params.actionName ~= 'UIAction' or child) and {r} or nil
      end 
      local uel = {
        eventBinding = {
          onReleased = (typ=='button' or typ=='switch') and mkBinding(name,"onReleased",typ=='switch' and "$event.value" or nil,el.onReleased) or nil,
          onLongPressDown = (typ=='button' or typ=='switch') and mkBinding(name,"onLongPressDown",typ=='switch' and "$event.value" or nil,el.onLongPressDown) or nil,
          onLongPressReleased = (typ=='button' or typ=='switch') and mkBinding(name,"onLongPressReleased",typ=='switch' and "$event.value" or nil,el.onLongPressReleased) or nil,
          onToggled = (typ=='select' or typ=='multi') and mkBinding(name,"onToggled","$event.value",el.onToggled) or nil,
          onChanged = typ=='slider' and mkBinding(name,"onChanged","$event.value",el.onChanged) or nil,
        },
        max = el.max,
        min = el.min,
        step = el.step,
        name = el[typ],
        options = arrayify(el.options),
        values = arrayify(el.values) or ((typ=='select' or typ=='multi') and arrayify({})) or nil,
        value = el.value,
        style = { weight = weight},
        type = typ=='multi' and 'select' or typ,
        selectionType = (typ == 'multi' and 'multi') or (typ == 'select' and 'single') or nil,
        text = el.text,
        visible = true,
      }
      arrayify(uel.options)
      arrayify(uel.values)
      if not next(uel.eventBinding) then 
        uel.eventBinding = nil 
      end
      uels[#uels+1] = uel
    end
    urow.components = uels
    uiView[#uiView+1] = urow
  end
  return uiView
end

local function mkViewLayout(list,height,id)
  local items = {}
  for _,i in ipairs(list) do items[#items+1]=mkRow(i) end
--    if #items == 0 then  return nil end
  return
  { ['$jason'] = {
      body = {
        header = {
          style = {height = tostring(height or #list*50)},
          title = "quickApp_device_"..id
        },
        sections = {
          items = items
        }
      },
      head = {
        title = "quickApp_device_"..id
      }
    }
  },
  UI2NewUiView(list)
end

local function transformUI(UI) -- { button=<text> } => {type="button", name=<text>}
  traverse(UI,
    function(e)
      if e.button then 
        e.name,e.type,e.onReleased=e.button,'button',e.onReleased or e.f; e.f=nil
      elseif e.slider then 
        e.name,e.type,e.onChanged=e.slider,'slider',e.onChanged or e.f; e.f=nil
      elseif e.select then 
        e.name,e.type=e.select,'select'
      elseif e.switch then 
        e.name,e.type=e.switch,'switch'
      elseif e.multi then 
        e.name,e.type=e.multi,'multi'
      elseif e.option then 
        e.name,e.type=e.option,'option'
      elseif e.image then 
        e.name,e.type=e.image,'image'
      elseif e.label then 
        e.name,e.type=e.label,'label'
      elseif e.space then 
        e.weight,e.type=e.space,'space' end
    end)
  return UI
end

--[[
[
  {
    "components": [
      {
        "eventBinding": {
          "onLongPressDown": [
            {
              "params": {
                "actionName": "UIAction",
                "args": [
                  "onLongPressDown",
                  "B1"
                ]
              },
              "type": "deviceAction"
            }
          ],
          "onLongPressReleased": [
            {
              "params": {
                "actionName": "UIAction",
                "args": [
                  "onLongPressReleased",
                  "B1"
                ]
              },
              "type": "deviceAction"
            }
          ],
          "onReleased": [
            {
              "params": {
                "actionName": "UIAction",
                "args": [
                  "onReleased",
                  "B1"
                ]
              },
              "type": "deviceAction"
            }
          ]
        },
        "name": "B1",
        "style": {
          "weight": "1.0"
        },
        "text": "Button1",
        "type": "button",
        "visible": true
      }
    ],
    "style": {
      "weight": "1.0"
    },
    "type": "horizontal"
  },
  {
    "components": [
      {
        "eventBinding": {
          "onLongPressDown": [
            {
              "params": {
                "actionName": "UIAction",
                "args": [
                  "onLongPressDown",
                  "B2"
                ]
              },
              "type": "deviceAction"
            }
          ],
          "onLongPressReleased": [
            {
              "params": {
                "actionName": "UIAction",
                "args": [
                  "onLongPressReleased",
                  "B2"
                ]
              },
              "type": "deviceAction"
            }
          ],
          "onReleased": [
            {
              "params": {
                "actionName": "UIAction",
                "args": [
                  "onReleased",
                  "B2"
                ]
              },
              "type": "deviceAction"
            }
          ]
        },
        "name": "B2",
        "style": {
          "weight": "1.0"
        },
        "text": "Button2",
        "type": "button",
        "visible": true
      }
    ],
    "style": {
      "weight": "1.0"
    },
    "type": "horizontal"
  },
  {
    "components": [
      {
        "eventBinding": {
          "onChanged": [
            {
              "params": {
                "actionName": "UIAction",
                "args": [
                  "onChanged",
                  "Slider1",
                  "$event.value"
                ]
              },
              "type": "deviceAction"
            }
          ]
        },
        "max": "100",
        "min": "0",
        "name": "Slider1",
        "style": {
          "weight": "1.0"
        },
        "text": "",
        "type": "slider",
        "visible": true
      }
    ],
    "style": {
      "weight": "1.0"
    },
    "type": "horizontal"
  },
  {
    "components": [
      {
        "eventBinding": {
          "onToggled": [
            {
              "params": {
                "actionName": "UIAction",
                "args": [
                  "onToggled",
                  "S1",
                  "$event.value"
                ]
              },
              "type": "deviceAction"
            }
          ]
        },
        "name": "S1",
        "options": [
          
        ],
        "selectionType": "single",
        "style": {
          "weight": "1.0"
        },
        "text": "Select1",
        "type": "select",
        "values": [
          
        ],
        "visible": true
      }
    ],
    "style": {
      "weight": "1.0"
    },
    "type": "horizontal"
  },
  {
    "components": [
      {
        "eventBinding": {
          "onToggled": [
            {
              "params": {
                "actionName": "UIAction",
                "args": [
                  "onToggled",
                  "S2",
                  "$event.value"
                ]
              },
              "type": "deviceAction"
            }
          ]
        },
        "name": "S2",
        "options": [
          
        ],
        "selectionType": "multi",
        "style": {
          "weight": "1.0"
        },
        "text": "Select2",
        "type": "select",
        "values": [
          
        ],
        "visible": true
      }
    ],
    "style": {
      "weight": "1.0"
    },
    "type": "horizontal"
  }
]
--]]

local function uiStruct2uiCallbacks(UI)
  local cbs = {}
  traverse(UI,
    function(e)
      if e.type == 'button' or e.type=='switch' then
        cbs[#cbs+1]={callback=e.onReleased or "",eventType='onReleased',name=e.name}
        cbs[#cbs+1]={callback=e.onLongPressDown or "",eventType='onLongPressDown',name=e.name}
        cbs[#cbs+1]={callback=e.onLongPressReleased or "",eventType='onLongPressReleased',name=e.name}
      elseif e.type == 'slider' then
        cbs[#cbs+1]={callback=e.onChanged or "",eventType='onChanged',name=e.name}
      elseif e.type == 'select' then
        cbs[#cbs+1]={callback=e.onToggled or "",eventType='onToggled',name=e.name}
      elseif e.type == 'multi' then
        cbs[#cbs+1]={callback=e.onToggled or "",eventType='onToggled',name=e.name}
      end
    end)
  return cbs
end


local function collectViewLayoutRow(u,map)
    local row = {}
    local function empty(a) return a~="" and a or "" end
    local function conv(u)
      if type(u) == 'table' then
        if u.name then
          if u.type=='label' then
            row[#row+1]={label=u.name, text=u.text}
          elseif u.type=='button' then
            local e ={[u.type]=u.name, text=u.text, value=u.value, visible=u.visible==nil and true or u.visible}
            e.onReleased = empty((map[u.name] or {}).onReleased)
            e.onLongPressDown = empty((map[u.name] or {}).onLongPressDown)
            e.onLongPressReleased = empty((map[u.name] or {}).onLongPressReleased)
            row[#row+1]=e
          elseif u.type=='switch' then
            local e ={[u.type]=u.name, text=u.text, value=u.value, visible=u.visible==nil and true or u.visible}
            e.onReleased = empty((map[u.name] or {}).onReleased)
            e.onLongPressDown = empty((map[u.name] or {}).onLongPressDown)
            e.onLongPressReleased = empty((map[u.name] or {}).onLongPressReleased)
            row[#row+1]=e
          elseif u.type=='slider' then
            row[#row+1]={
              slider=u.name, 
              text=u.text, 
              onChanged=(map[u.name] or {}).onChanged,
              max = u.max,
              min = u.min,
              step = u.step,
              visible = u.visible==nil and true or u.visible,
            }
          elseif u.type=='select' then
            row[#row+1]={
              [u.selectionType=='multi' and 'multi' or 'select']=u.name, 
              text=u.text, 
              options=arrayify(u.options),
              visible = u.visible==nil and true or u.visible,
              onToggled=(map[u.name] or {}).onToggled,
            }
          else
            print("Unknown type",json.encode(u))
          end
        else
          for _,v in pairs(u) do conv(v) end
        end
      end
    end
    conv(u)
    return row
  end
  
  local function viewLayout2UI(u,map)
    local function conv(u)
      local rows = {}
      for _,j in pairs(u.items) do
        local row = collectViewLayoutRow(j.components,map)
        if #row > 0 then
          if #row == 1 then row=row[1] end
          rows[#rows+1]=row
        end
      end
      return rows
    end
    return conv(u['$jason'].body.sections)
  end

  local function view2UI(view,callbacks)
    local map = {}
    traverse(callbacks,function(e) 
      if e.eventType then
        map[e.name]=map[e.name] or {}
        map[e.name][e.eventType]=e.callback
      end
    end)
    local UI = viewLayout2UI(view,map)
    return UI
  end

local function setVariable(self,name,value)
  local vars = __fibaro_get_device(self.id).properties.quickAppVariables or {}
  for _,v in ipairs(vars) do
    if v.name == name then 
      v.value,v.type = value, 'password' 
      self:updateProperty('quickAppVariables',vars)
      return
    end
  end
  vars[#vars+1] = {name = name, value = value, type = 'password'}
  self:updateProperty('quickAppVariables',vars)
end

local function equal(e1,e2)
  if e1==e2 then return true
  else
    if type(e1) ~= 'table' or type(e2) ~= 'table' then return false
    else
      for k1,v1 in pairs(e1) do if e2[k1] == nil or not equal(v1,e2[k1]) then return false end end
      for k2,_  in pairs(e2) do if e1[k2] == nil then return false end end
      return true
    end
  end
end

local function updateUI(self,UI)
  local oldUI = self:getVariable('userUI')
  if not equal(oldUI,UI)  then
    setVariable(self,'userUI',UI)
    self:debug("Updating UI...")
    transformUI(UI)
    local viewLayout = mkViewLayout(UI)
    local uiCallbacks = uiStruct2uiCallbacks(UI)
    return api.put("/devices/"..plugin.mainDeviceId,{
        properties={
          viewLayout= viewLayout,
          uiCallbacks =  uiCallbacks,
        }
      })
  else return "Already updated",200 end
end

local function stockRow(x)
  if type(x)=='table' then 
      for k,v in pairs(x) do
          if type(v)=='string' and v:sub(1,1)=="_" then return true end
          if stockRow(v) then return true end
      end
  end
end

local function copy(t)
  if type(t)~='table' then return t end
  local res = {}
  for k,v in pairs(t) do res[k] = copy(v) end
  return res
end

local function pruneViewLayout(vl)
  local x = vl['$jason'].body.sections.items
  local items,flag = {},false
  for i = 1,#x do
      --print(json.encode(x[i]))
      if not stockRow(x[i]) then items[#items+1] = x[i] else flag=true end
  end
  if flag then
      vl = copy(vl)
      vl['$jason'].body.sections.items = items
  end
  return vl
end

local function pruneuiView(vl)
  local x = vl or {}
  local items = {}
  for i = 1,#x do
      --print(json.encode(x[i]))
      if not stockRow(x[i]) then items[#items+1] = x[i] end
  end
  return items
end

local function pruneStock(prop)
  local viewLayout = pruneViewLayout(prop.viewLayout)
  local uiView = pruneuiView(prop.uiView)
  local uiCallbacks = prop.uiCallbacks
  if uiCallbacks then
      local x = {}
      for i=1,#uiCallbacks do
          local e = uiCallbacks[i]
          if e.name:sub(1,1)~='_' then x[#x+1] = e end
      end
      uiCallbacks = x
  end
  return viewLayout,uiView,uiCallbacks
end

local function uiView2UI(ui)
  local UI = {}
  for _,r in ipairs(ui) do
    local row = {}
    for _,c in ipairs(r.components) do
      if c.type == 'label' then
        row[#row+1] = { label = c.name, text = c.text, visible = c.visible }
      elseif c.type == 'button' or c.type == 'switch' then
        local r1 = { [c.type] = c.name, text = c.text, visible = c.visible, }
        for f,e in pairs(c.eventBinding or {}) do
          if e[1].type == 'deviceAction' then
            r1[f] = e[1].params.actionName
          end
        end
        row[#row+1] = r1
      elseif c.type == 'slider' then
        local e = c.eventBinding.onChanged[1]
        row[#row+1] = { slider = c.name, text = c.text, value = c.value, visible = c.visible, onChanged = e.params.actionName }
      elseif c.type == 'select' then
        local e = c.eventBinding.onToggled[1]
        local typ = c.selectionType == 'single' and 'select' or 'multi'
        -- arrayify options...
        row[#row+1] = { [typ] = c.name, text = c.text, values = arrayify(c.values or {}), options = arrayify(c.options), visible = c.visible, onToggled = e.params.actionName }
      end
    end
    UI[#UI+1] = row
  end
  return UI
end

fibaro.ui = {
  uiStruct2uiCallbacks = uiStruct2uiCallbacks,
  transformUI = transformUI,
  mkViewLayout = mkViewLayout,
  view2UI = view2UI,
  UI2NewUiView = UI2NewUiView,
  uiView2UI = uiView2UI,
  updateUI =  updateUI,
  pruneStock = pruneStock,
}