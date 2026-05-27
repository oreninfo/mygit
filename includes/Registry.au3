; ============================================================================
; Registry.au3 - Работа с реестром
; ============================================================================
#include-once
#include <WinAPIReg.au3>

; Константы уже объявлены в Config.au3 или главном скрипте через #include <WinAPIReg.au3>
; Здесь мы их не переобъявляем, а используем готовые

; ============================================================================
; ФУНКЦИИ РАБОТЫ С РЕЕСТРОМ
; ============================================================================

Func _Registry_ReadValue($sKeyPath, $sValueName, $sDefault = "")
    Local $sResult = RegRead($sKeyPath, $sValueName)
    If @error Then Return $sDefault
    Return $sResult
EndFunc

Func _Registry_WriteValue($sKeyPath, $sValueName, $vData, $iType = $REG_SZ)
    Local $bResult = RegWrite($sKeyPath, $sValueName, $iType, $vData)
    If @error Then
        _Logger_Error("Ошибка записи в реестр: " & $sKeyPath & "\" & $sValueName & ", код: " & @error)
        Return False
    EndIf
    Return True
EndFunc

Func _Registry_DeleteValue($sKeyPath, $sValueName = "")
    Local $bResult
    If $sValueName = "" Then
        $bResult = RegDelete($sKeyPath)
    Else
        $bResult = RegDelete($sKeyPath, $sValueName)
    EndIf
    
    If @error Then
        _Logger_Error("Ошибка удаления из реестра: " & $sKeyPath & ", код: " & @error)
        Return False
    EndIf
    Return True
EndFunc

Func _Registry_KeyExists($sKeyPath)
    Local $sResult = RegRead($sKeyPath, "")
    Return (@error = 0)
EndFunc

Func _Registry_CreateBackup($sBackupPath)
    ; Используем reg.exe для экспорта ключа USB
    Local $sUsbKey = "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\USB"
    Local $sCmd = 'reg export "' & $sUsbKey & '" "' & $sBackupPath & '" /y'
    
    Local $iPid = Run(@ComSpec & " /c " & $sCmd, "", @SW_HIDE, $STDERR_CHILD + $STDOUT_CHILD)
    ProcessWaitClose($iPid)
    Local $sOutput = StdoutRead($iPid)
    
    If FileExists($sBackupPath) Then
        _Logger_Info("Резервная копия создана: " & $sBackupPath)
        Return True
    Else
        _Logger_Error("Не удалось создать резервную копию: " & $sBackupPath)
        Return False
    EndIf
EndFunc

Func _Registry_DeleteKeyRecursive($sKeyPath, $bDryRun = False)
    If Not _Registry_KeyExists($sKeyPath) Then
        _Logger_Info("Ключ не найден: " & $sKeyPath)
        Return True
    EndIf
    
    If $bDryRun Then
        _Logger_Info("[SIM] Будет удален ключ: " & $sKeyPath)
        Return True
    EndIf
    
    ; Сначала удаляем подключи
    Local $i = 0
    While True
        Local $sSubKey = _WinAPI_RegEnumKeys($sKeyPath, $i)
        If @error Then ExitLoop
        
        Local $sFullSubKey = $sKeyPath & "\" & $sSubKey
        _Registry_DeleteKeyRecursive($sFullSubKey, $bDryRun)
        $i += 1
    WEnd
    
    ; Теперь удаляем сам ключ
    Local $bResult = RegDelete($sKeyPath)
    If @error Then
        _Logger_Error("Ошибка удаления ключа: " & $sKeyPath & ", код: " & @error)
        Return False
    EndIf
    
    _Logger_Info("Ключ удален: " & $sKeyPath)
    Return True
EndFunc
