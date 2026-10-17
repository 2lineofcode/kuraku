`kuraku.exe` is the Windows x64 downloader, built from
https://github.com/2lineofcode/kuraku-downloader commit
`fa96b17979f81194b45612119d6dd922cddff5eb` (the same revision as Linux).

Rebuild from that checkout with Go 1.27.1 and Node.js/npm:

```sh
npm --prefix frontend ci
npm --prefix frontend run build
GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -tags production -trimpath -ldflags '-s -w' -o kuraku.exe .
```

Runtime: Chrome/Chromium for website extraction, FFmpeg for HLS and yt-dlp for
YouTube, available on PATH. WebView2 Runtime is needed for the downloader's
standalone GUI; KuraKu uses its CLI. The binary keeps its console subsystem
for stdin/stdout interaction with the app.

SHA-256: `0cac6813516eb0a274e58553ff5ddc7a005c83eacaaa43b4f47a234a93fe044c`.
