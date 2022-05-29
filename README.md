## About

Rewrite of [tEntDev](https://forums.alliedmods.net/showthread.php?t=143081), but no need extensions.

## Require

- L4D2 linux dedicated server
- Sourcemod 1.11

## Use

Select an entity
- `sm_netprop_select` select aiming entity.
- `sm_netprop_select <entity index>` select specified entity.
- `sm_netprop_selectself` select self.

Watch entity netprops changes (auto)
- `sm_netprop_watch` show changed netprops of the selected entity every second.
- `sm_netprop_stopwatch` stop watching an entity.

Watch entity netprops changes (manual)
- `sm_netprop_save` saves an entity netprops for later comparison.
- `sm_netprop_compare` compares the current netprops with the saved ones.

Other
- `sm_netprop_menu` display the menu for the above commands.
- `sm_netprop_showall` show all netprops values of the selected entity.
- `sm_netprop_output <"file.txt">` save the selected entity's all netprops info to file in KeyValues format. save to game root by default, with path will save to another directory.
