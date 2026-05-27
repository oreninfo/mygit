; ============================================================================
; Config.au3 - Управление конфигурацией приложения
; ============================================================================
#include-once

; Проверка и создание констант реестра (если еще не объявлены в главном скрипте)
If Not IsDeclared("HKEY_LOCAL_MACHINE") Then Global Const $HKEY_LOCAL_MACHINE = 0x80000002
If Not IsDeclared("HKEY_CURRENT_USER") Then Global Const $HKEY_CURRENT_USER = 0x80000001
If Not IsDeclared("HKEY_CLASSES_ROOT") Then Global Const $HKEY_CLASSES_ROOT = 0x80000000
If Not IsDeclared("HKEY_USERS") Then Global Const $HKEY_USERS = 0x80000003

If Not IsDeclared("KEY_QUERY_VALUE") Then Global Const $KEY_QUERY_VALUE = 0x0001
If Not IsDeclared("KEY_SET_VALUE") Then Global Const $KEY_SET_VALUE = 0x0002
If Not IsDeclared("KEY_CREATE_SUB_KEY") Then Global Const $KEY_CREATE_SUB_KEY = 0x0004
If Not IsDeclared("KEY_READ") Then Global Const $KEY_READ = 0x20019
If Not IsDeclared("KEY_WRITE") Then Global Const $KEY_WRITE = 0x20006
If Not IsDeclared("KEY_ALL_ACCESS") Then Global Const $KEY_ALL_ACCESS = 0xF003F

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
