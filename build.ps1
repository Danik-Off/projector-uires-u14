$ErrorActionPreference = "Stop"
$d   = $PSScriptRoot
$b   = Join-Path $d "build"

# Android SDK: ANDROID_HOME / ANDROID_SDK_ROOT; берутся самые новые build-tools и platform
$sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } elseif ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } else { "$env:LOCALAPPDATA\Android\Sdk" }
$bt  = (Get-ChildItem "$sdk\build-tools" -Directory | Sort-Object { [version]$_.Name } | Select-Object -Last 1).FullName
$jar = (Get-ChildItem "$sdk\platforms" -Directory | Sort-Object Name | Select-Object -Last 1).FullName + "\android.jar"
# JDK 17+: JAVA_HOME или javac из PATH
$jdk = if ($env:JAVA_HOME) { "$env:JAVA_HOME\bin" } else { Split-Path (Get-Command javac).Source }

New-Item -ItemType Directory -Force "$b\gen", "$b\classes" | Out-Null

& "$bt\aapt2.exe" compile --dir "$d\res" -o "$b\res.zip"
if ($LASTEXITCODE) { throw "aapt2 compile failed" }

& "$bt\aapt2.exe" link -o "$b\base.apk" --manifest "$d\AndroidManifest.xml" -I $jar --java "$b\gen" "$b\res.zip"
if ($LASTEXITCODE) { throw "aapt2 link failed" }

$sources = Get-ChildItem -Recurse "$d\src", "$b\gen" -Filter *.java | ForEach-Object { $_.FullName }
& "$jdk\javac.exe" -encoding UTF-8 -source 8 -target 8 -nowarn -bootclasspath $jar -d "$b\classes" $sources
if ($LASTEXITCODE) { throw "javac failed" }

$classes = Get-ChildItem -Recurse "$b\classes" -Filter *.class | ForEach-Object { $_.FullName }
& "$bt\d8.bat" --lib $jar --min-api 21 --output $b $classes
if ($LASTEXITCODE) { throw "d8 failed" }

Push-Location $b
& "$jdk\jar.exe" uf base.apk classes.dex
Pop-Location

& "$bt\zipalign.exe" -f 4 "$b\base.apk" "$b\aligned.apk"
if ($LASTEXITCODE) { throw "zipalign failed" }

if (-not (Test-Path "$b\debug.keystore")) {
    & "$jdk\keytool.exe" -genkeypair -keystore "$b\debug.keystore" -storepass android -keypass android -alias key -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=uires"
}
& "$bt\apksigner.bat" sign --ks "$b\debug.keystore" --ks-pass pass:android --key-pass pass:android --out "$b\uires.apk" "$b\aligned.apk"
if ($LASTEXITCODE) { throw "sign failed" }

& "$bt\apksigner.bat" verify "$b\uires.apk"
Get-Item "$b\uires.apk" | Select-Object Name, Length
