# Template-RebootESXiHosts-AfterUpdate

Disclaimer: I did not build this script from scatch, I borrow many ideas from other scripters in the net and improved on them. Hence you may notice some similarities with naming coventions and coding structure. 

This is a template which I created that will reboot ESXi hosts after updates. There are many times in operations where you need to put a host into maintanence mode, make some changes and reboot the host for the changes to be effective. If you are doing from GUI or manually from PowerCLI its a lot of work and waiting. 

This is an operational script, that is, this has been used to implement changes in critical environments, not someone's hello world lab. As such, the script is very conservatively. To prevent a runaway execution, where the script, due to execution or coding error, blindly put hosts into maintenenance mode one after another or reboots them one after another, there is a lot of checks before it moves on to the next stage. If a check fails, the scripts just exits to prevent a runaway scenario. 

