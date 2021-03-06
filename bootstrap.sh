#!/bin/bash


# Get given parameters and set correct values
# $1 = location where dotfiles are stored (defaults to ~/dotfiles)
if [ -z "$1" ]; then
	dotfiles="${HOME}/.dotfiles"
else
	dotfiles="$1"
fi


# Set base path variables
WORK_DIR="/tmp/jean-imac-`date +%s`"
DOTFILES_DIR="$dotfiles"
BOOTSTRAP_DIR="$( cd "$( dirname "$0" )" && pwd )"
DROPBOX_DIR="$(bash ${BOOTSTRAP_DIR}/utilities/get_dropbox_folder.sh)"

# Source all functions used throughout this script
source "${BOOTSTRAP_DIR}/utilities/bootstrap_functions.sh"
source "${HOME}/.bash_profile"

# Ask for the administrator password upfront
sudo -v

# Keep-alive: update existing `sudo` time stamp until `.osx` has finished
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &


# Here we go!
echo -e "\033[1;32mInitializing Mac configuration...\033[0m"


# Create a tmp dir for all downloads/etc to go
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Check if Dropbox is installed
log "Checking for Dropbox"
if [ ! -d "${HOME}/Dropbox" ]; then
	cd $WORK_DIR
	curl -L -o Dropbox.dmg https://www.dropbox.com/download?plat=mac
	hdiutil mount Dropbox.dmg
	cp -R '/Volumes/Dropbox Installer/Dropbox.app' '/Applications/Dropbox.app'
	hdiutil unmount "/Volumes/Dropbox Installer"
	rm Dropbox.dmg
	open /Applications/Dropbox.app &
	check_for_dropbox

	$DROPBOX_DIR="$(bash ${BOOTSTRAP_DIR}/utilities/get_dropbox_folder.sh)"

	log "Dropbox installed, continuing..."
else
	log "Dropbox found, continuing..."
fi

# Check if Xcode/Git is installed
log "Checking for Git"
if [ ! $(which git 2>/dev/null) ]; then
	error "Git not found"
	check_for_xcode
	log "Git installed, continuing..."
else
	log "Git found, continuing..."
fi

# Install Homebrew and fix xcode locations
log "Checking for Homebrew"
if [ ! $(which brew 2>/dev/null) ]; then
	/usr/bin/ruby <(/usr/bin/curl -fsSk https://raw.github.com/mxcl/homebrew/go)
	echo "export PATH=/usr/local/bin:/usr/local/sbin:/usr/local/share/python:$PATH" >> "${HOME}/.bash_profile"
	source "${HOME}/.bash_profile"
	sudo xcode-select -switch /Applications/Xcode.app/Contents/Developer
	log "Homebrew installed, updating..."
else
	log "Homebrew found, checking..."
fi


# Make sure Homebrew works as expected
brew_doctor=$(brew doctor)
if [ "$?" -ne "0" ]; then
	log $brew_doctor
	pause "Homebrew returned an error. You can fix this problem now or deal with it later. Press [enter] to continue..."
else
	log $brew_doctor
fi

# Install rbenv
log "Checking for rbenv..."
if [ ! $(which rbenv 2>/dev/null) ]; then
	log "Rbenv not found, installing..."
	brew install rbenv &>/dev/null

	log "Adding rbenv path to .bash_profile"
	echo 'if which rbenv >/dev/null; then eval "$(rbenv init -)"; fi' >> "${HOME}/.bash_profile"
	source "${HOME}/.bash_profile"

	log "Rbenv installed, continuing..."
else
	log "Rbenv found, continuing..."
fi


# Install ruby-build
log "Checking for ruby-build..."
if [ ! $(which ruby-build 2>/dev/null) ]; then
	log "Ruby-build not found, installing..."
	brew install ruby-build &>/dev/null

	log "Ruby-build installed, continuing..."
else
	log "Ruby-build found, continuing..."
fi

# Print current installed ruby versions
log "Current installed Ruby versions:"
log "$(rbenv versions)"

# Install new Ruby version
ask "Do you want to install a new Ruby version? [yes/no]"
read confirm_install
ask_for_installation

# Warn on Ruby 1.8
if [ "$(ruby -v | grep '1.8' 2>/dev/null)" ]; then
	pause "Ruby 1.8 detected. If this is not the correct ruby version, please exit and type 'rbenv global <version>'. Press [enter] to continue..."
fi

# Install chef-solo for further system setup
if [ ! $(which chef-solo 2>/dev/null) ]; then
	log "Installing chef gem..."
	gem install chef --no-ri --no-rdoc >/dev/null || exit 1
	rbenv rehash
fi

# Symlink dotfiles directory
if [ ! -d "$DOTFILES_DIR" ]; then
	log "Creating symlink from $DOTFILES_DIR to ${HOME}/Dropbox/dotfiles"
	ln -s "${HOME}/Dropbox/dotfiles" "$DOTFILES_DIR"
else
	log "Existing dotfiles found, checking symlink target location..."
	if [ ! $(readlink "$DOTFILES_DIR" 2>/dev/null) ]; then
		log "$DOTFILES_DIR is not a symlink, backing up to ${DOTFILES_DIR}_bak"
		mv "$DOTFILES_DIR" "${DOTFILES_DIR}_bak"

		log "Creating symlink from $DOTFILES_DIR to ${HOME}/Dropbox/dotfiles"
		ln -s "${HOME}/Dropbox/dotfiles" "$DOTFILES_DIR"
	else
		if [[ $(readlink "$DOTFILES_DIR" 2>/dev/null) == "${HOME}/Dropbox/dotfiles" ]]; then
			log "Correct symlink already exists, no action taken"
		else
			log "Symlink exists but points to incorrect location ($(readlink \"$DOTFILES_DIR\"))."
			log "Backing up to ${DOTFILES_DIR}_bak"
			mv "$DOTFILES_DIR" "${DOTFILES_DIR}_bak"

			log "Creating symlink from $DOTFILES_DIR to ${HOME}/Dropbox/dotfiles"
			ln -s "${HOME}/Dropbox/dotfiles" "$DOTFILES_DIR"
		fi
	fi
fi
log "$DOTFILES_DIR symlink created, continuing..."


# Run chef-solo command
log "Starting chef-solo run..."
chef-solo -c "${DOTFILES_DIR}/chef/config/solo.rb"

if [ "$?" -ne "0" ]; then
  exit
fi

# # Symlink dotfiles in homedir
# cd  "${DOTFILES_DIR}/symlinks"
# source "${DOTFILES_DIR}/utilities/symlink_dotfiles.sh"
# log "All files in ${DOTFILES_DIR}/symlinks have been symlinked to ${HOME}"

# Install yadr
if [ ! -d "${HOME}/.yadr" ]; then
  brew install ack ctags git hub macvim fasd
  gem install ruby-debug-ide
  git clone https://github.com/JeanMertz/omz-to-prezto ~/.yadr
  cd ~/.yadr && rake install
fi

# Set git username and e-mail
if [ ! "$(git config --global user.name 2>/dev/null)" ]; then
	ask "Git Full name?"
	read git_username
	git config --global user.name "$git_username"

	ask "Git email?"
	read git_email
	git config --global user.email "$git_email"
fi


# Set up SHH for github access
if [ ! -f "${HOME}/.ssh/id_rsa.pub" ]; then
	log "Setting up SSH for Github access"

	ssh-keygen -t rsa -C "$git_email"

	log "This is your id_rsa.pub value:"
	cat "${HOME}/.ssh/id_rsa.pub"

	pause "Please add the above key to Github. Press [enter] to continue..."
fi


# Enable TRIM Support
log "Checking for TRIM Support..."
if [ "$(system_profiler SPSerialATADataType | grep 'TRIM Support: No' 2>/dev/null)" ]; then

	log "Trim support currently disabled."
	if [ -f /System/Library/Extensions/IOAHCIFamily.kext/Contents/PlugIns/IOAHCIBlockStorage.kext/Contents/MacOS/IOAHCIBlockStorage.original ]; then
		error "Old backup file found"
		log "  If you already activated TRIM support but haven't rebooted yet, then please do so now before running this command again."
		log "  Type \"no\" to skip this step and reboot first, or type \"yes\" if you understand the above and still want to reinstall TRIM support."
	fi
	ask "Do you want to enable TRIM support for OS X? [yes/no]"
	read confirm_trim
	activate_trim_support
else
	log "No SSD found or TRIM support already enabled, to disable perfom the following actions:"
	log "  sudo perl -pi -e 's|(\x52\x6F\x74\x61\x74\x69\x6F\x6E\x61\x6C\x00).{9}(\x00\x51)|$1\x41\x50\x50\x4C\x45\x20\x53\x53\x44$2|sg' /System/Library/Extensions/IOAHCIFamily.kext/Contents/PlugIns/IOAHCIBlockStorage.kext/Contents/MacOS/IOAHCIBlockStorage"
	log "  sudo kextcache -system-prelinked-kernel"
	log "  sudo kextcache -system-caches"
fi


# Add zsh as login shell
if [ -f "/usr/local/bin/zsh" ] && [ -z `grep ^/usr/local/bin/zsh$ /etc/shells` ]; then
	echo /usr/local/bin/zsh | sudo tee -a /etc/shells
fi

# Set zsh as default shell
if [ -f "/usr/local/bin/zsh" ] && [[ -z `dscl . -read ${HOME} UserShell | grep /usr/local/bin/zsh$` ]]; then
	chsh -s /usr/local/bin/zsh
fi

if [[ $confirm_trim == "yes" ]]; then
	log "You enabled TRIM support for OS X. To complete this you will need to reboot your Mac."
	log "You can rerun bootstrap.sh after the reboot to see if TRIM is properly enabled."
fi

# log "Loading sensible defaults (see ~/dotfiles/.osx)"
# source "${BOOTSTRAP_DIR}/.osx"

# Clean up temporary directory
rm -R $WORK_DIR

open "https://github.com/JeanMertz/dotfiles/wiki/Congratulations"
