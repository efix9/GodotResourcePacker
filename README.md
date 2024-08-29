# Godot Resource Packer - by Kaivexx

## Description
Godot Resource Packer is a Godot 4.3 plugin that allows you to easily share resources (like scenes) and all their dependencies as a single file you can export, then import.

## How To Use
### Packing a Resource:
![image](https://github.com/user-attachments/assets/4fbee40c-1119-4e43-bca9-eb9d047e3f3c)

*(Project -> Tools -> Pack Resource)*

<br>

![image](https://github.com/user-attachments/assets/e93c39be-e41b-415b-9a55-3447f79267f7)

The plugin will ask you which resource to pack, and will show you a tree featuring the found dependencies, from which you may uncheck the files you don't want to pack.

Upon confirmation, the plugin will then ask for the location where it should export the pack.
The export will be a `*.gdpck` file, which is the same as a `*.zip` file, but renamed to ease the search for files we would want to unpack.

### Unpacking a Resource:
![image](https://github.com/user-attachments/assets/459c6ab3-e537-4542-a5d4-3e0c85bc5d24)

*(Project -> Tools -> Unpack Resource)*

The plugin will ask you to select a `*.gdpck` file to unpack.
It will then show you a tree, similar to when packing. You may uncheck the files you don't want to unpack.
Unless the Force Overwrite on Load option is checked, the plugin will ask you if you want to replace each file that is already there.

## How To Install
Just like any other plugin, just download it and place its folder inside the addons folder of your Godot project, and then enable it in the project settings.
If your project doesn't have an addons folder, create one in `res://`.

***Notes:** This plugin was made for Godot 4.3, and remains untested on other versions of Godot. If the plugin ceases to function for whatever reason, just rename the `*.gdpck` files to `*.zip` and you will be able to manually extract their data.*
