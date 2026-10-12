function descriptor()return {title='Vela Media Tools',version='1.1',author='Vela',capabilities={'input-listener','playing-listener','menu'}}end
local dialog,label,volume,enabled
function activate()
 dialog=vlc.dialog('Vela Media Tools')
 label=dialog:add_label('',1,1,3,1)
 volume=dialog:add_text_input(tostring(math.floor(vlc.volume.get()*100/256)),1,2)
 dialog:add_button('Set Volume',function()vlc.volume.set((tonumber(volume:get_text())or 100)*256/100)end,2,2)
 enabled=dialog:add_check_box('Keep this dialog open',true,1,3,3,1)
 dialog:add_button('Play / Pause',function()if vlc.playlist.status()=='playing'then vlc.playlist.pause()else vlc.playlist.play()end end,1,4)
 dialog:add_button('Previous',vlc.playlist.prev,2,4)
 dialog:add_button('Next',vlc.playlist.next,3,4)
 input_changed()
end
function input_changed()if label then local item=vlc.input.item();label:set_text(item and item:name()or'No media open')end end
function playing_changed()end
function menu()return{'Refresh','Pause'}end
function trigger_menu(id)if id==1 then input_changed()elseif id==2 then vlc.playlist.pause()end end
function close()vlc.deactivate()end
function deactivate()if dialog then dialog:delete()end end
