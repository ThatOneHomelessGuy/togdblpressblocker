# TOG Double Press Blocker
(togdblpressblocker)

Blocks pressing buttons multiple times per round, allows admins to add buttons to an ignore list, see button info, find buttons, and more. This plugin was developed mainly for Deathrun servers.

## Additional features:
<details><summary>Click to Open Spoiler</summary>
<p>
<pre><code>
* Buttons can be colored based on status (pressed vs not pressed).
* Settings are saved per-map, so each map is customizable. Settings saved are: Disable plugin for the map, glow colors for buttons based on status, and specific buttons being ignored by the plugin.
* Specific buttons can be ignored, and are saved in the per-map settings. Notes: This is important, since some buttons need to be pressed multiple times, and others you dont want colored by status. Additionally, the method used is based on how old the map is. In very old maps, the only good identifier for buttons is the coordinates. However, since buttons move when pressing them, you have to build in an adjustable tolerance that is saved in the per-map settings. Too high and it will catch other buttons....too low and it wont be recognised after it moves. If the map isnt very old, Hammer IDs are used to identify the buttons (Hammer eventually started forcing Hammer IDs for buttons). The Hammer ID method is clean and easy. The coordinates one can be buggy sometimes, but again, that is for old maps.
* Configurable admin flag(s) using the TOG Flag System. All buttons are listed in an admin menu. From the sub-menu for a specific button, the button can be triggered, beaconed, or can have all available info printed to console for you. Beacons and triggers are printed in chat for all to see (to prevent admin abuse). Plugin also notifies admins if a map has never been configured and buttons should be checked.
</code></pre>
</p>
</details>

## Installation:
* Put togdblpressblocker.smx in the following folder: /addons/sourcemod/plugins/


## CVars:
<details><summary>Click to View CVars</summary>
<p>

* **tdpb_version** - TOG Double Press Blocker: Version

* **tdpb_enable** - Enable plugin by default on each map? (0 = Disabled, 1 = Enabled)

* **tdpb_auto_ignore** - Automatically add buttons to the ignore list if the map triggers them and the feature is not disabled for the current map (0 = Disabled, 1 = Enabled).

* **tdpb_adminflag** - Admin Flag to check for.

* **tdpb_preglow_pre** - RGB value to use as default glow for unpressed butotns (0-255, with spaces between).

* **tdpb_glow_post** - RGB value to use as default glow for pressed butotns (0-255, with spaces between).

* **tdpb_origin_tolerance** - Distance tolerance in button coordinates check (used only if Hammer ID = 0 (old maps only)).
</p>
</details>

## Player Commands:
<details><summary>Click to View Player Commands</summary>
<p>

* **sm_buttons** - Opens button list menu.

* **sm_resetbuttons** - Resets buttons locked by plugin this round.

* **sm_ident** - Returns information about the entity in the client's crosshairs.

* **sm_preglow** - Sets glow color (RGB) of buttons before they are pressed.

* **sm_postglow** - Sets glow color (RGB) of buttons after they are pressed.

* **sm_ignore** - Tells plugin to not lock a specific button after it is pressed.

* **sm_tolerance** - Sets tolerance override for the map (only important on maps without Hammer IDs for buttons).

* **sm_removeautoignore** - Removes auto-ignore function for the given map (if applicable).

* **sm_enableautoignore** - Re-enables auto-ignore function for the given map (if applicable).
</p>
</details>

Note: After changing the cvars in your cfg file, be sure to rcon the new values to the server so that they take effect immediately.






### Check out my plugin list: http://www.togcoding.com/togcoding/index.php
