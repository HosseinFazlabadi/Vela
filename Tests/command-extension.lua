function descriptor()return {title="Cancellable command"}end
function activate()local d=vlc.dialog("Command cancellation");d:add_label("Waiting");d:update();os.execute("sleep 30")end
