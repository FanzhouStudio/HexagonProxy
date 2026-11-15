# Antigravity-Proxy v2.4, IDE x64

Source: https://github.com/yuaotian/antigravity-proxy/tree/v2.4

Release: https://github.com/yuaotian/antigravity-proxy/releases/tag/v2.4

Archive: https://github.com/yuaotian/antigravity-proxy/releases/download/v2.4/antigravity-proxy-v2.4-ide-win-x64.zip

The archive digest was checked against the GitHub Releases API asset digest before extraction:

| File | SHA-256 |
| --- | --- |
| Upstream ZIP | `ee4aead95b677148c6ac4d8e46018b3b07e2b1e4249bb5232985628ee78d82e3` |
| `ide/version.dll` | `40f037232a180da8dff7611021270549fcc4e208580d8bf0f70bc9975f871b5f` |
| `ide/config.json` (saved as `config.template.json`) | `da22147e740b40f155553142da7ff90ba0383421beff8d6cdfd3019c791eeced` |

The DLL and template are unmodified. `LICENSE.txt` and `AUTHORS.txt` are retained from tag v2.4. The Windows helper validates both payload hashes before deployment, sets the SOCKS5 endpoint to the local HexagonProxy mixed port, and disables upstream updates and download mirrors.

No source or binary from Antigravity-Manager is included. Its account list and explicit account selection were referenced as product patterns only.
