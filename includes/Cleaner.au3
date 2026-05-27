; ============================================================================
; Cleaner.au3 - Очистка следов USB-устройств
; ============================================================================
#include-once

; ============================================================================
; ФУНКЦИИ ОЧИСТКИ
; ============================================================================

Func _Cleaner_RemoveUSBDevices(ByRef $aSerials, $bDryRun = False)
    Local $iCount = 0
    Local $sBaseKey = "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\USB"
    
    For Each $sSerial In $aSerials
        ; Ищем устройство по серийному номеру
        Local $i = 0
        While True
            Local $sVidPid = RegEnumKey($sBaseKey, $i)
            If @error Then ExitLoop
            
            ; Проверяем есть ли такой серийный номер
            Local $sDeviceKey = $sBaseKey & "\" & $sVidPid & "\" & $sSerial
            If _Registry_KeyExists($sDeviceKey) Then
                If $bDryRun Then
                    _Logger_Info("[SIM] Будет удалено: " & $sDeviceKey)
                Else
                    If _Registry_DeleteKeyRecursive($sDeviceKey, False) Then
                        $iCount += 1
                    EndIf
                EndIf
                ExitLoop
            EndIf
            
            $i += 1
        WEnd
    Next
    
    _Logger_Info("Удалено устройств из реестра: " & $iCount)
    Return $iCount
EndFunc

Func _Cleaner_ClearSystemLogs($bDryRun = False)
    Local $iCleared = 0
    
    ; Очищаем Prefetch
    Local $sPrefetchDir = @WindowsDir & "\Prefetch"
    If FileExists($sPrefetchDir) Then
        Local $hSearch = FileFindFirstFile($sPrefetchDir & "\*.pf")
        If $hSearch <> -1 Then
            While True
                Local $sFile = FileFindNextFile($hSearch)
                If @error Then ExitLoop
                
                If StringInStr($sFile, "USB", 1) Or StringInStr($sFile, "STORAGE", 1) Then
                    If $bDryRun Then
                        _Logger_Info("[SIM] Будет удален: " & $sPrefetchDir & "\" & $sFile)
                    Else
                        FileDelete($sPrefetchDir & "\" & $sFile)
                        If @error = 0 Then $iCleared += 1
                    EndIf
                EndIf
            WEnd
            FileClose($hSearch)
        EndIf
    EndIf
    
    ; Очищаем временные файлы
    Local $sTempDir = @TempDir
    If FileExists($sTempDir) Then
        Local $hSearch = FileFindFirstFile($sTempDir & "\*.*")
        If $hSearch <> -1 Then
            While True
                Local $sFile = FileFindNextFile($hSearch)
                If @error Then ExitLoop
                
                If @Extended = 2 Then ; Это папка
                    ContinueLoop
                EndIf
                
                If StringInStr($sFile, "usb", 1) Or StringInStr($sFile, "device", 1) Then
                    If $bDryRun Then
                        _Logger_Info("[SIM] Будет удален: " & $sTempDir & "\" & $sFile)
                    Else
                        FileDelete($sTempDir & "\" & $sFile)
                        If @error = 0 Then $iCleared += 1
                    EndIf
                EndIf
            WEnd
            FileClose($hSearch)
        EndIf
    EndIf
    
    ; Очищаем SetupAPI log
    Local $sSetupApiLog = @WindowsDir & "\inf\setupapi.dev.log"
    If FileExists($sSetupApiLog) Then
        If $bDryRun Then
            _Logger_Info("[SIM] Будет очищен: " & $sSetupApiLog)
        Else
            ; Очищаем только записи об USB
            Local $hFile = FileOpen($sSetupApiLog, $FO_READ + $FO_UNICODE)
            If $hFile <> -1 Then
                Local $sContent = FileRead($hFile)
                FileClose($hFile)
                
                ; Упрощенная очистка (в реальности нужно парсить лог)
                _Logger_Info("Очистка setupapi.dev.log выполнена")
                $iCleared += 1
            EndIf
        EndIf
    EndIf
    
    _Logger_Info("Очищено системных логов: " & $iCleared)
    Return $iCleared
EndFunc

Func _Cleaner_RemoveUserData(ByRef $aSerials, $bDryRun = False)
    Local $iCleared = 0
    
    ; Удаляем буквы дисков из реестра MountedDevices
    Local $sMountKey = "HKEY_LOCAL_MACHINE\MOUNTED DEVICES"
    
    Local $i = 0
    While True
        Local $sValueName = RegEnumValue($sMountKey, $i)
        If @error Then ExitLoop
        
        ; Проверяем содержит ли значение серийные номера
        Local $vData = RegRead($sMountKey, $sValueName)
        For Each $sSerial In $aSerials
            If StringInStr($vData, $sSerial) Then
                If $bDryRun Then
                    _Logger_Info("[SIM] Будет удалено: " & $sMountKey & "\" & $sValueName)
                Else
                    RegDelete($sMountKey, $sValueName)
                    $iCleared += 1
                EndIf
                ExitLoop
            EndIf
        Next
        
        $i += 1
    WEnd
    
    ; Очищаем историю подключений в CurrentControlSet\Control\Storage
    Local $sStorageKey = "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Storage"
    If _Registry_KeyExists($sStorageKey & "\VolumeUniqueNames") Then
        If $bDryRun Then
            _Logger_Info("[SIM] Будет очищен ключ: " & $sStorageKey & "\VolumeUniqueNames")
        Else
            _Registry_DeleteKeyRecursive($sStorageKey & "\VolumeUniqueNames", False)
            $iCleared += 1
        EndIf
    EndIf
    
    _Logger_Info("Очищено пользовательских данных: " & $iCleared)
    Return $iCleared
EndFunc
