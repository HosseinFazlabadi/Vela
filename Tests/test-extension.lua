function descriptor()return{title='Extension Test',version='1.0',capabilities={'input-listener','menu'}}end
function activate()
 d=vlc.dialog('Native Test Dialog');label=d:add_label('Ready',1,1)
 input=d:add_text_input('initial',1,2);check=d:add_check_box('Enabled',true,2,2)
 drop=d:add_dropdown(1,3);drop:add_value('One',1);drop:add_value('Two',2)
 d:add_button('Run',function()label:set_text(input:get_text()..':'..tostring(check:get_checked())..':'..drop:get_value());vlc.volume.set(37*256/100)end,1,4)
end
function input_changed()if label then label:set_text('Input changed')end end
function playing_changed()end
function deactivate()end

function menu()return {[1]="Refresh",[2]="Close"}end
function trigger_menu(id)if id==1 then label:set_text("Menu invoked")elseif id==2 then vlc.deactivate()end end
