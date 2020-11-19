-- ----------------------------------------------------------------------------
-- Token Affiliation
--
-- https://github.com/emrahcom/
-- ----------------------------------------------------------------------------
-- This plugin set the occupant's affiliation according to the token content.
--
-- 1) Copy this script to the Prosody plugins folder. It's the following folder
--    on Debian
--
--    /usr/share/jitsi-meet/prosody-plugins/
--
-- 2) Enable module in your prosody config.
--    /etc/prosody/conf.d/meet.mydomain.com.cfg.lua
--
--    Component "conference.meet.mydomain.com" "muc"
--       modules_enabled = {
--         "token_verification";
--         "token_affiliation";
--
-- 3) Disable auto-ownership on Jicofo and let the module set the affiliations
--    according to the token content. Add the following line to
--    /etc/jitsi/jicofo/sip-communicator.properties
--
--    org.jitsi.jicofo.DISABLE_AUTO_OWNER=true
--
-- 4) Restart the services
--
--    systemctl restart prosody.service
--    systemctl restart jicofo.service
--
-- 5) Set the affiliation on token. The value may be "owner" or "member".
--
--    A sample token body:
--    {
--      "aud": "myapp",
--      "iss": "myapp",
--      "sub": "meet.mydomain.com",
--      "iat": 1601366000
--      "exp": 1601366180,
--      "room": "*",
--      "context": {
--        "user": {
--          "name": "myname",
--          "email": "myname@mydomain.com",
--          "affiliation": "owner"
--        }
--      }
--    }
-- ----------------------------------------------------------------------------
local LOGLEVEL = "debug"

local is_admin = require "core.usermanager".is_admin
local is_healthcheck_room = module:require "util".is_healthcheck_room
module:log(LOGLEVEL, "loaded")

local function _is_admin(jid)
    return is_admin(jid, module.host)
end

module:hook("muc-room-created", function(event)
        log(LOGLEVEL, 'room created, adding token moderation code');
        local room = event.room;
        -- Wrap set affilaition to block anything but token setting owner (stop pesky auto-ownering)
        local _set_affiliation = room.set_affiliation;
        room.set_affiliation = function(room, actor, jid, affiliation, reason)
                -- if they are admin, let them through
                if _is_admin(jid) then
                        return _set_affiliation(room, true, jid, affiliation, reason)
                -- let this plugin do whatever it wants
                elseif actor == "token_plugin" then
                        return _set_affiliation(room, true, jid, affiliation, reason)
                -- noone else can assign owner (in order to block prosody/jisti's built in moderation functionality
                elseif affiliation == "owner" then
                        return nil, "modify", "not-acceptable"
                -- keep other affil stuff working as normal (hopefully, haven't needed to use/test any of it)
                else
                        return _set_affiliation(room, actor, jid, affiliation, reason);
                end;
        end;
end);

module:hook("muc-occupant-joined", function (event)
    local room, occupant = event.room, event.occupant

    if is_healthcheck_room(room.jid) or _is_admin(occupant.jid) then
        module:log(LOGLEVEL, "skip affiliation, %s", occupant.jid)
        return
    end

    if not event.origin.auth_token then
        module:log(LOGLEVEL, "skip affiliation, no token")
        return
    end

    local affiliation = "member"
    local context_user = event.origin.jitsi_meet_context_user

    if context_user then
        if context_user["affiliation"] == "owner" then
            affiliation = "owner"
        elseif context_user["affiliation"] == "moderator" then
            affiliation = "owner"
        end
    end

    module:log(LOGLEVEL, "affiliation: %s", affiliation)
    room:set_affiliation("token_plugin", occupant.bare_jid, affiliation)
end)
