# Template-RebootESXiHosts-AfterUpdate

Disclaimer: I did not build this script from scatch, I borrow many ideas from other scripters in the net and improved on them. Hence you may notice some similarities with naming coventions and coding structure. 

This is a template which I created that will reboot ESXi hosts after updates. There are many times in operations where you need to put a host into maintanence mode, make some changes and reboot the host for the changes to be effective. If you are doing from GUI or manually from PowerCLI its a lot of work and waiting. 

This is an operational script, that is, this has been used to implement changes in critical environments, not someone's hello world lab. As such, the script is very conservatively. To prevent a runaway execution, where the script, due to execution or coding error, blindly put hosts into maintenenance mode one after another or reboots them one after another, there is a lot of checks before it moves on to the next stage. If a check fails, the scripts just exits to prevent a runaway scenario. 

template-reboothosts-aftertask.ps1 -> This is template file you can use
Set-vmhostKernalPagePoolLimit.ps1 -> This is a sample of an actual operational script that I used

Currently the script only does 1 host at a time, when I have more time, I will look for code it for nth host at a time, since for some clusters you can really down more host at one go and it reduces your execution time.
