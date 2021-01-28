
local events = require 'lifter_puller.init'.events

for ev in events('<?xml version="1.1" encoding="UTF-8"?><p>hi</p>') do
    print(ev.ty)
end