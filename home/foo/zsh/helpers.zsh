alias remove_image='metaflac --dont-use-padding --remove --block-type=PICTURE,PADDING *.flac'
alias manydex='python ~/Documents/scripts/manydex/main.py'

# function
# pick a dir from the pushd stack
function p() {
	local dir
	select dir in $dirstack; do
		echo $dir
		break
	done
	[[ ! -z "$dir" ]] && cd $dir
}

sshto() {
    ssh -o "HostName=$1" "${@:2}"
}

function print-color() {
	if (($# == 1)); then
		print -P '%F{$1}██████████████████%f'
	elif (($# == 2)); then
		print -P '%F{$1}$2%f' $1
	fi
}
function caps-led() {
	local caps_led=$(find /sys/class/leds/ -iname "*capslock")/brightness
	if [[ "$1" = "on" ]]; then
		echo 1 | sudo tee "${caps_led}" >/dev/null
	else
		echo 0 | sudo tee "${caps_led}" >/dev/null
	fi
}

function falac() {
	count=$(find . -mindepth 1 -type f -name "*.flac" | wc -l)
	if [ $count != 0 ]; then
		for i in *.flac; do
			echo $i
			ffmpeg -i "$i" -c:a alac -c:v copy "${i%.flac}".m4a && rm "$i"
		done
	else
		echo "${PWD}: No FLAC file found in directory, do nothing"
	fi
}

function falac-all() {
	for d in */; do
		pushd "$d"
		falac
		popd
	done
}

function flac-md5diff() {
	local dir1=$1
	local dir2=$2
	local dir1_md5s=$(mediainfo "$dir1"/*.flac | grep MD5)
	local dir2_md5s=$(mediainfo "$dir2"/*.flac | grep MD5)
	diff --color <(echo $dir1_md5s) <(echo $dir2_md5s)
}