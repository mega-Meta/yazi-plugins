# plugins for Yazi
yazi-plugins

## Yazi installation summary
>https://yazi-rs.github.io/docs/installation/
>
## macOS
### Homebrew
First, make sure that Homebrew is fully up-to-date with brew update.
Then you can install Yazi (and the optional dependencies):
```bash
brew install yazi ffmpeg-full sevenzip jq poppler fd ripgrep fzf zoxide resvg imagemagick-full font-symbols-only-nerd-font
brew link ffmpeg-full imagemagick-full -f --overwrite
```
If you prefer to use the most recent code, use the --HEAD flag when installing Yazi.
brew install yazi --HEAD


### MacPorts
```bash
sudo port install yazi ffmpeg 7zip jq poppler fd ripgrep fzf zoxide ImageMagick
```

### Debian and Ubuntu
We provide Debian and Ubuntu users with an official APT repository that offers the latest stable and nightly amd64 and arm64 binary builds.
** StableNightly **
```bash
curl -fsSL https://yazi-rs.github.io/builds/yazi-keyring.gpg | sudo tee /usr/share/keyrings/yazi-keyring.gpg >/dev/null
echo 'deb [signed-by=/usr/share/keyrings/yazi-keyring.gpg] https://yazi-rs.github.io/builds/ stable main' | sudo tee /etc/apt/sources.list.d/yazi.list >/dev/null
sudo apt update && sudo apt install yazi
```
