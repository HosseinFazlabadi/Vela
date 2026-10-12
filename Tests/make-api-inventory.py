from pathlib import Path
import re,json
root=Path(__file__).resolve().parents[1]
source=root/'Vendor/vlc-3.0.24/modules/lua/libs'
specs={'config':('configuration','vlclua_config_reg'),'input':('input','vlclua_input_reg'),'input_item':('input','vlclua_input_item_reg'),'object':('objects','vlclua_object_reg'),'strings':('strings','vlclua_strings_reg'),'var':('variables','vlclua_var_reg'),'net':('net','vlclua_net_intf_reg'),'net_listener':('net','vlclua_net_listen_reg'),'stream':('stream','vlclua_stream_reg'),'xml':('xml','vlclua_xml_reg'),'xml_reader':('xml','vlclua_xml_reader_reg'),'io':('io','vlclua_io_reg'),'io_file':('io','vlclua_io_file_reg'),'vlm':('vlm','vlclua_vlm_reg'),'volume':('volume','vlclua_volume_reg'),'video':('video','vlclua_video_reg'),'osd':('osd','vlclua_osd_reg'),'playlist':('playlist','vlclua_playlist_reg'),'sd':('sd','vlclua_sd_intf_reg'),'dialog':('dialog','vlclua_dialog_reg'),'widget':('dialog','vlclua_widget_reg')}
result={}
for name,(file,table) in specs.items():
 text=(source/(file+'.c')).read_text();text=re.sub(r'/\*.*?\*/|//[^\n]*','',text,flags=re.S)
 match=re.search(r'(?:static\s+)?const\s+luaL_Reg\s+'+table+r'\[\]\s*=\s*\{(.*?)\};',text,re.S)
 if not match:raise RuntimeError(f'No table {table} in {file}: '+str(re.findall(r'luaL_Reg\s+(\w+)',text)))
 names=re.findall(r'\{\s*"([^"]+)"\s*,',match.group(1))
 result[name]={'functions':names,'implementation':'Vela native UI' if name in ['dialog','widget'] else 'Vela frontend + libVLC' if name=='playlist' else 'VLC SDK discovery + Vela tree adapter' if name=='sd' else 'official VLC Lua bindings','upstream':f'Vendor/vlc-3.0.24/modules/lua/libs/{file}.c','upstream_table':table}
result['msg']={'functions':['dbg','info','warn','err'],'implementation':'Vela native log'}
manifest={'scope':'All macOS extension API families registered by GetLuaState in VLC 3.0.24; additional userdata methods listed separately. This inventory is function coverage, not certification of every extension or every parameter combination.','engine':'3.0.24','lua':'5.1.5 with official VLC bytecode, vararg and dynamic-module patches','surfaces':result,'upstream_function_count':sum(len(v['functions']) for v in result.values()),'root_functions':['dialog','gettext','deactivate','keep_alive','stream','memory_stream','xml','vlm'],'extra_family':{'misc':['mdate','mwait','quit']},'platform_exclusions':['Windows-only win APIs','HTTP interface / service-discovery-script libraries not registered in extension context']}
(root/'extension-api-inventory.json').write_text(json.dumps(manifest,indent=2))
lua='local surfaces='+json.dumps({k:v['functions'] for k,v in result.items() if k not in ['input_item','net_listener','stream','xml','xml_reader','io_file','vlm','dialog','widget']}).replace('[','{').replace(']','}').replace(':','=' )
# Lua object keys are emitted explicitly; no JSON-to-Lua text substitution.
lua='return {'+','.join('['+json.dumps(k)+']={'+','.join(json.dumps(n) for n in v['functions'])+'}' for k,v in result.items() if k not in ['input_item','net_listener','stream','xml','xml_reader','io_file','vlm','dialog','widget'])+'}'
(root/'Tests/api-function-names.lua').write_text(lua+'\n')
print(manifest['upstream_function_count'],'upstream functions inventoried')
