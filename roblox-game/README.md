# Dead Hours - Roblox Studio version

1. In Roblox Studio open a new **Baseplate** place. Delete the Baseplate (the script builds its own lobby + arenas).
2. **ServerScriptService** > Insert **Script**, name it `ServerMain`, paste `ServerMain.server.lua`.
3. **StarterPlayer > StarterPlayerScripts** > Insert **LocalScript**, name it `ClientMain`, paste `ClientMain.client.lua`.
4. Press Play (or Test > Start with 2+ players).
5. Optional sounds: fill the `SOUND` table at the top of ServerMain with `rbxassetid://...` ids from the Creator Store.

Flow: lobby (floating platform) -> walk to a door, press E -> waiting room; countdown 20s (restarts when someone joins;
5 players starts in 5s; min 1) -> that door's own arena (up to 5 players, own day/night clock) -> game runs until every
player in the arena is dead -> everybody returns to the lobby and can start again.
