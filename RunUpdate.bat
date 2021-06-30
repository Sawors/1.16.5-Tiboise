@ECHO OFF
del ".\1.16.5-Tiboise\" /f /q /s
rd ".\1.16.5-Tiboise\" /q /s
del ".\mods\" /f /q /s
del ".\config\" /f /q /s
git clone https://github.com/Sawors/1.16.5-Tiboise.git
del ".\1.16.5-Tiboise\options.txt" /q
del ".\1.16.5-Tiboise\optionsof.txt" /q
rem CONFIGS TO DELETE
rem {
del ".\1.16.5-Tiboise\config\craftpresence.properties" /f /q /s
del ".\1.16.5-Tiboise\config\rats-client.toml" /f /q /s
del ".\1.16.5-Tiboise\config\ambientsounds-client.json" /f /q /s
del ".\1.16.5-Tiboise\config\betterfoliage-client.toml" /f /q /s
del ".\1.16.5-Tiboise\config\jei-client.toml" /f /q /s
del ".\1.16.5-Tiboise\config\voicechat-client.toml" /f /q /s
del ".\1.16.5-Tiboise\config\jei\" /f /q /s
del ".\1.16.5-Tiboise\config\voicechat\" /f /q /s
del ".\1.16.5-Tiboise\shaderpacks\" /f /q /s
rem del ".\1.16.5-Tiboise\config\" /f /q /s
rem }
xcopy ".\1.16.5-Tiboise\" "." /i /e /y
del ".\1.16.5-Tiboise\" /f /q /s
rd ".\1.16.5-Tiboise" /q /s
echo:
echo:
echo  /================SAWORS=================\
echo  ^|                                       ^|
echo  ^|                                       ^|
echo  ^|           Modpack Updated !           ^|
echo  ^|                                       ^|
echo  ^|                                       ^|
echo  \=======================================/
echo:
echo:
pause