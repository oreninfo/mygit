; ============================================================================
; USBScanner.au3 - Сканирование USB-устройств в реестре
; ============================================================================
#include-once
#include <WinAPIReg.au3>

; ============================================================================
; ФУНКЦИИ СКАНИРОВАНИЯ
; ============================================================================

Func _USB_ScanAll()
    Local $aDevices[0][9] ; Vid/Pid, Class, Type, Name, Serial, First, Last, Status, Color
    
    ; Путь к ключам USB устройств
    Local $sBaseKey = "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\USB"
    
    ; Получаем список VID/PID
    Local $i = 0
    While True
        Local $sVidPid = RegEnumKey($sBaseKey, $i)
        If @error Then ExitLoop
        
        ; Получаем список серийных номеров для этого VID/PID
        Local $j = 0
        While True
            Local $sSerial = RegEnumKey($sBaseKey & "\" & $sVidPid, $j)
            If @error Then ExitLoop
            
            ; Пропускаем системные ключи
            If $sSerial = "Properties" Or StringLeft($sSerial, 1) = "{" Then
                $j += 1
                ContinueLoop
            EndIf
            
            ; Читаем информацию об устройстве
            Local $sDeviceKey = $sBaseKey & "\" & $sVidPid & "\" & $sSerial
            Local $sFriendlyName = _Registry_ReadValue($sDeviceKey & "\Properties", "{a45c254e-df1c-4efd-8020-67d146a850e0}.10", "")
            If $sFriendlyName = "" Then
                $sFriendlyName = _Registry_ReadValue($sDeviceKey, "FriendlyName", "Неизвестное устройство")
            EndIf
            
            ; Определяем класс устройства
            Local $sClass = _GetDeviceClass($sVidPid, $sFriendlyName)
            
            ; Определяем тип устройства
            Local $sType = _GetDeviceType($sClass, $sFriendlyName)
            
            ; Получаем даты подключений
            Local $sFirst = _GetFirstConnectDate($sVidPid, $sSerial)
            Local $sLast = _GetLastConnectDate($sVidPid, $sSerial)
            
            ; Добавляем в массив
            Local $iNewSize = UBound($aDevices) + 1
            ReDim $aDevices[$iNewSize][9]
            
            $aDevices[$iNewSize - 1][0] = $sVidPid
            $aDevices[$iNewSize - 1][1] = $sClass
            $aDevices[$iNewSize - 1][2] = $sType
            $aDevices[$iNewSize - 1][3] = $sFriendlyName
            $aDevices[$iNewSize - 1][4] = $sSerial
            $aDevices[$iNewSize - 1][5] = $sFirst
            $aDevices[$iNewSize - 1][6] = $sLast
            $aDevices[$iNewSize - 1][7] = "" ; Статус заполняется в главном скрипте
            $aDevices[$iNewSize - 1][8] = 0x000000 ; Цвет заполняется в главном скрипте
            
            $j += 1
        WEnd
        
        $i += 1
    WEnd
    
    _Logger_Info("Сканирование завершено. Найдено устройств: " & UBound($aDevices))
    Return $aDevices
EndFunc

Func _GetDeviceClass($sVidPid, $sFriendlyName)
    ; Проверяем по VID
    Local $sVid = StringUpper(StringLeft($sVidPid, 4))
    
    ; Известные производители
    Switch $sVid
        Case "VID_0781" ; SanDisk
            Return "SanDisk"
        Case "VID_0951" ; Kingston
            Return "Kingston"
        Case "VID_090C" ; Silicon Motion
            Return "SiliconMotion"
        Case "VID_13FE" ; Phison
            Return "Phison"
        Case "VID_058D" ; Micron
            Return "Micron"
        Case "VID_046A" ; Cherry
            Return "Cherry"
        Case "VID_045E" ; Microsoft
            Return "Microsoft"
        Case "VID_045E" ; HP
            Return "HP"
        Case Else
            ; Проверяем по имени
            If StringInStr($sFriendlyName, "USB Mass Storage", 1) Or _
               StringInStr($sFriendlyName, "Запоминающее устройство", 1) Or _
               StringInStr($sFriendlyName, "Flash", 1) Or _
               StringInStr($sFriendlyName, "Disk", 1) Then
                Return "USBSTOR"
            ElseIf StringInStr($sFriendlyName, "Hub", 1) Then
                Return "USB Hub"
            ElseIf StringInStr($sFriendlyName, "Keyboard", 1) Or _
                   StringInStr($sFriendlyName, "Клавиатура", 1) Then
                Return "HID Keyboard"
            ElseIf StringInStr($sFriendlyName, "Mouse", 1) Or _
                   StringInStr($sFriendlyName, "Мышь", 1) Then
                Return "HID Mouse"
            Else
                Return "Unknown"
            EndIf
    EndSwitch
EndFunc

Func _GetDeviceType($sClass, $sFriendlyName)
    If $sClass = "USBSTOR" Or _
       StringInStr($sFriendlyName, "Mass Storage", 1) Or _
       StringInStr($sFriendlyName, "Запоминающее", 1) Or _
       StringInStr($sFriendlyName, "Flash", 1) Or _
       StringInStr($sFriendlyName, "Disk", 1) Then
        Return "Запоминающее устройство"
    ElseIf $sClass = "USB Hub" Or StringInStr($sFriendlyName, "Hub", 1) Then
        Return "USB Hub"
    ElseIf StringInStr($sClass, "Keyboard", 1) Or StringInStr($sFriendlyName, "Клавиатура", 1) Then
        Return "Клавиатура"
    ElseIf StringInStr($sClass, "Mouse", 1) Or StringInStr($sFriendlyName, "Мышь", 1) Then
        Return "Мышь"
    Else
        Return "Другое устройство"
    EndIf
EndFunc

Func _GetFirstConnectDate($sVidPid, $sSerial)
    ; Пытаемся получить из SetupAPI log или реестра
    Local $sKey = "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\USB\" & $sVidPid & "\" & $sSerial
    Local $sCreated = _Registry_ReadValue($sKey & "\Properties", "{83da6326-97a6-4088-9453-a1923f573b29}.100", "")
    
    If $sCreated <> "" Then
        ; Конвертируем FILETIME в дату
        Return _ConvertFileTimeToDate($sCreated)
    EndIf
    
    Return "Неизвестно"
EndFunc

Func _GetLastConnectDate($sVidPid, $sSerial)
    ; Пытаемся получить из реестра последнее подключение
    Local $sKey = "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\USB\" & $sVidPid & "\" & $sSerial
    Local $sLastArrival = _Registry_ReadValue($sKey & "\Properties", "{83da6326-97a6-4088-9453-a1923f573b29}.104", "")
    
    If $sLastArrival <> "" Then
        Return _ConvertFileTimeToDate($sLastArrival)
    EndIf
    
    Return "Неизвестно"
EndFunc

Func _ConvertFileTimeToDate($sFileTime)
    ; Упрощенная конвертация (требует доработки для точности)
    ; В реальном проекте использовать _WinAPI_FileTimeToLocalFileTime и _WinAPI_FileTimeToSystemTime
    Return "Неизвестно" ; Заглушка
EndFunc
