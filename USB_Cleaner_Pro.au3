;#RequireAdmin
#AutoIt3Wrapper_Icon=usb.ico
#AutoIt3Wrapper_Outfile=USB_Cleaner.exe
#AutoIt3Wrapper_Res_Description=USB Device History Cleaner
#AutoIt3Wrapper_Res_Fileversion=2.0.0.0
#AutoIt3Wrapper_Res_Language=2073

; ============================================================================
; ПОДКЛЮЧЕНИЕ БИБЛИОТЕК
; ============================================================================
#include <GUIConstantsEx.au3>
#include <GuiListView.au3>
#include <GuiMenu.au3>
#include <Array.au3>
#include <File.au3>
#include <Date.au3>
#include <Crypt.au3>
#include <String.au3>
#include <MsgBoxConstants.au3>
#include <WinAPI.au3>
#include <WinAPIReg.au3>
#include <WinAPIDiag.au3>
#include <Constants.au3>
#include <WindowsConstants.au3>
#include <EditConstants.au3>
#include <ComboConstants.au3>
#include <StaticConstants.au3>
#include <ButtonConstants.au3>
#include <ListViewConstants.au3>
#include <FileConstants.au3>
#include <StringConstants.au3>
#include <StructureConstants.au3>
#include <ProgressConstants.au3>
#include <APIRegConstants.au3>
#include <SecurityConstants.au3>

#include "includes\Config.au3"
#include "includes\Logger.au3"
#include "includes\Registry.au3"
#include "includes\USBScanner.au3"
#include "includes\Cleaner.au3"

; ============================================================================
; ГЛОБАЛЬНЫЕ КОНСТАНТЫ И ПЕРЕМЕННЫЕ
; ============================================================================
Global Const $APP_NAME = "USB Cleaner Pro"
Global Const $APP_VERSION = "2.0.0"
Global Const $CONFIG_FILE = @ScriptDir & "\config.ini"
Global Const $SERIALS_FILE = @ScriptDir & "\serials.dat"
Global Const $LOG_DIR = @ScriptDir & "\logs"
Global Const $DEFAULT_PASSWORD_HASH = "5f4dcc3b5aa765d61d8327deb882cf99"

Global $hGUI, $hListView, $hSearchInput, $hFilterCombo
Global $hMenuListView, $idCtxCopySN, $idCtxOpenReg, $idCtxExport
Global $idChkBackup, $idChkLog, $idChkDryRun, $idChkLogOnly
Global $idBtnSelectAll, $idBtnDelete, $idBtnCancel, $idBtnRefresh, $idBtnExport
Global $idLblCount, $idInputSerial, $idStatusLbl
Global $aSerialsRevoked[0], $aSerialsActive[0], $aSerialsNumbers[0]
Global $bExpertMode = False, $bDryRun = False

; Мастер-массив для хранения всех отсканированных устройств
Global $aMasterDevices[0]

; ============================================================================
; ТОЧКА ВХОДА
; ============================================================================
Main()

Func Main()
    _InitApp()
    If Not _Authenticate() Then Exit
    _LoadSerialLists()
    _CreateGUI()
    _RefreshDeviceList()
    _MainLoop()
    _Shutdown()
    Exit
EndFunc

; ============================================================================
; ИНИЦИАЛИЗАЦИЯ
; ============================================================================
Func _InitApp()
    If Not FileExists($LOG_DIR) Then DirCreate($LOG_DIR)
    _Logger_Init($LOG_DIR & "\activity.log", $LOG_DIR & "\errors.log")
    _Logger_Info("Приложение запущено. Версия: " & $APP_VERSION)
    
    If Not FileExists($CONFIG_FILE) Then _Config_CreateDefault()
    _Config_Load()
    
    If Not FileExists($SERIALS_FILE) Then
        _Logger_Error("Файл serials.dat не найден!")
        MsgBox($MB_ICONERROR, $APP_NAME, "Отсутствует файл со списком устройств: serials.dat")
        Exit
    EndIf
EndFunc

; ============================================================================
; АВТОРИЗАЦИЯ
; ============================================================================
Func _Authenticate()
    Local $sPassword, $sHash
    While True
        $sPassword = InputBox("Авторизация", "Введите пароль для доступа:", "", "*", 250, 140, -1, -1, 10)
        If @error Then Return False
        
        $sHash = _NormalizeHash(_Crypt_HashData($sPassword, $CALG_MD5))
        Local $sStoredHash = _NormalizeHash(IniRead($CONFIG_FILE, "Security", "PasswordHash", $DEFAULT_PASSWORD_HASH))
        
        ConsoleWrite("> [AUTH] Введенный хеш: " & $sHash & @CRLF)
        ConsoleWrite("> [AUTH] Хранимый хеш: " & $sStoredHash & @CRLF)
        
        If $sHash = $sStoredHash Then
            _Logger_Info("Авторизация успешна")
            Return True
        Else
            _Logger_Warn("Неверная попытка входа")
            If MsgBox($MB_RETRYCANCEL + $MB_ICONWARNING, "Ошибка", "Неверный пароль. Повторить?") = $IDCANCEL Then
                Return False
            EndIf
        EndIf
    WEnd
EndFunc

Func _NormalizeHash($vHash)
    Local $sStr = String($vHash)
    If StringLeft($sStr, 2) = "0x" Then $sStr = StringMid($sStr, 3)
    Return StringLower($sStr)
EndFunc

; ============================================================================
; ЗАГРУЗКА СПИСКОВ УСТРОЙСТВ
; ============================================================================
Func _LoadSerialLists()
    Local $hKey = _Crypt_DeriveKey("USB_Cleaner_Key_2026", $CALG_AES_256)
    If @error Then
        _Logger_Error("Не удалось создать крипто-ключ: " & @error)
        Return
    EndIf
    
    Local $hFile = FileOpen($SERIALS_FILE, $FO_BINARY + $FO_READ)
    If $hFile = -1 Then
        _Logger_Error("Не удалось открыть " & $SERIALS_FILE)
        _Crypt_DestroyKey($hKey)
        Return
    EndIf
    
    Local $sEncrypted = FileRead($hFile)
    FileClose($hFile)
    
    Local $bDecrypted = _Crypt_DecryptData($sEncrypted, "USB_Cleaner_Key_2026", $CALG_AES_256)
    If @error Then
        _Logger_Error("Ошибка дешифровки: " & @error)
        _Crypt_DestroyKey($hKey)
        Return
    EndIf
    
    Local $sData = BinaryToString($bDecrypted)
    Local $aLines = StringSplit($sData, @CRLF, $STR_NOCOUNT)
    
    For $sLine In $aLines
        $sLine = StringStripWS($sLine, $STR_STRIPALL)
        If $sLine = "" Or StringLeft($sLine, 1) = ";" Then ContinueLoop
        
        Local $aParts = StringSplit($sLine, "|", $STR_NOCOUNT)
        If UBound($aParts) < 2 Then ContinueLoop
        
        Switch $aParts[0]
            Case "R"
                _ArrayAdd($aSerialsRevoked, $aParts[1])
            Case "A"
                _ArrayAdd($aSerialsActive, $aParts[1])
                _ArrayAdd($aSerialsNumbers, $aParts[2])
        EndSwitch
    Next
    
    _Crypt_DestroyKey($hKey)
    _Logger_Info("Загружено устройств: списанных=" & UBound($aSerialsRevoked) & _
                 ", активных=" & UBound($aSerialsActive))
EndFunc

; ============================================================================
; СОЗДАНИЕ ИНТЕРФЕЙСА
; ============================================================================
Func _CreateGUI()
    $hGUI = GUICreate($APP_NAME & " v" & $APP_VERSION, 1280, 640, -1, -1, _
                      BitOR($WS_OVERLAPPEDWINDOW, $WS_MINIMIZEBOX, $WS_MAXIMIZEBOX))
    GUISetBkColor(0xF0F0F0)
    GUISetIcon("shell32.dll", 24)
    
    GUICtrlCreateLabel("🔍 Поиск:", 15, 12)
    $hSearchInput = GUICtrlCreateInput("", 70, 10, 200, 22, $ES_AUTOHSCROLL)
    GUICtrlSetTip(-1, "Введите часть серийного номера, Vid/Pid или имени устройства")
    
    GUICtrlCreateLabel("Фильтр:", 285, 12)
    $hFilterCombo = GUICtrlCreateCombo("Все устройства", 340, 10, 180, 22, $CBS_DROPDOWNLIST)
    GUICtrlSetData(-1, "Запоминающие устройства|Неизвестные|Зарегистрированные|Списанные")
    
    GUICtrlCreateLabel("Найденные USB-устройства:", 15, 42)
    $hListView = _GUICtrlListView_Create($hGUI, _
        "✓|Vid/Pid|Класс|Тип устройства|Имя|Серийный номер|Первое подключение|Последнее подключение|Статус", _
        15, 62, 1250, 440, _
        BitOR($LVS_SHOWSELALWAYS, $LVS_NOSORTHEADER, $LVS_SINGLESEL), _
        BitOR($LVS_EX_FULLROWSELECT, $LVS_EX_GRIDLINES, $LVS_EX_CHECKBOXES, $LVS_EX_DOUBLEBUFFER))
        
    _GUICtrlListView_SetColumnWidth($hListView, 0, 25)
    _GUICtrlListView_SetColumnWidth($hListView, 1, 140)
    _GUICtrlListView_SetColumnWidth($hListView, 2, 100)
    _GUICtrlListView_SetColumnWidth($hListView, 3, 150)
    _GUICtrlListView_SetColumnWidth($hListView, 4, 200)
    _GUICtrlListView_SetColumnWidth($hListView, 5, 140)
    _GUICtrlListView_SetColumnWidth($hListView, 6, 130)
    _GUICtrlListView_SetColumnWidth($hListView, 7, 130)
    _GUICtrlListView_SetColumnWidth($hListView, 8, 120)
    
    $hMenuListView = _GUICtrlMenu_CreatePopup()
    $idCtxCopySN = _GUICtrlMenu_AddMenuItem($hMenuListView, "Копировать серийный номер")
    $idCtxOpenReg = _GUICtrlMenu_AddMenuItem($hMenuListView, "Открыть ключ в RegEdit")
    _GUICtrlMenu_AddMenuItem($hMenuListView, "")
    $idCtxExport = _GUICtrlMenu_AddMenuItem($hMenuListView, "Экспорт информации")
    
    GUICtrlCreateGroup("Параметры операции", 15, 510, 800, 105)
    $idChkBackup = GUICtrlCreateCheckbox("Создать резервную копию реестра", 25, 530, 250, 20)
    GUICtrlSetTip(-1, "Рекомендуется перед удалением")
    GUICtrlSetState(-1, $GUI_CHECKED)
    
    $idChkLog = GUICtrlCreateCheckbox("Вести журнал операций", 25, 555, 200, 20)
    GUICtrlSetTip(-1, "Записывать действия в log-файл")
    GUICtrlSetState(-1, $GUI_CHECKED)
    
    $idChkDryRun = GUICtrlCreateCheckbox("Режим симуляции (без реального удаления)", 25, 580, 300, 20)
    GUICtrlSetTip(-1, "Только показать, что будет удалено")
    $bDryRun = True
    GUICtrlSetState(-1, $GUI_CHECKED)
    
    $idChkLogOnly = GUICtrlCreateCheckbox("Очистить только системные логи", 280, 530, 220, 20)
    GUICtrlSetTip(-1, "Не затрагивать реестр, только Prefetch/Temp/логи")
    
    GUICtrlCreateLabel("Доп. серийный номер:", 520, 532)
    $idInputSerial = GUICtrlCreateInput("", 640, 530, 170, 22)
    GUICtrlSetTip(-1, "Введите серийный номер для добавления в список удаления")
    
    GUICtrlCreateLabel("Всего устройств:", 15, 495, 100, 15)
    $idLblCount = GUICtrlCreateLabel("0", 110, 495, 40, 15, $SS_RIGHT)
    GUICtrlSetFont(-1, 9, 700)
    
    $idBtnRefresh = GUICtrlCreateButton("⟳ Обновить", 1100, 512, 80, 25)
    GUICtrlSetTip(-1, "Пересканировать систему (F5)")
    
    $idBtnSelectAll = GUICtrlCreateButton("Выбрать всё", 1100, 542, 80, 25)
    
    $idBtnDelete = GUICtrlCreateButton("🗑️ Удалить", 1100, 572, 80, 30, $BS_MULTILINE)
    GUICtrlSetFont(-1, 9, 700)
    GUICtrlSetColor(-1, 0xC00000)
    GUICtrlSetTip(-1, "Удалить выбранные устройства (Enter)")
    
    $idBtnExport = GUICtrlCreateButton("📤 Отчёт", 1200, 512, 70, 25)
    GUICtrlSetTip(-1, "Экспортировать список устройств в CSV")
    
    $idBtnCancel = GUICtrlCreateButton("✕ Выход", 1200, 572, 70, 30, $BS_MULTILINE)
    GUICtrlSetTip(-1, "Закрыть программу (Esc)")
    
    $idStatusLbl = GUICtrlCreateLabel("Готово", 15, 620, 1250, 15, $SS_CENTER)
    
    GUIRegisterMsg($WM_NOTIFY, "_WM_NOTIFY_Handler")
    GUISetAccelerators(_CreateAccelerators())
    
    GUISetState(@SW_SHOW)
    _Logger_Info("Интерфейс создан")
    Return $hGUI
EndFunc

Func _CreateAccelerators()
    Local $aAccel[3][2] = [ _
        ["{F5}", $idBtnRefresh], _
        ["{ENTER}", $idBtnDelete], _
        ["{ESC}", $idBtnCancel] _
    ]
    Return $aAccel
EndFunc

; ============================================================================
; ГЛАВНЫЙ ЦИКЛ
; ============================================================================
Func _MainLoop()
    Local $msg, $sIndices, $iSelected, $sSerial, $sVidPid, $sRegPath, $tPoint
    
    While True
        $msg = GUIGetMsg()
        
        Switch $msg
            Case $GUI_EVENT_CLOSE, $idBtnCancel
                ExitLoop
                
            Case $idBtnRefresh
                _RefreshDeviceList()
                
            Case $idBtnSelectAll
                _ToggleSelectAll()
                
            Case $idBtnDelete
                _ProcessDeletion()
                
            Case $idBtnExport
                _ExportReport()
                
            Case $idChkDryRun
                $bDryRun = (GUICtrlRead($idChkDryRun) = $GUI_CHECKED)
                If $bDryRun Then
                    GUICtrlSetBkColor($idBtnDelete, 0xFFE0A0)
                    GUICtrlSetTip($idBtnDelete, "Режим симуляции: изменения не применяются")
                Else
                    GUICtrlSetBkColor($idBtnDelete, 0xFFFFFF)
                    GUICtrlSetTip($idBtnDelete, "Удалить выбранные устройства (Enter)")
                EndIf
                
            Case $hSearchInput, $hFilterCombo
                _ApplyFilters()
                
            Case $GUI_EVENT_SECONDARYUP
                If _WinAPI_GetFocus() = GUICtrlGetHandle($hListView) Then
                    $sIndices = _GUICtrlListView_GetSelectedIndices($hListView)
                    $iSelected = ($sIndices <> "") ? Number($sIndices) : -1
                    
                    If $iSelected >= 0 Then
                        $tPoint = _WinAPI_GetMousePos(True, $hGUI)
                        _GUICtrlMenu_TrackPopupMenu($hMenuListView, $hGUI, $tPoint.X, $tPoint.Y)
                    EndIf
                EndIf
                
            Case $idCtxCopySN
                $sIndices = _GUICtrlListView_GetSelectedIndices($hListView)
                $iSelected = ($sIndices <> "") ? Number($sIndices) : -1
                If $iSelected >= 0 Then
                    $sSerial = _GUICtrlListView_GetItemText($hListView, $iSelected, 5)
                    If $sSerial <> "" Then
                        ClipPut($sSerial)
                        _StatusBar_Show("Серийный номер скопирован", 2000)
                    EndIf
                EndIf
                
            Case $idCtxOpenReg
                $sIndices = _GUICtrlListView_GetSelectedIndices($hListView)
                $iSelected = ($sIndices <> "") ? Number($sIndices) : -1
                If $iSelected >= 0 Then
                    $sVidPid = _GUICtrlListView_GetItemText($hListView, $iSelected, 1)
                    $sSerial = _GUICtrlListView_GetItemText($hListView, $iSelected, 5)
                    If $sVidPid <> "" And $sSerial <> "" Then
                        $sRegPath = "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\USB\" & $sVidPid & "\" & $sSerial
                        ShellExecute("regedit.exe", "/e """ & @ScriptDir & "\device_reg.reg"" """ & $sRegPath & """")
                    EndIf
                EndIf
                
            Case $idCtxExport
                _ExportDeviceInfo()
        EndSwitch
        Sleep(10)
    WEnd
EndFunc

; ============================================================================
; СКАНИРОВАНИЕ И ОТОБРАЖЕНИЕ УСТРОЙСТВ
; ============================================================================
Func _RefreshDeviceList()
    _Logger_Info("Начато сканирование USB-устройств")
    _GUICtrlListView_DeleteAllItems($hListView)
    GUICtrlSetData($idLblCount, "0")
    
    ProgressOn("Сканирование", "Поиск USB-устройств в реестре...", "0%")
    
    Local $aFound = _USB_ScanAll()
    
    If Not IsArray($aFound) Or UBound($aFound) = 0 Then
        ProgressOff()
        _StatusBar_Show("Устройства не найдены или сканер вернул ошибку.")
        ReDim $aMasterDevices[0]
        Return
    EndIf
    
    ReDim $aMasterDevices[0]
    Local $iRows = UBound($aFound)
    Local $iCount = 0, $iStoreCount = 0
    
    _GUICtrlListView_BeginUpdate($hListView)
    
    For $i = 0 To $iRows - 1
        Local $sVidPid  = $aFound[$i][0]
        Local $sClass   = $aFound[$i][1]
        Local $sType    = $aFound[$i][2]
        Local $sName    = $aFound[$i][3]
        Local $sSerial  = $aFound[$i][4]
        Local $sFirst   = $aFound[$i][5]
        Local $sLast    = $aFound[$i][6]
        
        Local $sStatus = _GetDeviceStatus($sSerial)
        Local $iColor = ($sStatus = "Утиль") ? 0xC04040 : (($sStatus <> "Не зарегистрирован") ? 0x008000 : 0x000000)
        
        Local $sRowData = $sVidPid & "|" & $sClass & "|" & $sType & "|" & $sName & "|" & $sSerial & "|" & $sFirst & "|" & $sLast & "|" & $sStatus & "|" & $iColor
        _ArrayAdd($aMasterDevices, $sRowData)
        
        Local $iItem = _GUICtrlListView_AddItem($hListView, "", -1)
        _GUICtrlListView_AddSubItem($hListView, $iItem, $sVidPid, 1)
        _GUICtrlListView_AddSubItem($hListView, $iItem, $sClass, 2)
        _GUICtrlListView_AddSubItem($hListView, $iItem, $sType, 3)
        _GUICtrlListView_AddSubItem($hListView, $iItem, $sName, 4)
        _GUICtrlListView_AddSubItem($hListView, $iItem, $sSerial, 5)
        _GUICtrlListView_AddSubItem($hListView, $iItem, $sFirst, 6)
        _GUICtrlListView_AddSubItem($hListView, $iItem, $sLast, 7)
        _GUICtrlListView_AddSubItem($hListView, $iItem, $sStatus, 8)
        
        ; Используем стандартную функцию вместо _GUICtrlListView_SetItemColor
        _GUICtrlListView_SetItemText($hListView, $iItem, $sStatus, 8)
        
        If StringInStr($sType, "Запоминающее", 1) Or StringInStr($sClass, "USBSTOR", 1) Then $iStoreCount += 1
        $iCount += 1
        
        If Mod($i, 10) = 0 Then
            ProgressSet(Round(($i / $iRows) * 100), Round(($i / $iRows) * 100) & "%", "Обработано: " & $i & " из " & $iRows)
        EndIf
    Next
    
    _GUICtrlListView_EndUpdate($hListView)
    ProgressSet(100, "100%", "Завершено!")
    Sleep(300)
    ProgressOff()
    
    GUICtrlSetData($idLblCount, $iCount)
    _Logger_Info("Сканирование завершено. Найдено устройств: " & $iCount)
    _ApplyFilters()
EndFunc

Func _GetDeviceStatus($sSerial)
    If _ArraySearch($aSerialsRevoked, $sSerial) >= 0 Then Return "Утиль"
    Local $iIdx = _ArraySearch($aSerialsActive, $sSerial)
    If $iIdx >= 0 Then Return ($aSerialsNumbers[$iIdx] <> "") ? $aSerialsNumbers[$iIdx] : "Активен (без номера)"
    Return "Не зарегистрирован"
EndFunc

; ============================================================================
; ФИЛЬТРАЦИЯ И ПОИСК
; ============================================================================
Func _ApplyFilters()
    Local $sSearch = StringLower(StringStripWS(GUICtrlRead($hSearchInput), $STR_STRIPALL))
    Local $sFilter = GUICtrlRead($hFilterCombo)
    Local $iVisible = 0
    
    If UBound($aMasterDevices) = 0 Then 
        _StatusBar_Show("Список устройств пуст.")
        Return 
    EndIf
    
    _GUICtrlListView_BeginUpdate($hListView)
    _GUICtrlListView_DeleteAllItems($hListView)
    
    For $i = 0 To UBound($aMasterDevices) - 1
        Local $aParts = StringSplit($aMasterDevices[$i], "|", $STR_NOCOUNT)
        If UBound($aParts) < 9 Then ContinueLoop
        
        Local $bShow = True
        Local $sType = $aParts[2]
        Local $sStatus = $aParts[7]
        Local $iColor = Number($aParts[8])
        
        If $sSearch <> "" Then
            $bShow = False
            For $j = 0 To UBound($aParts) - 1
                If StringInStr(StringLower($aParts[$j]), $sSearch) Then
                    $bShow = True
                    ExitLoop
                EndIf
            Next
        EndIf
        
        If $bShow And $sFilter <> "Все устройства" Then
            Switch $sFilter
                Case "Запоминающие устройства"
                    $bShow = StringInStr($sType, "Запоминающее", 1) > 0
                Case "Неизвестные"
                    $bShow = ($sStatus = "Не зарегистрирован")
                Case "Зарегистрированные"
                    $bShow = ($sStatus <> "Не зарегистрирован" And $sStatus <> "Утиль")
                Case "Списанные"
                    $bShow = ($sStatus = "Утиль")
            EndSwitch
        EndIf
        
        If $bShow Then
            Local $iItem = _GUICtrlListView_AddItem($hListView, "", -1)
            _GUICtrlListView_AddSubItem($hListView, $iItem, $aParts[0], 1)
            _GUICtrlListView_AddSubItem($hListView, $iItem, $aParts[1], 2)
            _GUICtrlListView_AddSubItem($hListView, $iItem, $aParts[2], 3)
            _GUICtrlListView_AddSubItem($hListView, $iItem, $aParts[3], 4)
            _GUICtrlListView_AddSubItem($hListView, $iItem, $aParts[4], 5)
            _GUICtrlListView_AddSubItem($hListView, $iItem, $aParts[5], 6)
            _GUICtrlListView_AddSubItem($hListView, $iItem, $aParts[6], 7)
            _GUICtrlListView_AddSubItem($hListView, $iItem, $sStatus, 8)
            
            $iVisible += 1
        EndIf
    Next
    
    _GUICtrlListView_EndUpdate($hListView)
    _StatusBar_Show("Показано: " & $iVisible & " из " & UBound($aMasterDevices))
    GUICtrlSetData($idLblCount, $iVisible)
EndFunc

; ============================================================================
; УДАЛЕНИЕ УСТРОЙСТВ
; ============================================================================
Func _ProcessDeletion()
    Local $aToDelete[0], $sCustomSerial = StringStripWS(GUICtrlRead($idInputSerial), $STR_STRIPALL)
    
    For $i = 0 To _GUICtrlListView_GetItemCount($hListView) - 1
        If _GUICtrlListView_GetItemChecked($hListView, $i) Then
            Local $sSerial = _GUICtrlListView_GetItemText($hListView, $i, 5)
            Local $sVidPid = _GUICtrlListView_GetItemText($hListView, $i, 1)
            If $sSerial <> "" Then _ArrayAdd($aToDelete, $sSerial)
        EndIf
    Next
    
    If $sCustomSerial <> "" Then _ArrayAdd($aToDelete, $sCustomSerial)
    $aToDelete = _ArrayUnique($aToDelete)
    _ArrayDelete($aToDelete, 0)
    
    If UBound($aToDelete) = 0 Then
        MsgBox($MB_ICONINFORMATION, $APP_NAME, "Выберите хотя бы одно устройство для удаления")
        Return
    EndIf
    
    If Not _ConfirmDeletion($aToDelete) Then Return
    _SetUIEnabled(False)
    
    If GUICtrlRead($idChkBackup) = $GUI_CHECKED And Not $bDryRun Then
        _Logger_Info("Создание резервной копии реестра...")
        If Not _Registry_CreateBackup(@ScriptDir & "\USB_Cleaner_Backup_" & @YEAR & @MON & @DAY & ".reg") Then
            If MsgBox($MB_YESNO + $MB_ICONWARNING, "Внимание", "Не удалось создать резервную копию реестра. Продолжить удаление?") = $IDNO Then
                _SetUIEnabled(True)
                Return
            EndIf
        EndIf
    EndIf
    
    If GUICtrlRead($idChkLog) = $GUI_CHECKED Then
        _Logger_EnableFileLogging($LOG_DIR & "\deletion_" & @YEAR & @MON & @DAY & "_" & @HOUR & @MIN & ".log")
    EndIf
    
    ProgressOn("Удаление следов", "Инициализация...", "0%")
    If GUICtrlRead($idChkLogOnly) = $GUI_CHECKED Then
        _Cleaner_ClearSystemLogs($bDryRun)
        ProgressSet(100, "100%", "Очистка логов завершена!")
    Else
        _Cleaner_RemoveUSBDevices($aToDelete, $bDryRun)
        _Cleaner_ClearSystemLogs($bDryRun)
        _Cleaner_RemoveUserData($aToDelete, $bDryRun)
        ProgressSet(100, "100%", "Очистка завершена!")
    EndIf
    Sleep(500)
    ProgressOff()
    
    _Logger_DisableFileLogging()
    _SetUIEnabled(True)
    _StatusBar_Show("Удаление завершено. Обработано устройств: " & UBound($aToDelete), 3000)
    
    If Not $bDryRun Then
        If MsgBox($MB_YESNO + $MB_ICONQUESTION, "Готово", "Пересканировать систему для обновления списка?") = $IDYES Then
            _RefreshDeviceList()
        EndIf
    EndIf
EndFunc

Func _ConfirmDeletion(ByRef $aSerials)
    Local $iMax = 9
    If UBound($aSerials) < $iMax Then $iMax = UBound($aSerials)
    
    Local $sMsg = "Будут удалены следы подключения " & UBound($aSerials) & " устройств:" & @CRLF & @CRLF
    For $i = 0 To $iMax - 1
        $sMsg &= "• " & _StringTrimCenter($aSerials[$i], 40) & @CRLF
    Next
    If UBound($aSerials) > 10 Then $sMsg &= @CRLF & "... и ещё " & (UBound($aSerials) - 10) & " устройств"
    
    If $bDryRun Then
        $sMsg &= @CRLF & @CRLF & "⚠ РЕЖИМ СИМУЛЯЦИИ: изменения НЕ будут применены"
    Else
        $sMsg &= @CRLF & @CRLF & "⚠ ВНИМАНИЕ: Это действие необратимо!"
    EndIf
    Return (MsgBox($MB_YESNO + $MB_ICONWARNING + $MB_DEFBUTTON2, $APP_NAME & " - Подтверждение", $sMsg) = $IDYES)
EndFunc

Func _SetUIEnabled($bEnabled)
    Local $aControls = [$idBtnRefresh, $idBtnSelectAll, $idBtnDelete, $idBtnExport, _
                        $idChkBackup, $idChkLog, $idChkDryRun, $idChkLogOnly, _
                        $hSearchInput, $hFilterCombo, $idInputSerial]
    For $idCtrl In $aControls
        GUICtrlSetState($idCtrl, $bEnabled ? $GUI_ENABLE : $GUI_DISABLE)
    Next
EndFunc

; ============================================================================
; ЭКСПОРТ И ОТЧЁТЫ
; ============================================================================
Func _ExportReport()
    Local $sFile = FileSaveDialog("Экспорт отчёта", @ScriptDir, "CSV-файлы (*.csv)", 18, _
                                  "USB_Devices_" & @YEAR & @MON & @DAY & ".csv")
    If @error Then Return
    
    Local $hFile = FileOpen($sFile, $FO_OVERWRITE + $FO_UNICODE)
    If $hFile = -1 Then
        MsgBox($MB_ICONERROR, "Ошибка", "Не удалось создать файл: " & $sFile)
        Return
    EndIf
    
    FileWriteLine($hFile, "№;Vid/Pid;Class;Type;Name;Serial;FirstConnected;LastConnected;Status")
    For $i = 0 To _GUICtrlListView_GetItemCount($hListView) - 1
        Local $sLine = ""
        For $j = 1 To 8
            $sLine &= _GUICtrlListView_GetItemText($hListView, $i, $j) & ";"
        Next
        FileWriteLine($hFile, StringTrimRight($sLine, 1))
    Next
    
    FileClose($hFile)
    _StatusBar_Show("Отчёт экспортирован: " & $sFile, 3000)
    _Logger_Info("Экспорт отчёта: " & $sFile)
EndFunc

Func _ExportDeviceInfo()
    Local $sIndices = _GUICtrlListView_GetSelectedIndices($hListView)
    Local $iSelected = ($sIndices <> "") ? Number($sIndices) : -1
    If $iSelected < 0 Then
        MsgBox($MB_ICONINFORMATION, $APP_NAME, "Выберите устройство для экспорта")
        Return
    EndIf
    
    Local $sInfo = "Информация об устройстве" & @CRLF & _
                   _StringRepeat("=", 50) & @CRLF & @CRLF
    Local $aHeaders = ["Vid/Pid", "Class", "Type", "Name", "Serial", "FirstConnected", "LastConnected", "Status"]
    
    For $j = 1 To 8
        Local $sHeader = $aHeaders[$j-1]
        Local $sValue = _GUICtrlListView_GetItemText($hListView, $iSelected, $j)
        $sInfo &= $sHeader & ":" & @TAB & $sValue & @CRLF
    Next
    
    ClipPut($sInfo)
    _StatusBar_Show("Информация скопирована в буфер обмена", 2000)
EndFunc

; ============================================================================
; ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
; ============================================================================
Func _ToggleSelectAll()
    Local $bCheck = True
    For $i = 0 To _GUICtrlListView_GetItemCount($hListView) - 1
        If Not _GUICtrlListView_GetItemChecked($hListView, $i) Then
            $bCheck = True
            ExitLoop
        EndIf
        $bCheck = False
    Next
    
    For $i = 0 To _GUICtrlListView_GetItemCount($hListView) - 1
        _GUICtrlListView_SetItemChecked($hListView, $i, $bCheck)
    Next
    GUICtrlSetData($idBtnSelectAll, $bCheck ? "Снять всё" : "Выбрать всё")
    _StatusBar_Show($bCheck ? "Выбраны все устройства" : "Снято выделение")
EndFunc

Func _WM_NOTIFY_Handler($hWnd, $iMsg, $wParam, $lParam)
    #forceref $hWnd, $iMsg, $wParam
    Local $tNMHDR = DllStructCreate($tagNMHDR, $lParam)
    Local $iCode = DllStructGetData($tNMHDR, 3)
    If $wParam = $hListView And $iCode = $NM_RCLICK Then Return 0
    Return $GUI_RUNDEFMSG
EndFunc

Func _StatusBar_Show($sText, $iDuration = 0)
    GUICtrlSetData($idStatusLbl, $sText)
    If $iDuration > 0 Then AdlibRegister("_StatusBar_Clear", $iDuration)
EndFunc

Func _StatusBar_Clear()
    GUICtrlSetData($idStatusLbl, "Готово")
    AdlibUnRegister("_StatusBar_Clear")
EndFunc

Func _Shutdown()
    _Logger_Info("Приложение завершено")
    _Logger_Close()
    GUIDelete($hGUI)
EndFunc

Func _StringTrimCenter($sText, $iMaxLen)
    If StringLen($sText) <= $iMaxLen Then Return $sText
    Local $iTrim = Int(($iMaxLen - 3) / 2)
    Return StringLeft($sText, $iTrim) & "..." & StringRight($sText, $iTrim)
EndFunc
