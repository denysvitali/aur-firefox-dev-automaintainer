# aur-firefox-dev-automaintainer

This package keeps the AUR package [`firefox-dev`](https://aur.archlinux.org/packages/firefox-dev) updated to the latest Firefox Developer edition.  
It does so by checking the official Firefox update service, and it updates the AUR package repo accordingly when there is a new version.  
The script is run every hour on a VPS.

## Usage

Create a folder that acts as a repo (in my case its `~/ffdev-aur/`) and set `@@originalPKGBUILD` accordingly.  
Run the script with `crystal run src/automaintainer.cr`.  
For better performances, build it with `crystal build src/automaintainer.cr --release` and then run it via `./automaintainer`.


## Contributing

1. Fork it ( https://github.com/denysvitali/aur-firefox-dev-automaintainer/fork )
2. Create your feature branch (git checkout -b my-new-feature)
3. Commit your changes (git commit -am 'Add some feature')
4. Push to the branch (git push origin my-new-feature)
5. Create a new Pull Request

## Contributors

- [denysvitali](https://github.com/denysvitali) Denys Vitali - creator, maintainer
