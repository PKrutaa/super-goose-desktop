Desktop Goose for Mac
Holy shoot, you actually opened the readme. Good for you!
New in version 0.22:
	•	Settings Window
	•	Custom Notes
	•	Bug Fixes
	•	Performance Improvements
	•	Runs on more macs (10.9 or newer)

Based on Desktop Goose v0.21 for Windows by @samnchiet.
Mac port by Jesús A. Álvarez.
Desktop Goose Homepage.
How to Use
	•	Double click the app to open
	•	Double click the app again to show the settings window
	•	From the settings window, you can:
	⁃	Change Settings
	⁃	Quit Desktop Goose
	⁃	Open Memes and Notes folders

Please message me your goose antics on Twitter @samnchiet, or any other means. I'd love to see it.

Support my work!

	•	twitter.com/samnchiet
	•	patreon.com/sammakesvr
	•	...just search "Sam Chiet" on YouTube.

Special thanks to all my patrons, who made this possible. You're heroes.
And huge shouts to the friendly people in my Discord/Twitter who helped test this and provided feedback!
And to the MOD COMMUNITY in the discord!

Some legal stuff

Honks sampled from Untitled Goose Game (go play it!)

SOFTWARE PROVIDED AS IS, WITHOUT WARRANTY you've seen all this before
in summary, I AM NOT LIABLE IF YOU DO SOMETHING LIKE USE THE GOOSE TO TRY AND FILE YOUR TAXES, OR IF THE GOOSE DAMAGES YOU SOMEHOW

THAT IS FULLY ON YOU.

Also, don't redistribute this software on your own! Link back to the itch page (on samperson.itch.io), or better yet, the YouTube video at https://www.youtube.com/watch?v=EQx6fyrZDWM)
If you got this from a source 

Technical Notes

Memes
Memes are stored in ~/Library/Containers/net.namedfork.DesktopGoose/Data/Library/Application Support/Desktop Goose/Memes/.
On the first run, it's populated with the built-in memes, but you can put more memes there (gif, png, jpg, etc).
Notes
Notes  are stored in ~/Library/Containers/net.namedfork.DesktopGoose/Data/Library/Application Support/Desktop Goose/Notes/.
On the first run, it's populated with the built-in notes, but you can put more notes here (as txt files).
Settings
To open the settings window, double click the app icon again once it's already running.
You can also change the settings with Terminal using the defaults command. These are the settings and their default values:
	•	CanAttackAtRandom: NO
	•	MinWanderingTimeSeconds: 20
	•	MaxWanderingTimeSeconds: 40
	•	FirstWanderTimeSeconds: 20
	•	FrameRate: 60
	•	SoundVolume: 1 – (use values between 0 and 1)
	•	UseCustomColors: NO
	•	GooseWhite: #ffffff
	•	GooseOrange: #ffa500
	•	GooseOutline: #d3d3d3
	•	GooseEye: #000000
	•	GooseMud: #8b4513

For example, to reduce the framerate to 30:
	defaults write net.namedfork.DesktopGoose FrameRate 30

To make the goose red:
	defaults write net.namedfork.DesktopGoose GooseWhite "#ff0000"
	defaults write net.namedfork.DesktopGoose UseCustomColors -bool YES

To make the goose quiet:
	defaults write net.namedfork.DesktopGoose SoundVolume 0

The change will be effective immediately, without having to restart Desktop Goose.
AppleScript
Desktop Goose for Mac is scriptable with AppleScript. Drag the app to Script Editor to see what's supported.
Some Examples of what you can do:
	•	tell app "Desktop Goose" to collect meme "Meme4.png"
	•	tell app "Desktop Goose" to collect meme "https://i.redd.it/4bamd6lnso241.jpg"
	•	tell app "Desktop Goose" to wander
	•	tell app "Desktop Goose" to nab mouse
	•	tell app "Desktop Goose" to collect note "Honk from AppleScript" title "HoNK"
 
Change Log
v0.22
	•	Fixed crash that caused goose to go offscreen and never return
	•	Fixed font and color of notes
	•	If you minimize a window in transit, it now stays minimized
	•	When a new window is received, it no longer activates all the windows
	•	Adjusted goose speed to match frame rate
	•	Reduced CPU usage
	•	Added Notes folder to customize
	•	Supports macOS 10.9 or newer
	•	Settings to customize colors
	•	Setting for sound volume
	•	Added settings window (double click app again to show it)

v0.21
	•	First release
