local extensionDir=(_vela_extension_path or ''):match('^(.*)/') or '.'
package.path=extensionDir..'/modules/?.luac;'..extensionDir..'/modules/?.lua;'..extensionDir..'/?.lua;'.._vela_runtime..'/?.lua;'.._vela_runtime..'/modules/?.lua;'..package.path
-- Lua 5.1 and fixed-width bytecode match the official VLC runtime.
local json=require('dkjson')
_vela_encode=function(x)if x==_vela_model then x.revision=(x.revision or 0)+1 end;return json.encode(x or {})end
local function native(action,value)return _vela_native(action,value or '')end
local function decode(s)local value,_,err=json.decode(s or '{}');if err then error(err)end;return value end
_vela_model={title='Extension',visible=false,widgets={},logs={},revision=0,editAck={}}
_vela_descriptor={}
local serial=0;local callbacks={};local widgetMethods={};local dialogs={}
local function widget(kind,text,col,row,span,rowspan,width,height)
 serial=serial+1
 if kind=='image' and type(text)=='string' and text:sub(1,1)~='/' and not text:match('^%w+://')then text=extensionDir..'/'..text end
 local w={id=serial,kind=kind,text=tostring(text or ''),col=(tonumber(col) or 0)>0 and tonumber(col) or 1,row=(tonumber(row) or 0)>0 and tonumber(row) or serial,span=tonumber(span) or 1,rowspan=tonumber(rowspan) or 1,width=tonumber(width) or 0,height=tonumber(height) or 0,checked=false,value=0,values={},selection={},enabled=true}
 setmetatable(w,{__index=widgetMethods});table.insert(_vela_model.widgets,w);return w
end
local textKinds={label=true,button=true,html=true,text_input=true,password=true,dropdown=true,checkbox=true}
local function valid(w,kinds,method)if w.deleted then error('Widget has been deleted')end;if kinds and not kinds[w.kind]then error('method '..method..' not valid for this widget')end end
function widgetMethods:set_text(t)valid(self,textKinds,'set_text');assert(type(t)=='string' or type(t)=='number','set_text requires text');self.text=tostring(t);return t end
function widgetMethods:get_text()valid(self,textKinds,'get_text');return self.text end
function widgetMethods:set_checked(v)valid(self,{checkbox=true},'set_checked');assert(type(v)=='boolean','set_checked requires a boolean');self.checked=v;return v end
function widgetMethods:get_checked()valid(self,{checkbox=true},'get_checked');return self.checked end
function widgetMethods:add_value(text,id)valid(self,{dropdown=true,list=true},'add_value');local value=tonumber(id) or 0;table.insert(self.values,{text=tostring(text),id=value});if not self.hasValue and self.kind=='dropdown'then self.value=value;self.hasValue=true end;return id or text end
function widgetMethods:get_value()valid(self,{dropdown=true},'get_value');if self.hasValue then for _,v in ipairs(self.values)do if v.id==self.value then return v.id,v.text end end end;return -1,nil end
function widgetMethods:clear()valid(self,{dropdown=true,list=true},'clear');self.values={};self.selection={};self.value=-1;self.hasValue=false;return self end
function widgetMethods:get_selection()valid(self,{list=true},'get_selection');local t={};for _,v in ipairs(self.values)do if self.selection[tostring(v.id)]then t[v.id]=v.text end end;return t end
function widgetMethods:set_value(v)self.value=v;self.hasValue=true end
function widgetMethods:enable()self.enabled=true end
function widgetMethods:disable()self.enabled=false end
function widgetMethods:animate(loops)valid(self,{spinner=true},'animate');self.spinLoops=tonumber(loops) or -1;self.animating=self.spinLoops~=0;self.animationToken=_mdate();return loops or self end
function widgetMethods:stop()valid(self,{spinner=true},'stop');self.animating=false;self.spinLoops=0;self.animationToken=_mdate();return self end
function widgetMethods:delete()self.deleted=true end
local dialogMethods={}
function dialogMethods:show()assert(not self.deleted);_vela_model.visible=true;return self end
function dialogMethods:hide()assert(not self.deleted);_vela_model.visible=false;return self end
function dialogMethods:delete()self.deleted=true;_vela_model.visible=false;_vela_model.widgets={};callbacks={};return self end
function dialogMethods:set_title(t)assert(not self.deleted);_vela_model.title=tostring(t);return t end
function dialogMethods:update()native("dialog:update",_vela_encode(_vela_model));return self end
function dialogMethods:del_widget(w)w:delete();callbacks[w.id]=nil;self:update();return w end
function dialogMethods:add_button(text,fn,col,row,span,rowspan,width,height)local w=widget('button',text,col,row,span,rowspan,width,height);callbacks[w.id]=fn;return w end
function dialogMethods:add_check_box(text,state,col,row,span,rowspan,width,height)local w=widget('checkbox',text,col,row,span,rowspan,width,height);w.checked=not not state;return w end
function dialogMethods:add_dropdown(col,row,span,rowspan,width,height)return widget('dropdown','',col,row,span,rowspan,width,height)end
function dialogMethods:add_list(col,row,span,rowspan,width,height)return widget('list','',col,row,span,rowspan,width,height)end
for _,kind in ipairs({'label','html','text_input','password','image'})do local k=kind;dialogMethods['add_'..k]=function(_,text,col,row,span,rowspan,width,height)return widget(k,text,col,row,span,rowspan,width,height)end end
function dialogMethods:add_spin_icon(col,row,span,rowspan,width,height)return widget('spinner','',col,row,span,rowspan,width,height)end
function _vela_click(id)if callbacks[id]then callbacks[id]()end end
function _vela_set(id,text,value,sequence)if sequence and sequence>0 then _vela_model.editAck[tostring(id)]=sequence end;for _,w in ipairs(_vela_model.widgets)do if w.id==id then if w.kind=='checkbox'then w.checked=value~=0 elseif w.kind=='dropdown'then w.value=value;w.hasValue=true elseif w.kind=='list'then w.selection[tostring(value)]=text=='true'else w.text=text end;break end end end
vlc=_vela_vlc
function vlc.gettext(s)return native('gettext',tostring(s)) or s end
vlc.msg={};for _,level in ipairs({'info','warn','err','dbg'})do local l=level;vlc.msg[l]=function(...)local t={...};for i,v in ipairs(t)do t[i]=tostring(v)end;table.insert(_vela_model.logs,l..': '..table.concat(t,' '));if #_vela_model.logs>100 then table.remove(_vela_model.logs,1)end end end
function vlc.dialog(title)for _,d in ipairs(dialogs)do if not d.deleted then error('An extension may only have one active dialog')end end;_vela_model.title=tostring(title);_vela_model.visible=true;local d=setmetatable({},{__index=dialogMethods});table.insert(dialogs,d);return d end
vlc.playlist={}
vlc.playlist.current=function()return tonumber(native('current')) or -1 end
vlc.playlist.status=function()return native('status')end
vlc.misc={mdate=_mdate,mwait=_mwait,quit=function()native('quit')end}
function vlc.deactivate()_vela_model.visible=false;_vela_model.deactivationRequested=true end
vlc.config.datadir=function()return native('datadir')end
vlc.config.userdatadir=function()return native('userdatadir')end
vlc.config.homedir=function()return native('homedir')end
vlc.config.cachedir=function()return native('cachedir')end

function _vela_getmenu()local result={};if type(menu)=='function'then for id,text in pairs(menu()or{})do result[tostring(id)]=tostring(text)end end;return result end

local core=_vela_vlc
for _,name in ipairs({'object','var','input','strings','net','xml','io','errno','stream','memory_stream','vlm','volume','osd','video'})do vlc[name]=core[name]end
vlc.config.get=core.config.get;vlc.config.set=core.config.set
vlc.config.configdir=function()return native('userdatadir')end
vlc.config.datadir_list=function(name)return {native('userdatadir')..'/lua/'..name,_vela_runtime..'/'..name,native('datadir')..'/lua/'..name}end
vlc.keep_alive=_vela_keepalive

local dataRoot=os.getenv('VLC_DATA_PATH');if dataRoot then package.path=package.path..';'..dataRoot..'/lua/modules/?.luac;'..dataRoot..'/lua/modules/?.lua' end

-- Frontend-owned playlist: IDs survive reorder and are shared by all extensions.
local function ret(action,args)local n=tonumber(native('playlist:'..action,json.encode(args or {})))or -1;return n,n==0 and 'no error' or 'generic error'end
for _,op in ipairs({'prev','next','skip','play','pause','stop','clear','sort','delete','move','gotoitem'})do local o=op;vlc.playlist[o]=function(...)return ret(o,{...})end end
vlc.playlist['goto']=vlc.playlist.gotoitem
for _,op in ipairs({'repeat','loop','random'})do local o=op;vlc.playlist[o]=function(v)return native('playlist:'..o,v==nil and 'toggle' or tostring(v))=='true'end end
vlc.playlist.repeat_=vlc.playlist['repeat']
for _,op in ipairs({'add','enqueue'})do local o=op;vlc.playlist[o]=function(items)return tonumber(native('playlist:'..o,json.encode(items)))or 0 end end
local function enrich(node)
 if type(node)~='table' or next(node)==nil then return nil end
 if node.path and not node.item then node.item=_vela_item(node.id)end
 for _,child in ipairs(node.children or {})do enrich(child)end
 return node
end
local function findnode(node,id)if node.id==id then return node end;for _,child in ipairs(node.children or {})do local found=findnode(child,id);if found then return found end end end
vlc.playlist.get=function(which)
 if type(which)=='string'then local service=_vela_sd_get(which);if service then return service end end
 if type(which)=='number' and which>=1000000 then for _,root in ipairs(_vela_sd_roots())do local found=findnode(root,which);if found then return found end end end
 if which==nil or which==0 or (type(which)=='string' and which:lower()=='root')then
  local children={vlc.playlist.get('normal'),vlc.playlist.get('ml')};for _,service in ipairs(_vela_sd_roots())do table.insert(children,service)end
  return {id=0,name='Root',flags={},children=children}
 end
 return enrich(decode(native('playlist:get',json.encode({which}))))
end
vlc.playlist.search=function(text)return enrich(decode(native('playlist:search',text or '')))end
local varget,varset,vartoggle,varinherit=vlc.var.get,vlc.var.set,vlc.var.toggle_bool,vlc.var.inherit
local function playlistvar(obj,name)return _vela_is_playlist(obj) and (name=='repeat' or name=='loop' or name=='random')end
vlc.var.get=function(obj,name)if playlistvar(obj,name)then return native('playlistvar:get',name)=='true'end;if name=='fullscreen' and _vela_object_kind(obj)=='vout'then local state=native('video:is_fullscreen');if state~=nil then return state=='true'end end;return varget(obj,name)end
vlc.var.inherit=function(obj,name)if playlistvar(obj,name)then return vlc.var.get(obj,name)end;return varinherit(obj,name)end
vlc.var.set=function(obj,name,value)if playlistvar(obj,name)then native('playlist:'..name,tostring(value));return 0,'no error'end;local result={varset(obj,name,value)};if result[1]==0 and (name=='rate' or name=='aspect-ratio' or name=='crop' or name=='mute' or name=='fullscreen')then local ok,actual=pcall(varget,obj,name);native('var:sync',json.encode({kind=_vela_object_kind(obj),name=name,value=ok and actual or value}))end;return unpack(result)end
vlc.var.toggle_bool=function(obj,name)if playlistvar(obj,name)then return native('playlist:'..name,'toggle')=='true'end;return vartoggle(obj,name)end
local configset=vlc.config.set
vlc.config.set=function(name,value)local result=configset(name,value);native('config:sync',json.encode({name=name,value=value}));return result end

local fullscreen=vlc.video.fullscreen
vlc.video.fullscreen=function(mode)
 local state=native('video:is_fullscreen')
 if mode==nil and state~=nil then mode=state=='true' and 'off' or 'on' end
 if mode==true then mode='on' elseif mode==false then mode='off' end
 local result;if mode==nil then result=fullscreen()else result=fullscreen(mode)end
 native('video:fullscreen',tostring(result));return result
end
