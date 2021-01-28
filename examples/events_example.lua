
local events = require 'lifter_puller.init'.events

-- An alternative to driving the parser yourself, you can also use this
-- iterator interface provided by the `events` function
for ev in events('<?xml version="1.1" encoding="UTF-8"?><p>hi</p>') do
    print(ev.ty)
end
-- Event Type    Text
-- -----------  ----------------------------------------
-- Declaration  (<?xml version="1.1" encoding="UTF-8"?>)
-- OpenTag      (<p)
-- TagEnd       (>)
-- Text         (hi)
-- CloseTag     (</p>)
