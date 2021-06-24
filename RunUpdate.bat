@ECHO OFF
del ".\1.16.5-Tiboise\" /f /q /s
rd ".\1.16.5-Tiboise\" /q /s
git clone https://github.com/Sawors/1.16.5-Tiboise.git
del ".\1.16.5-Tiboise\options.txt" /q
del ".\1.16.5-Tiboise\optionsof.txt" /q
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