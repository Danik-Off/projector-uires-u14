# Оптимизация Android-проектора NL5H00X (Hi3751V350) — инструкция

Пошаговая инструкция: как ускорить интерфейс проектора, убрать фоновую нагрузку и вендорскую телеметрию. Всё делается с компьютера по ADB, прошивка не перешивается, каждый шаг обратим.

Проверено в сентябре 2026 на устройстве из раздела «Справка → Устройство». На другой прошивке того же SoC часть шагов может отличаться — перед каждым шагом описано, как проверить результат.

## Что нужно

- Windows с `adb` в `PATH` (Android SDK Platform-Tools).
- Проектор и компьютер в одной сети; на проекторе включена отладка по сети (ADB по TCP, порт 5555). IP проектора смотреть в его настройках сети — ниже он обозначен как `<IP>`.
- Файлы из этого репозитория: `zz_optimize.rc` (init-файл), `zz_optimize.sh` (фоновый скрипт) и `uires.apk` (переключатель разрешения UI).
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

# Не проверять «есть ли интернет» через connectivitycheck.gstatic.com (из РФ тормозит, вешает «!» на Wi-Fi)
adb shell settings put global captive_portal_mode 0
adb shell settings put global captive_portal_detection_enabled 0

# Не ждать Play Protect при установке (он отключён) — adb install быстрее
adb shell settings put global package_verifier_enable 0
adb shell settings put global verifier_verify_adb_installs 0
```

Замечания:

- `max_cached_processes=4` — память освобождается быстрее, но Кинопоиск/Rutube после переключения чаще стартуют «с нуля» (2–4 с). Если это раздражает — `adb shell settings delete global activity_manager_constants`.
- Бакет ACTIVE для Кинопоиска/Rutube на фоновую работу не влияет — её блокирует шаг 2. Нужен он в основном лаунчеру.
- **`wm density` на этой прошивке не работает**: хук `ActivityManager.adjustDisplayDensityForPackage` (проп `vendor.nl.disneyplus.DpiAdjust`) сбрасывает density при каждом переключении приложений. Разрешение UI меняется иначе — шаг 6.

## Шаг 4. Root-настройки: init-файл и фоновый скрипт

Сборка **userdebug**, поэтому `adb root` работает. Root слетает после перезагрузки — перед этим шагом выполнять заново.

```powershell
adb root
adb remount
```

Установить два файла из репозитория: init-файл `zz_optimize.rc` (при каждой загрузке останавливает лишние демоны, выставляет параметры ядра и запускает скрипт) и сам скрипт `zz_optimize.sh`:

```powershell
adb push zz_optimize.rc /vendor/etc/init/zz_optimize.rc
adb push zz_optimize.sh /vendor/etc/zz_optimize.sh
adb shell "chmod 644 /vendor/etc/init/zz_optimize.rc /vendor/etc/zz_optimize.sh; chcon u:object_r:vendor_configs_file:s0 /vendor/etc/init/zz_optimize.rc /vendor/etc/zz_optimize.sh"
```

Оба файла должны быть с LF-переносами — `.gitattributes` в репозитории это гарантирует при клоне. Если редактировали руками в Windows-редакторе, проверить, что не появился CRLF (иначе `sh` на устройстве упадёт на первой же строке).

### Что делает `zz_optimize.rc`

```
on post-fs-data
    setprop dalvik.vm.heapgrowthlimit 192m

service zz_optimize /system/bin/sh /vendor/etc/zz_optimize.sh
    user root
    group root
    seclabel u:r:su:s0
    disabled
    oneshot

on property:sys.boot_completed=1
    stop boa
    stop perfprofd
    stop xiriservice
    stop storaged
    write /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor performance
    write /sys/block/mmcblk0/queue/read_ahead_kb 512
    setprop pm.dexopt.bg-dexopt speed
    setprop pm.dexopt.install speed
    setprop pm.dexopt.inactive speed
    start zz_optimize
```

| Строка | Зачем |
|---|---|
| `dalvik.vm.heapgrowthlimit 192m` | лимит кучи приложения по умолчанию 128 МБ — Кинопоиск на экранах с сотнями постеров упирается в него и постоянно запускает GC (микрозадержки при прокрутке). RAM 2 ГБ, можно больше. Читается zygote при старте → нужна перезагрузка. Именно `post-fs-data`: раньше (`on init`) значение перетирает `load_system_props` из init.rc |
| `stop boa` | веб-сервер от root на порту 80, открыт всей локальной сети, с CGI — дыра и лишний процесс |
| `stop perfprofd` | системный профилировщик |
| `stop xiriservice` | голосовой ассистент iFlytek, стучится в `openspeech.cn` |
| `stop storaged` | сборщик IO-статистики для bugreport'ов: 0.6 % CPU и сотни тысяч page faults впустую |
| governor `performance` | CPU всегда на 1 ГГц вместо 800/1000 по нагрузке — интерфейс отзывчивее, для проектора от сети нагрев не критичен |
| `read_ahead_kb 512` | eMMC читает крупнее — быстрее холодный старт приложений |
| `pm.dexopt.install speed` | новые и обновлённые приложения компилируются в `speed` сразу при установке (по умолчанию `speed-profile`, что без профиля = JIT). Установка на 20–60 с дольше, зато приложение быстрое с первого запуска |
| `pm.dexopt.bg-dexopt speed` | страховка: фоновая докомпиляция (раз в сутки при простое) тоже в `speed` |
| `pm.dexopt.inactive speed` | приложения, не открывавшиеся 10 дней, не понижаются обратно до `verify` (штатная экономия места, тут не нужна) |
| `start zz_optimize` | запуск скрипта ниже. `seclabel u:r:su:s0` — домен, в котором init может запускать shell на userdebug-сборке |

### Что делает `zz_optimize.sh`

Работает от root постоянно, просыпается раз в 30 с (в простое — 0 % CPU, это `sleep`):

1. **Wi-Fi power save выключен.** Драйвер по умолчанию засыпает между пакетами (`iw dev wlan0 get power_save` → `on`), отсюда рваный ping 4–9 мс. Устройство от розетки — экономить нечего; старт видео и подгрузка постеров ровнее. После переподключения Wi-Fi драйвер включает power save обратно — скрипт снова выключает.
2. **Фоновые приложения выгружаются через 5 минут.** Запрет фона из шага 2 не убивает процесс — Кинопоиск, Rutube и `:AppMetrica` висят в кэше и по чуть-чуть едят CPU и память. Скрипт считает, сколько каждое стороннее приложение провело в фоне, и по достижении `BG_TIMEOUT` (300 с) делает `am force-stop`. «В фоне» определяется по `oom_score_adj` процесса, который выставляет сам Android: 0 — на экране, ≤200 — видимое/перцептивное, 600 — текущий домашний лаунчер (какой бы ни был), 700 — предыдущее приложение, 900+ — кэш. Считаются только ≥700, поэтому лаунчер и то, что на экране, под выгрузку не попадают автоматически. Таймер не идёт, пока работает заставка или экран выключен (`mWakefulness != Awake`), и сбрасывается, когда приложение снова используется. Исключения (`KEEP`, допускаются shell-шаблоны): лаунчер, клавиатура, `local.uires`, `com.tvsas.*` (разрабатывается параллельно, включая `.debug`-сборку).

Настройки — в шапке скрипта: `BG_TIMEOUT`, `INTERVAL`, `KEEP`. Лог: `/data/local/tmp/zz_optimize.log`, текущие таймеры: `/data/local/tmp/zz_bg/<pkg>` (секунды в фоне).

Следствие, о котором надо помнить: фильм, поставленный на паузу и брошенный на 5 минут (без заставки), будет закрыт — позиция сохранится только если приложение само её запоминает.

### Применить прямо сейчас, не дожидаясь перезагрузки

Новый `service` init подхватит только после перезагрузки, поэтому скрипт первый раз запускается руками:

```powershell
adb shell "stop boa; stop perfprofd; stop xiriservice; stop storaged"
adb shell "echo performance > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
adb shell "echo 512 > /sys/block/mmcblk0/queue/read_ahead_kb"
adb shell "setprop pm.dexopt.install speed; setprop pm.dexopt.bg-dexopt speed; setprop pm.dexopt.inactive speed"
adb shell "(nohup sh /vendor/etc/zz_optimize.sh </dev/null >/dev/null 2>&1 &)"
adb shell service call bluetooth_manager 8        # выключить BT сразу
adb shell setprop persist.log.tag S               # заглушить логи приложений (logd ел 3 % CPU)
adb shell pm trim-caches 9999G
adb shell sm fstrim
```

**Не останавливать**: `hipluginserver` (видеоконвейер), `cameraserver` («Integrated Camera» — автофокус), `hwtvmw` (настройки картинки), `hwdlnaservice` (DLNA).

Проверка:

```powershell
adb shell getprop init.svc.boa                                          # stopped
adb shell cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor    # performance
adb shell "ps -A -o pid,args | grep zz_optimize"                        # sh /vendor/etc/zz_optimize.sh
adb shell iw dev wlan0 get power_save                                   # Power save: off
adb shell cat /data/local/tmp/zz_optimize.log                           # start … / wifi power_save -> off / force-stop …
```

## Шаг 5. AOT-компиляция приложений

По умолчанию приложения работают через JIT — на 4×ARMv7 @ 1 ГГц это заметно. Полная компиляция в `speed`:

```powershell
adb shell cmd package compile -m speed -f -a
```

Занимает 10–20 минут (83 пакета). **На это время устройство не трогать**: `dex2oat` занимает все 4 ядра и eMMC, `system_server` дважды ловил ANR по watchdog'у во время такого прогона (это и был «мягкий перезапуск system_server»). Если хочется без риска — компилировать по одному пакету: `cmd package compile -m speed -f <pkg>` для лаунчера, клавиатуры и видеоприложений, остальное оставить `bg-dexopt`. **Кинопоиск при массовом прогоне не компилируется** (большой APK, dex2oat падает) — после общего прогона обязательно отдельно:

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
| 1440×810 | 960×540 dp | канонический размер макетов Android TV — приложения выглядят как задумано, GPU рисует на 44 % меньше пикселей |
| **1280×720** (выбрано) | **853×480 dp** | максимум скорости, на 65 % меньше пикселей, чем в 1080p; чуть меньше канона — если где-то обрежется, вернуться на 1440×810 |

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
adb shell getprop init.svc.zz_optimize                                      # running
adb shell iw dev wlan0 get power_save                                       # Power save: off
adb shell cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor        # performance
adb shell cat /sys/block/mmcblk0/queue/read_ahead_kb                        # 512
adb shell settings get global bluetooth_on                                  # 0
adb shell wm size                                                           # Override size: 1280x720
adb shell cmd appops get ru.rutube.app.tv                                   # ignore
adb shell top -b -n 1 -m 12 -s 9                                            # ничего лишнего в топе
```

Практический тест: запустить фильм в Кинопоиске, выйти в лаунчер, открыть Rutube, вернуться — в `top` не должно быть процесса Rutube с заметным %CPU, когда он не на экране.

## Шаг 8. Лаунчер Projectivy

Лаунчер — то, что на экране 90 % времени, и на Mali-450 его эффекты стоят дороже всего остального: в `top` Projectivy 4.71 с настройками по умолчанию ест 20–30 % CPU, просто стоя на экране.

**В настройках лаунчера (пульт → Настройки Projectivy → Внешний вид):**

- Обои: статичная картинка или сплошной цвет вместо динамических (по умолчанию он скачивает и декодирует новые фоны).
- Размытие фона (blur) — выключить.
- Превью программ на карточках (play preview) — выключить.
- Тени, скругления, увеличение карточки при фокусе (zoom on focus), эффект ripple — выключить.
- Заставка: если используется заставка Projectivy — то же самое, статичная.

**Через adb (root)** — выключить его Firebase-аналитику и Crashlytics, которые с отключённым GMS только зря стучатся в сеть:

```powershell
@'
P=/data/data/com.spocky.projengmenu/shared_prefs/com.spocky.projengmenu_preferences.xml
am force-stop com.spocky.projengmenu
sed -i 's/name="general_enable_analytics" value="true"/name="general_enable_analytics" value="false"/' $P
sed -i 's/name="general_enable_crashlytics" value="true"/name="general_enable_crashlytics" value="false"/' $P
grep -oE 'general_enable_(analytics|crashlytics)" value="[a-z]*' $P
am start -a android.intent.action.MAIN -c android.intent.category.HOME >/dev/null
exit
'@ | adb shell
```

(Команды передаются через stdin — Windows-`adb` иначе ломает вложенные кавычки. Лаунчер на секунду перезапускается. Остальные настройки Projectivy в prefs хранятся только если менялись, поэтому их проще кликнуть в интерфейсе.)

## Откат

| Что | Как вернуть |
|---|---|
| Шаг 1, отключённые пакеты | `adb shell pm enable <pkg>` |
| Шаг 1, удалённые для пользователя | `adb shell cmd package install-existing <pkg>` |
| Шаг 2 | `adb shell cmd appops set <pkg> RUN_IN_BACKGROUND allow` и `RUN_ANY_IN_BACKGROUND allow` |
| Шаг 3, анимации | те же `settings put` со значением `1` |
| Шаг 3, BT / GPS | `settings put global bluetooth_on 1`; `settings put secure location_providers_allowed +gps` |
| Шаг 3, остальное | `settings delete global activity_manager_constants`, `auto_sync 1`, `send_action_app_error 1`, `am set-standby-bucket <pkg> 30`, `captive_portal_mode 1`, `package_verifier_enable 1` |
| Шаг 4 полностью | `adb root; adb remount; adb shell rm /vendor/etc/init/zz_optimize.rc /vendor/etc/zz_optimize.sh`, `adb shell setprop persist.log.tag ""`, перезагрузка |
| Шаг 4, только выгрузка фоновых | в `zz_optimize.sh` поднять `BG_TIMEOUT` или добавить пакет в `KEEP`, перезалить файл, `adb shell "stop zz_optimize; start zz_optimize"` |
| Шаг 5 | `adb shell cmd package compile -m quicken -f <pkg>` (или просто оставить — вреда нет) |
| Шаг 6 | `adb shell wm size reset`; `adb uninstall local.uires` |
| Шаг 8 | в настройках Projectivy вернуть эффекты; аналитика — те же `sed` со значением `true` |

## Известные ограничения

- `:AppMetrica` Кинопоиска отдельно не отключить без модификации приложения; шаг 2 не даёт ему работать, когда Кинопоиск не на экране, а скрипт шага 4 выгружает его через 5 минут.
- Выгрузка фоновых (шаг 4) не различает «брошенный» и «поставленный на паузу» фильм: если выйти в лаунчер на 5+ минут, приложение будет закрыто. Пока идёт заставка, таймер стоит.
- `hwtvmw` слушает TCP 4321 на всех интерфейсах — остановить нельзя (настройки картинки), можно закрыть через `iptables` (не делалось).
- Заводские/тестовые пакеты (`com.newlink.autotest`, `tvtestingtools`, `factorymenu`, `isuperred.ijkplayerdemo`) не отключались — они не запущены, выигрыш только косметический.
- Диагностика при заглушенных логах: `logcat -b crash` и `dumpsys dropbox` (падения, ANR, WTF) работают всегда; ANR-дампы — `/data/anr/`, нативные падения — `/data/tombstones/`. Буферы logcat здесь всего 64 КБ (`low_ram`), на длинную историю не рассчитывать; если нужно — временно `adb shell setprop persist.log.tag ""`.

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

### Что уже упёрлось в потолок (крутить бесполезно)

Проверено на устройстве — здесь выигрыша больше нет:

| Что | Почему |
|---|---|
| GPU Mali-450 MP2 | DVFS зафиксирован прошивкой на 500 МГц (`/sys/module/mali/parameters/g_mali_dvfs_min_frequency = max_frequency = 500000`) |
| CPU | только две ступени 800/1000 МГц, стоим на 1000; разгона нет |
| zram | уже `lz4`, `page-cluster=0`, `swappiness=60` — стандартно правильные значения |
| eMMC | планировщик `deadline`, запись 150 МБ/с — не узкое место |
| `debug.hwui.renderer=skiagl` | на GLES 2.0-железе Skia медленнее штатного OpenGL-рендерера, не пробовать |
| build.prop-«твики» из интернета (`ro.max.fling_velocity`, `windowsmgr.max_events_per_sec`, `debug.egl.hw`, `persist.sys.ui.hw`, `debug.composition.type` и т.п.) | на Android 9 эти свойства ничем не читаются, эффект плацебо |
| LMK (`minfree` 6/96/112/128/144/160 МБ, `lmkd` в режиме minfree) | значения адекватны 2 ГБ; PSI-режим в ядре этой прошивки недоступен |

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
adb shell cat /data/local/tmp/zz_optimize.log        # что выгрузил фоновый скрипт
adb shell "ls /data/local/tmp/zz_bg; cat /data/local/tmp/zz_bg/*"   # кто сколько секунд в фоне
```
