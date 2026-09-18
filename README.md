# Оптимизация Android-проектора NL5H00X (Hi3751V350) — инструкция

Пошаговая инструкция: как ускорить интерфейс проектора, убрать фоновую нагрузку и вендорскую телеметрию. Всё делается с компьютера по ADB, прошивка не перешивается, каждый шаг обратим.

Проверено в сентябре 2026 на устройстве из раздела «Справка → Устройство». На другой прошивке того же SoC часть шагов может отличаться — перед каждым шагом описано, как проверить результат.

## Что нужно

- Windows с `adb` в `PATH` (Android SDK Platform-Tools).
- Проектор и компьютер в одной сети; на проекторе включена отладка по сети (ADB по TCP, порт 5555). IP проектора смотреть в его настройках сети — ниже он обозначен как `<IP>`.
- Файлы из этого репозитория: `zz_optimize.rc` (init-файл) и `uires.apk` (переключатель разрешения UI).
- Все команды ниже — для PowerShell. `adb shell "..."` в кавычках — одна команда на устройстве.

## Шаг 0. Подключиться

```powershell
adb connect <IP>:5555
adb devices          # должно быть <IP>:5555  device
```

Если `offline`/`unauthorized` — подтвердить запрос на экране проектора или `adb kill-server` и повторить.

## Шаг 1. Убрать лишние приложения (root не нужен)

Отключить Google-сервисы (без аккаунта Google они только едят память и сеть) и вендорскую телеметрию:

```powershell
adb shell pm disable-user --user 0 com.android.vending
adb shell pm disable-user --user 0 com.google.android.gms
adb shell pm disable-user --user 0 com.google.android.gsf
adb shell pm disable-user --user 0 com.google.android.gsf.login
adb shell pm disable-user --user 0 com.newlink.service      # DataUploadService / RegisterService / AutoSystemUpdateService
```

Удалить для пользователя ненужные предустановки (данные и APK остаются в системе, вернуть можно всегда):

```powershell
adb shell pm uninstall -k --user 0 com.android.chrome
adb shell pm uninstall -k --user 0 com.newlink.cast
adb shell pm uninstall -k --user 0 com.hisilicon.miracast
```

Так же можно убрать другие предустановки, если они есть (YouTube TV, Netflix, Office, магазин `zeasn`). Полный список пакетов: `adb shell pm list packages`, только сторонние: `pm list packages -3`.

**Не трогать**: `com.newlink.nlprovision` (контроль температуры), `com.hisilicon.tv.service`, `com.hisilicon.tvinput.external` (HDMI/VGA-входы), `com.zhiying.autofocus`, лаунчер и клавиатуру.

## Шаг 2. Запретить фоновую работу видеоприложениям (root не нужен)

Rutube после переключения на Кинопоиск продолжал работать в фоне (51 % CPU, 135 МБ), а `:AppMetrica` Кинопоиска — телеметрия — крутится всегда. Запрет фона решает оба случая:

```powershell
foreach ($p in "ru.rutube.app.tv","ru.kinopoisk.tv","ru.vk.store.tv") {
  adb shell cmd appops set $p RUN_IN_BACKGROUND ignore
  adb shell cmd appops set $p RUN_ANY_IN_BACKGROUND ignore
}
adb shell am force-stop ru.rutube.app.tv
```

Лаунчер (`com.spocky.projengmenu`) и клавиатуру (`org.liskovsoft.androidtv.rukeyboard`) **не ограничивать** — лаунчер должен жить в фоне, IME поднимает система.

Проверка: `adb shell cmd appops get ru.rutube.app.tv` → обе строки `ignore`.

## Шаг 3. Системные настройки (root не нужен)

```powershell
# Анимации вдвое короче (0 — совсем без анимаций, но некоторые приложения глючат)
adb shell settings put global window_animation_scale 0.5
adb shell settings put global transition_animation_scale 0.5
adb shell settings put global animator_duration_scale 0.5

# Bluetooth не поднимать после загрузки (пульт — ИК/2.4 ГГц-донгл, BT не нужен)
adb shell settings put global bluetooth_on 0

# GPS-провайдер выключить
adb shell settings put secure location_providers_allowed -gps

# Автосинхронизация и диалог «отправить отчёт об ошибке»
adb shell settings put global auto_sync 0
adb shell settings put secure send_action_app_error 0

# Не больше 4 кэшированных процессов в фоне (см. замечание ниже)
adb shell settings put global activity_manager_constants max_cached_processes=4

# App Standby включён, лаунчер и видеоприложения — в бакет ACTIVE
adb shell settings put global app_standby_enabled 1
adb shell settings put global adaptive_battery_management_enabled 1
adb shell am set-standby-bucket com.spocky.projengmenu 10
adb shell am set-standby-bucket ru.kinopoisk.tv 10
adb shell am set-standby-bucket ru.rutube.app.tv 10

# Доступ к скрытым API — нужен приложению из шага 6
adb shell settings put global hidden_api_policy_p_apps 1
adb shell settings put global hidden_api_policy_pre_p_apps 1

# Меню разработчика (удобно, необязательно)
adb shell settings put global development_settings_enabled 1
```

Замечания:

- `max_cached_processes=4` — память освобождается быстрее, но Кинопоиск/Rutube после переключения чаще стартуют «с нуля» (2–4 с). Если это раздражает — `adb shell settings delete global activity_manager_constants`.
- Бакет ACTIVE для Кинопоиска/Rutube на фоновую работу не влияет — её блокирует шаг 2. Нужен он в основном лаунчеру.
- **`wm density` на этой прошивке не работает**: хук `ActivityManager.adjustDisplayDensityForPackage` (проп `vendor.nl.disneyplus.DpiAdjust`) сбрасывает density при каждом переключении приложений. Разрешение UI меняется иначе — шаг 6.

## Шаг 4. Root-настройки и init-файл

Сборка **userdebug**, поэтому `adb root` работает. Root слетает после перезагрузки — перед этим шагом выполнять заново.

```powershell
adb root
adb remount
```

Установить init-файл, который при каждой загрузке останавливает лишние демоны и выставляет параметры ядра:

```powershell
adb push zz_optimize.rc /vendor/etc/init/zz_optimize.rc
adb shell "chmod 644 /vendor/etc/init/zz_optimize.rc; chcon u:object_r:vendor_configs_file:s0 /vendor/etc/init/zz_optimize.rc"
```

Содержимое `zz_optimize.rc`:

```
on property:sys.boot_completed=1
    stop boa
    stop perfprofd
    stop xiriservice
    write /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor performance
    write /sys/block/mmcblk0/queue/read_ahead_kb 512
    setprop pm.dexopt.bg-dexopt speed
    setprop pm.dexopt.install speed
    setprop pm.dexopt.inactive speed
```

Что это даёт:

| Строка | Зачем |
|---|---|
| `stop boa` | веб-сервер от root на порту 80, открыт всей локальной сети, с CGI — дыра и лишний процесс |
| `stop perfprofd` | системный профилировщик |
| `stop xiriservice` | голосовой ассистент iFlytek, стучится в `openspeech.cn` |
| governor `performance` | CPU всегда на 1 ГГц вместо 800/1000 по нагрузке — интерфейс отзывчивее, для проектора от сети нагрев не критичен |
| `read_ahead_kb 512` | eMMC читает крупнее — быстрее холодный старт приложений |
| `pm.dexopt.install speed` | новые и обновлённые приложения компилируются в `speed` сразу при установке (по умолчанию `speed-profile`, что без профиля = JIT). Установка на 20–60 с дольше, зато приложение быстрое с первого запуска |
| `pm.dexopt.bg-dexopt speed` | страховка: фоновая докомпиляция (раз в сутки при простое) тоже в `speed` |
| `pm.dexopt.inactive speed` | приложения, не открывавшиеся 10 дней, не понижаются обратно до `verify` (штатная экономия места, тут не нужна) |

Применить то же самое прямо сейчас, не дожидаясь перезагрузки:

```powershell
adb shell "stop boa; stop perfprofd; stop xiriservice"
adb shell "echo performance > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
adb shell "echo 512 > /sys/block/mmcblk0/queue/read_ahead_kb"
adb shell "setprop pm.dexopt.install speed; setprop pm.dexopt.bg-dexopt speed; setprop pm.dexopt.inactive speed"
adb shell service call bluetooth_manager 8        # выключить BT сразу
adb shell setprop persist.log.tag S               # заглушить логи приложений (logd ел 3 % CPU)
adb shell pm trim-caches 9999G
adb shell sm fstrim
```

**Не останавливать**: `hipluginserver` (видеоконвейер), `cameraserver` («Integrated Camera» — автофокус), `hwtvmw` (настройки картинки), `hwdlnaservice` (DLNA).

Проверка: `adb shell getprop init.svc.boa` → `stopped`; `adb shell cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor` → `performance`.

## Шаг 5. AOT-компиляция приложений

По умолчанию приложения работают через JIT — на 4×ARMv7 @ 1 ГГц это заметно. Полная компиляция в `speed`:

```powershell
adb shell cmd package compile -m speed -f -a
```

Занимает 10–20 минут (83 пакета). **Кинопоиск при массовом прогоне не компилируется** (большой APK, dex2oat падает) — после общего прогона обязательно отдельно:

```powershell
adb shell cmd package compile -m speed -f ru.kinopoisk.tv
```

Проверка каждого важного пакета — должно быть `[status=speed]`:

```powershell
foreach ($p in "com.spocky.projengmenu","ru.kinopoisk.tv","ru.rutube.app.tv","ru.vk.store.tv","org.liskovsoft.androidtv.rukeyboard") {
  "$p : " + (adb shell dumpsys package $p | Select-String -Pattern 'status=' | Select-Object -First 1)
}
```

Если у пакета `run-from-apk` — повторить компиляцию для него одного.

Этот массовый прогон нужен один раз — для уже установленных приложений. Всё, что ставится или обновляется **после** шага 4, компилируется в `speed` само, прямо при установке (`pm.dexopt.install`). Проверить: `adb shell getprop pm.dexopt.install` → `speed`.

## Шаг 6. Переключатель разрешения UI (`local.uires`)

Интерфейс рисуется в 1920×1080 на слабом Mali-450. Приложение из этой папки переключает разрешение UI (то же, что `adb shell wm size`), видео не затрагивается — оно идёт аппаратным оверлеем в родном разрешении.

```powershell
adb install -r uires.apk        # из папки репозитория
adb shell pm grant local.uires android.permission.WRITE_SECURE_SETTINGS
```

(`hidden_api_policy_*` уже выставлены на шаге 3.) Приложение «Разрешение UI» появится в лаунчере. Открыть — фокус стоит на следующем пресете, одно нажатие OK переключает по кругу. Выбор сохраняется после перезагрузки.

| Пресет | dp при 240 dpi | Когда |
|---|---|---|
| 1920×1080 | 1280×720 dp | родное, если что-то выглядит неправильно |
| **1440×810** (рекомендуется) | **960×540 dp** | канонический размер макетов Android TV — приложения выглядят как задумано, GPU рисует на 44 % меньше пикселей |
| 1280×720 | 853×480 dp | максимум скорости; чуть меньше канона — где-то может обрезаться |

То же вручную: `adb shell wm size 1440x810` / `adb shell wm size reset`.

Пересборка приложения (если понадобится): `.\build.ps1` — без Gradle, цепочка aapt2 → javac → d8 → zipalign → apksigner. Нужны Android SDK (`ANDROID_HOME`, build-tools и platform любой свежей версии) и JDK 17+ (`JAVA_HOME` или `javac` в `PATH`). Исходники в `src/` и `res/`, результат `build\uires.apk`.

Ключ подписи `build\debug.keystore` создаётся при первой сборке и в репозиторий не входит. Готовый `uires.apk` подписан другим ключом, поэтому свою сборку поверх него `adb install -r` не поставит — сначала `adb uninstall local.uires`, потом установить свою. Свой ключ потом не терять, иначе то же самое при каждом обновлении.

## Шаг 7. Перезагрузка и проверка

```powershell
adb reboot
```

После загрузки (root снова понадобится только для root-команд):

```powershell
adb connect <IP>:5555
adb shell getprop init.svc.boa                                              # stopped
adb shell getprop pm.dexopt.install                                         # speed
adb shell cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor        # performance
adb shell cat /sys/block/mmcblk0/queue/read_ahead_kb                        # 512
adb shell settings get global bluetooth_on                                  # 0
adb shell wm size                                                           # Override size: 1440x810
adb shell cmd appops get ru.rutube.app.tv                                   # ignore
adb shell top -b -n 1 -m 12 -s 9                                            # ничего лишнего в топе
```

Практический тест: запустить фильм в Кинопоиске, выйти в лаунчер, открыть Rutube, вернуться — в `top` не должно быть процесса Rutube с заметным %CPU, когда он не на экране.

## Откат

| Что | Как вернуть |
|---|---|
| Шаг 1, отключённые пакеты | `adb shell pm enable <pkg>` |
| Шаг 1, удалённые для пользователя | `adb shell cmd package install-existing <pkg>` |
| Шаг 2 | `adb shell cmd appops set <pkg> RUN_IN_BACKGROUND allow` и `RUN_ANY_IN_BACKGROUND allow` |
| Шаг 3, анимации | те же `settings put` со значением `1` |
| Шаг 3, BT / GPS | `settings put global bluetooth_on 1`; `settings put secure location_providers_allowed +gps` |
| Шаг 3, остальное | `settings delete global activity_manager_constants`, `auto_sync 1`, `send_action_app_error 1`, `am set-standby-bucket <pkg> 30` |
| Шаг 4 полностью | `adb root; adb remount; adb shell rm /vendor/etc/init/zz_optimize.rc`, `adb shell setprop persist.log.tag ""`, перезагрузка |
| Шаг 5 | `adb shell cmd package compile -m quicken -f <pkg>` (или просто оставить — вреда нет) |
| Шаг 6 | `adb shell wm size reset`; `adb uninstall local.uires` |

## Известные ограничения

- `:AppMetrica` Кинопоиска отдельно не отключить без модификации приложения; шаг 2 хотя бы не даёт ему работать, когда Кинопоиск не на экране.
- `hwtvmw` слушает TCP 4321 на всех интерфейсах — остановить нельзя (настройки картинки), можно закрыть через `iptables` (не делалось).
- Заводские/тестовые пакеты (`com.newlink.autotest`, `tvtestingtools`, `factorymenu`, `isuperred.ijkplayerdemo`) не отключались — они не запущены, выигрыш только косметический.
- Однажды мягко перезапускался `system_server` (без перезагрузки). Связи с переключателем UI в контролируемом тесте не выявлено, причина не установлена — логи заглушены. Если повторится: `adb shell setprop persist.log.tag ""` и смотреть `adb logcat -b crash`.

## Справка

### Устройство

| Параметр | Значение |
|---|---|
| Модель | HiDPTAndroid_Hi3751V350 (Hisilicon), продукт NL5H00X (Newlink) |
| SoC | Hi3751 «bigfish», 4×ARMv7 @ 1 ГГц (частоты 800/1000 МГц), GPU Mali-450 |
| RAM | 2 ГБ + zram 636 МБ, `ro.config.low_ram=true` |
| Накопитель | eMMC 26 ГБ (занято ~0.6 ГБ), запись ~150 МБ/с — не узкое место |
| Wi-Fi | только 2.4 ГГц, 86 Мбит/с, RSSI −50, ping до роутера ~5 мс — для 1080p-стриминга хватает |
| Android | 9 (API 28), сборка **userdebug** → `adb root` и `adb remount` работают |
| Экран | 1920×1080 @ 240 dpi |
| Лаунчер | Projectivy (`com.spocky.projengmenu`) |
| Пользовательские приложения | Кинопоиск, Rutube, VK Store, русская клавиатура (liskovsoft) |
| Термодатчики | `/sys/class/thermal` отсутствует — температуру штатно не посмотреть (за неё отвечает `com.newlink.nlprovision`/`TempService`) |
| Doze | никогда не включается (нет батареи), App Standby работает только по бакетам |

### Почему именно это (диагностика)

1. Rutube в фоне ел 51 % CPU и 135 МБ, пока шёл фильм в Кинопоиске — его `TvPlaybackService` не останавливался при переключении приложений → шаг 2.
2. Кинопоиск запускает 3 процесса: плеер, `:passport`, `:AppMetrica` (телеметрия, 10–19 % CPU во время фильма) → шаг 2.
3. Swap активно использовался (тысячи major faults у плеера) — памяти впритык → шаги 1, 3.
4. Load average ~13 — **ложный**: 7 потоков драйверов HiSilicon (`disp_mix_panel`, `hi_vpss_process`, `dmx_monitor`, …) вечно висят в состоянии D. Реальную нагрузку смотреть по `top`/`vmstat`.
5. Вендорские демоны `boa`, `perfprofd`, `xiriservice`, `com.newlink.service` → шаги 1, 4.
6. Bluetooth со всеми профилями, GPS, анимации 1.0 → шаг 3.
7. UI в 1920×1080 на Mali-450 → шаг 6.
8. Хук `adjustDisplayDensityForPackage` в прошивке делает `wm density` бесполезным → в шаге 6 меняется размер, а не density.

### Полезные команды

```powershell
adb shell top -b -n 1 -m 12 -s 9                    # кто грузит CPU (столбец %CPU, не load average)
adb shell dumpsys cpuinfo | Select-Object -First 15  # среднее по процессам за последние минуты
adb shell dumpsys package <pkg> | findstr status     # состояние компиляции
adb shell cmd appops get <pkg>                       # фоновые ограничения
adb shell am get-standby-bucket <pkg>                # бакет App Standby (10 = ACTIVE)
adb shell wm size                                    # текущее разрешение UI
adb shell getprop init.svc.boa                       # stopped = веб-сервер не работает
adb shell cat /proc/meminfo                          # память / swap
```
