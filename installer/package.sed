[Version]
Class=IEXPRESS
SEDVersion=3

[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=1
HideExtractAnimation=0
UseLongFileName=1
InsideCompressed=0
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=N
InstallPrompt=%InstallPrompt%
DisplayLicense=%DisplayLicense%
FinishMessage=%FinishMessage%
TargetName=%TargetName%
FriendlyName=%FriendlyName%
AppLaunched=%AppLaunched%
PostInstallCmd=%PostInstallCmd%
AdminQuietInstCmd=
UserQuietInstCmd=
SourceFiles=SourceFiles

[Strings]
InstallPrompt=
DisplayLicense=
FinishMessage=
TargetName=__TARGET_PATH__
FriendlyName=Hexagon Proxy Setup
AppLaunched=powershell.exe -NoProfile -ExecutionPolicy Bypass -File install.ps1
PostInstallCmd=<None>
FILE0="HexagonProxy.exe"
FILE1="LICENSE"
FILE2="LICENSING.md"
FILE3="SOURCE.md"
FILE4="THIRD_PARTY_NOTICES.md"
FILE5="Mihomo-LICENSE.txt"
FILE6="MetaRules-LICENSE.txt"
FILE7="install.ps1"
FILE8="uninstall.ps1"

[SourceFiles]
SourceFiles0=__SOURCE_PATH__

[SourceFiles0]
%FILE0%=
%FILE1%=
%FILE2%=
%FILE3%=
%FILE4%=
%FILE5%=
%FILE6%=
%FILE7%=
%FILE8%=
