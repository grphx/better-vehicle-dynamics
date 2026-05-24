-- BVD_SkidSync_Server.lua (server; v0.1.3)
--
-- Relays per-vehicle skid heartbeat commands to all online clients so each
-- client can locally play/stop its own copy of the skid sound. Solves the
-- v<=0.1.2 bug where the driver's vehicle:getEmitter():stopSound() did not
-- replicate, leaving the sound looping on remote clients until they left
-- audio range.
--
-- Wire format:
--   "BVD-Skid" "Start" { vid }
--   "BVD-Skid" "Tick"  { vid, intensity }
--   "BVD-Skid" "Stop"  { vid }
--
-- The server just broadcasts. Volume / intensity calculation lives on the
-- driver client; the playback lives on every receiving client.

if isClient() and not isServer() then return end

local function onClientCommand(module, command, player, args)
    if module ~= "BVD-Skid" then return end
    if command ~= "Start" and command ~= "Tick" and command ~= "Stop" then return end
    if not args or not args.vid then return end
    -- Broadcast to every online client. sendServerCommand with nil player
    -- targets the global broadcast on B42 dedicated servers; in SP it
    -- fires OnServerCommand on the local client which is the desired
    -- single-path behaviour.
    pcall(sendServerCommand, "BVD-Skid", command, args)
end

if Events and Events.OnClientCommand then
    Events.OnClientCommand.Add(onClientCommand)
end
