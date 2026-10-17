`kuraku` is the Linux x64 downloader, built from
https://github.com/2lineofcode/kuraku-downloader commit
`fa96b17979f81194b45612119d6dd922cddff5eb` using `./build.sh` on Ubuntu 22.04.

Build requirements: Go 1.27.1, Node.js/npm, GTK3 and WebKitGTK 4.1 development libraries.
Runtime: GTK3, WebKitGTK 4.1; Chromium/Chrome for website extraction,
FFmpeg for HLS and yt-dlp for YouTube.

The macOS binary remains at `assets/kuraku`. Linux builds restore this binary's
executable permission during CMake installation.
