std = "lua51"
max_line_length = false
self = false
ignore = { "212", "213", "211/_" } -- unused args / loop vars
globals = {
    "ForeverXP", "ForeverXPDB", "ForeverXPCharDB",
    "SLASH_FOREVERXP1", "SLASH_FOREVERXP2",
}
read_globals = {
    -- WoW API used through Compat.lua
    "CreateFrame", "UIParent", "GameTooltip", "DEFAULT_CHAT_FRAME", "SlashCmdList", "BackdropTemplateMixin",
    "C_Timer", "C_Map", "C_QuestLog", "C_SuperTrack", "C_Item", "C_AddOns", "C_GameRules",
    "GetBuildInfo", "GetMaxPlayerLevel", "MAX_PLAYER_LEVEL", "UnitLevel", "UnitXP", "UnitXPMax", "GetXPExhaustion",
    "IsResting", "InCombatLockdown", "UnitFactionGroup", "UnitClass", "UnitRace", "GetNumGroupMembers", "IsInInstance",
    "GetPlayerFacing", "GetZoneText", "GetRealZoneText", "GetSubZoneText", "GetTime", "GetInventoryItemLink",
    "GetQuestLogRewardXP", "GetNumQuestLogEntries", "GetQuestLogTitle", "MAX_QUESTS", "SetSuperTrackedQuestID",
    "GetSuperTrackedQuestID", "GetItemInfo", "GetDetailedItemLevelInfo", "GetAddOnMetadata", "UiMapPoint",
    "WOW_PROJECT_ID", "WOW_PROJECT_CAMELOT", "Settings", "InterfaceOptions_AddCategory", "InterfaceOptionsFrame_OpenToCategory",
    "unpack", "time",
}
files["tests/"] = { std = "lua54+lua51", globals = { "*" } }
