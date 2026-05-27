; ============================================================================
; Logger.au3 - Система логирования
; ============================================================================
#include-once

Global $hLogFile_Activity = -1
Global $hLogFile_Error = -1
Global $bFileLoggingEnabled = False
Global $sCurrentLogFile = ""

; ============================================================================
; ФУНКЦИИ ЛОГИРОВАНИЯ
; ============================================================================

Func _Logger_Init($sActivityLogPath, $sErrorLogPath)
    ; Закрываем старые файлы если открыты
    _Logger_Close()
    
    $hLogFile_Activity = FileOpen($sActivityLogPath, $FO_APPEND + $FO_UNICODE)
    $hLogFile_Error = FileOpen($sErrorLogPath, $FO_APPEND + $FO_UNICODE)
    
    If $hLogFile_Activity = -1 Or $hLogFile_Error = -1 Then
        ConsoleWrite("[LOGGER ERROR] Не удалось открыть файлы логов!" & @CRLF)
        Return False
    EndIf
    
    _Logger_Info("=== Логирование инициализировано ===")
    Return True
EndFunc

Func _Logger_Close()
    If $hLogFile_Activity <> -1 Then
        FileClose($hLogFile_Activity)
        $hLogFile_Activity = -1
    EndIf
    If $hLogFile_Error <> -1 Then
        FileClose($hLogFile_Error)
        $hLogFile_Error = -1
    EndIf
    $bFileLoggingEnabled = False
    $sCurrentLogFile = ""
EndFunc

Func _Logger_EnableFileLogging($sLogPath)
    If $bFileLoggingEnabled And $sCurrentLogFile = $sLogPath Then Return True
    
    _Logger_DisableFileLogging()
    
    $hLogFile_Current = FileOpen($sLogPath, $FO_OVERWRITE + $FO_UNICODE)
    If $hLogFile_Current = -1 Then
        ConsoleWrite("[LOGGER ERROR] Не удалось создать файл лога: " & $sLogPath & @CRLF)
        Return False
    EndIf
    
    $sCurrentLogFile = $sLogPath
    $bFileLoggingEnabled = True
    FileWriteLine($hLogFile_Current, "=== Лог операций запущен: " & _NowCalc() & " ===")
    Return True
EndFunc

Func _Logger_DisableFileLogging()
    If $hLogFile_Current <> -1 Then
        FileClose($hLogFile_Current)
        $hLogFile_Current = -1
    EndIf
    $bFileLoggingEnabled = False
    $sCurrentLogFile = ""
EndFunc

Func _Logger_Write($sLevel, $sMessage)
    Local $sTimestamp = _NowCalc()
    Local $sLogLine = $sTimestamp & " [" & $sLevel & "] " & $sMessage
    
    ; Пишем в консоль
    ConsoleWrite($sLogLine & @CRLF)
    
    ; Пишем в основной лог
    If $hLogFile_Activity <> -1 Then
        FileWriteLine($hLogFile_Activity, $sLogLine)
    EndIf
    
    ; Пишем в специальный лог операции если включен
    If $bFileLoggingEnabled And $hLogFile_Current <> -1 Then
        FileWriteLine($hLogFile_Current, $sLogLine)
    EndIf
EndFunc

Func _Logger_Info($sMessage)
    _Logger_Write("INFO", $sMessage)
EndFunc

Func _Logger_Warn($sMessage)
    _Logger_Write("WARN", $sMessage)
EndFunc

Func _Logger_Error($sMessage)
    _Logger_Write("ERROR", $sMessage)
    
    If $hLogFile_Error <> -1 Then
        FileWriteLine($hLogFile_Error, _NowCalc() & " [ERROR] " & $sMessage)
    EndIf
EndFunc
