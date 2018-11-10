
This fork of www.dirkwhoffmann.de/virtualC64 provides alternate video controls which I hope can better emulate CRT monitors:

![video controls](video_controls.png)

The first significant difference is in the scanlines. VirtualC64 3.1.1 scanlines are rendered thicker on a higher resolution texture. This makes them less obvious but makes the image more luminous:
![video controls](ss1.png)

The scanlines are aligned to the monitor output rather than the emulator texture, which makes them very sharp. The misalignment with the emulator texture is noticeable (to me at least) near pixel edges where there are color changes.

This fork doubles the emulator texture size and alternates the attenuation of horizontal lines, which fixes the alignment problem:
![video controls](ss2.png)

The attenuation between scanlines is adjustable. The scanlines are blurable as well.

The next significant difference is the blooming, which is a glowing effect around brighter areas. There are three adjustments:
 * Bloom radius: controls how far the effect spans 
 * Bloom factor: attenuates blooming for less bright parts of the image
 * Bloom brightness: scales the effect when compositing onto the final image

For example, here is the Ultima III intro screen with no bloom:
![video controls](ss3.png)

And with bloom:
![video controls](ss4.png)



VirtualC64 is open source and released under the GNU General Public License.
