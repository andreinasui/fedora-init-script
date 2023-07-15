#!/bin/bash
# shellcheck disable=2086

# =========== System (Fedora) initial configs ===========

dnf_install_options="--assumeyes --allowerasing"
system_version="$(rpm -E %fedora)"

invert_echo() {
	message=$1
	# Reset
	reset='\033[0m'

	# White Background
	BG='\033[47m'

	# Black Foreground
	FG='\033[0;30m'

	# Usage
	echo -e "$FG$BG $message $reset"
}

# 1. Change name
change_hostname() {
	(which hostnamectl >/dev/null 2>&1 && (echo "Setting hostname to $1" && hostnamectl set-hostname "$1" && echo "Hostname set to $1")) || echo "Failed setting hostname"
}

# 2. Configure DNF for Faster Downloads of Packages
config_dnf() {
	inputFile="/etc/dnf/dnf.conf"
	declare -A configurations=(["max_parallel_downloads"]=10 ["fastestmirror"]="True" ["deltarpm"]="True")

	for config in "${!configurations[@]}"; do
		if grep -q "$config" $inputFile; then
			sudo sed -i -e "/$config=/ s/=.*/=${configurations[$config]}/" $inputFile
		else
			echo "$config=${configurations[$config]}" | sudo tee -a $inputFile
		fi
	done
}

# 3. DNF Setup
dnf_setup() {
	# Update the system
	update_system() {
		invert_echo "Updating the system"
		sudo dnf update $dnf_install_options
	}

	# Enable RPM Fusion
	enable_rpm_fusion() {
		invert_echo "Enabling RPM fusion repositories"
		sudo dnf install $dnf_install_options https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-"$system_version".noarch.rpm \
			https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-"$system_version".noarch.rpm
	}

	dnf_plugins() {
		invert_echo "Adding DNF plugins"
		sudo dnf install $dnf_install_options dnf-plugins-core
	}

	update_system
	enable_rpm_fusion
	dnf_plugins
}

# 4. Install stuff
install_base_stuff() {
	pre_install() {
		invert_echo "Preinstall actions"
		# OpenRazer backend
		sudo dnf install $dnf_install_options kernel-devel # https://openrazer.github.io/#download
		sudo dnf config-manager --add-repo https://download.opensuse.org/repositories/hardware:razer/Fedora_"$system_version"/hardware:razer.repo
		sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
		sudo dnf copr $dnf_install_options enable tokariew/i3lock-color
	}

	install() {
		invert_echo "Install actions"
		build_essentials="cmake make automake gcc gcc-c++ kernel-devel curl \
      zlib-devel bzip2 bzip2-devel readline-devel sqlite sqlite-devel \
      openssl-devel tk-devel libffi-devel xz-devel libuuid-devel gdbm-devel \
      libnsl2-devel musl-libc autoconf automake cairo-devel fontconfig \
      libev-devel libjpeg-turbo-devel libXinerama libxkbcommon-devel \
      libxkbcommon-x11-devel libXrandr pam-devel pkgconf xcb-util-image-devel xcb-util-xrm-devel"
		media_list="vlc gstreamer1-plugins-bad-* gstreamer1-plugins-good-* \
      gstreamer1-plugins-base-* \
      gstreamer1-plugin-openh264 gstreamer1-libav \
      lame* gnome-tweaks gnome-extensions-app steam \
      openrazer-meta"
		tools_list="flatpak ripgrep fd-find tmux cargo wine lutris alacritty stow zsh neovim curl"
		docker_list="docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
		i3_list="i3 i3status i3lock-color feh dunst picom polybar rofi xrdb"
		exclude_list="gstreamer1-plugins-bad-free-devel lame-devel"
		exclude_i3_list="i3lock dmenu"

		sudo dnf install $dnf_install_options $build_essentials $media_list $tools_list $docker_list --exclude=$exclude_list
		sudo dnf install $dnf_install_options $i3_list --exclude=$exclude_i3_list

		# Specifically for polychromatic, see https://polychromatic.app/download/fedora
		sudo rpm -e gpg-pubkey-d6d11ce4-5418547d
		sudo dnf install $dnf_install_options --nogpgcheck polychromatic

		# Flatpak installs
		invert_echo "Installing flatpaks"
		flatpak_apps="com.discordapp.Discord com.getpostman.Postman com.github.tchx84.Flatseal com.spotify.Client"
		flatpak install --noninteractive $flatpak_apps

		# Install input-leap (barrier)
		sudo dnf install --releasever=39 $dnf_install_options input-leap
	}

	post_install() {
		invert_echo "Postinstall actions"

		# docker
		invert_echo "Installing docker"
		sudo groupadd -f docker
		sudo usermod -aG docker $USER
		sudo systemctl start docker
		sudo systemctl enable docker

		# Create mongodb container
		invert_echo "Creating mongodb container"
		sudo docker pull mongodb/mongodb-community-server
		sudo docker run --name mongo -d mongodb/mongodb-community-server:latest

		# mongocompass
		invert_echo "Installing mongocompass"
		mongocompass_url="https://downloads.mongodb.com/compass/mongodb-compass-1.38.2.x86_64.rpm"
		wget "$mongocompass_url" -P "$HOME/Downloads/"
		sudo dnf install $dnf_install_options "$HOME/Downloads/mongodb-compass-1.38.2.x86_64.rpm"

		# fonts
		invert_echo "Installing fonts"

		local nf_version="3.0.2"
		declare -A fonts=(["ibmplex"]="https://github.com/ryanoasis/nerd-fonts/releases/download/v$nf_version/ibmplexmono.tar.xz"
			["inconsolata"]="https://github.com/ryanoasis/nerd-fonts/releases/download/v$nf_version/Inconsolata.tar.xz"
			["meslo"]="https://github.com/ryanoasis/nerd-fonts/releases/download/v$nf_version/Meslo.tar.xz"
			["roboto"]="https://github.com/ryanoasis/nerd-fonts/releases/download/v$nf_version/RobotoMono.tar.xz"
			["source-code-pro"]="https://github.com/ryanoasis/nerd-fonts/releases/download/v$nf_version/SourceCodePro.tar.xz"
		)
		mkdir -pv "$HOME/.local/share/fonts"
		for font_key in "${!fonts[@]}"; do
			echo "DOWNLOADING font $font_key"
			wget -q -O "$font_key.tar.xz" "${fonts[$font_key]}"
			mkdir -pv "$HOME/.local/share/fonts/$font_key-nf-$nf_version"

			echo "EXTRACTING font $font_key to $HOME/.local/share/fonts/$font_key-nf-$nf_version"
			tar xf "$font_key.tar.xz" -C "$HOME/.local/share/fonts/$font_key-nf-$nf_version"

			echo "REMOVING local font $font_key"
			rm -v $font_key".tar.xz"
		done

		# fzf
		invert_echo "Installing fzf"
		git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
		~/.fzf/install --all --no-bash --no-fish --completion

		# spicetify
		invert_echo "Installing spicetify"
		curl -fsSL https://raw.githubusercontent.com/spicetify/spicetify-cli/master/install.sh | sh

		# neovim dependencies
		invert_echo "Installing neovim dependencies"
		cargo install rbw

		# betterlock
		# symlink i3lock-color to i3lock
		sudo ln -s "$(which i3lock)" /usr/bin/i3lock-color
		wget https://raw.githubusercontent.com/betterlockscreen/betterlockscreen/main/install.sh -O - -q | sudo bash -s system latest true

		# set zsh as default shell
		chsh -s "$(which zsh)"

		# pyenv
		invert_echo "Installing pyenv"
		curl https://pyenv.run | bash
		local python_version="3.11.4"
		invert_echo "Installing python $python_version"
		$HOME/.pyenv/bin/pyenv install $python_version
		$HOME/.pyenv/bin/pyenv global $python_version

		# nodenv
		invert_echo "Configuring nodenv"
		git clone https://github.com/nodenv/nodenv.git $HOME/.nodenv
		mkdir -p $HOME/.nodenv/plugins/
		git clone https://github.com/nodenv/node-build.git $HOME/.nodenv/plugins/node-build
		git clone https://github.com/nodenv/nodenv-aliases.git $HOME/.nodenv/plugins/nodenv-aliases
		git clone https://github.com/nodenv/nodenv-update.git $HOME/.nodenv/plugins/nodenv-update
		local node_version="18.16.0"
		invert_echo "Installing node $node_version"
		$HOME/.nodenv/bin/nodenv install $node_version
		$HOME/.nodenv/bin/nodenv global $node_version

		# Download dotfiles
		git clone https://github.com/andreinasui/dotfiles.git $HOME/.dotfiles
		rm -rf $HOME/.zshrc
		(cd $HOME/.dotfiles && stow .)

		# Create betterlockscreen cache
		betterlockscreen -u $HOME/Pictures/Wallpapers/ --fx blur

		# fix i3lock to be able to accept login password after screen lock
		echo "auth include system-auth" | sudo tee -a /etc/pam.d/i3lock

	}

	pre_install && install && post_install
}

initial_configurations() {
	set -e
	outsideStep=$1
	step=1
	invert_echo "$outsideStep Running initial system configuration..."
	newHostname="andrei-linux"
	invert_echo "Step $outsideStep.$step Changing hostname to $newHostname"
	change_hostname "$newHostname"
	((step++))
	invert_echo "Step $outsideStep.$step Configuring DNF..."
	config_dnf
	((step++))
	invert_echo "Step $outsideStep.$step Setting up DNF..."
	dnf_setup
	((step++))
	invert_echo "Step $outsideStep.$step Installing base packages"
	install_base_stuff
}

run_all() {
	set -e
	step=1
	initial_configurations "$step"
	invert_echo "It is recommended that you restart your system"
	invert_echo "NOTE: Manually configure the following tools:"
	echo "* Spicetify from the following link https://spicetify.app/docs/advanced-usage/installation#spotify-installed-from-flatpak"
	echo "* Betterlock from the following link https://github.com/betterlockscreen/betterlockscreen#installation"
	echo "* Input-leap"
	echo "* Pipewire sound"
	sudo dnf clean all
}

invert_echo "Installing first time config for Fedora $system_version"
run_all
