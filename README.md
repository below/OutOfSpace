# Out Of Space
## A Lego Dimensions Project for macOS

Now that Lego Dimensions seems to be reaching end-of-life as of early 2026, I got my hands on a used toy pad. This is my first attempt in talking to it.
So I wrote a macOS app for it.

## Features
- Control Zone LEDs
- Detect NFC Tags in Zones

## What is not working
- Read the real ID of the tags

> [!TIP]
> The IDs in `TagRegistryStore` are the individual NFC IDs of my tags. As long as I can not read the real IDs, you will have to adjust this file for your own tags

## TBD
- Outfactor the ToypadService to a library
- Read the real ID of the tag

## Links

https://www.proxmark.io/www.proxmark.org/forum/viewtopic.php%3Fpid=20257.html
https://github.com/dolmen-go/legodim/blob/f1c5b25864649ec34fb060457fa32d7832f01b1e/tag/uid.go#L43
https://www.nxp.com/docs/en/data-sheet/NTAG213_215_216.pdf
https://retrodeck.readthedocs.io/en/latest/wiki_controllers/toystolife/lego-toypad/

