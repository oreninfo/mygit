; ============================================================================
; Config.au3 - Управление конфигурацией приложения
; ============================================================================
#include-once

; ============================================================================
; ФУНКЦИИ КОНФИГУРАЦИИ
; ============================================================================

Func _Config_CreateDefault()
    Local $sConfigPath = @ScriptDir & "\config.ini"
    
    IniWrite($sConfigPath, "Security", "PasswordHash", "5f4dcc3b5aa765d61d8327deb882cf99")
    IniWrite($sConfigPath, "Settings", "AutoBackup", "1")
    IniWrite($sConfigPath, "Settings", "LogLevel", "2")
    IniWrite($sConfigPath, "Settings", "Language", "RU")
    
    _Logger_Info("Конфигурация по умолчанию создана: " & $sConfigPath)
EndFunc

Func _Config_Load()
    Local $sConfigPath = @ScriptDir & "\config.ini"
    
    If Not FileExists($sConfigPath) Then
        _Logger_Warn("Файл конфигурации не найден, создаем новый")
        _Config_CreateDefault()
    EndIf
    
    ; Загрузка настроек в глобальные переменные при необходимости
    Local $bAutoBackup = IniRead($sConfigPath, "Settings", "AutoBackup", "1")
    Local $iLogLevel = IniRead($sConfigPath, "Settings", "LogLevel", "2")
    
    _Logger_Info("Конфигурация загружена: AutoBackup=" & $bAutoBackup & ", LogLevel=" & $iLogLevel)
EndFunc
