
##the following stuff has inconsistent parameter expansion ($ vs "${}")- just a warning that differences can't be assumed to be meaningful

function get_job_id_from_name () {
	#$1 expected to be job name
	echo $( squeue --me --name="$1" --Format="JobID" --noheader )
}
function time_left () {
	#$1 should be job id
	echo $( squeue --me -j"$1" --Format="TimeLeft" --noheader) #not having a space between j and the job id is actually correct. also, --me isn't strictly necessary but seemed to speed it up
}
function get_node () {
	#$1 should be job id
	echo $( squeue --me -j"$1" --Format="NodeList" --noheader)
}
function get_waiting_reason () {
	#$1 should be job id
	echo $( squeue --me -j"$1" --Format="Reason" --noheader )
}
function random_port () {
	#get a random port number between 30k and 60k
	#$RANDOM is distributed between 0 and 32767 (unsigned 15 bit value), so just use modulo on it to get it to 0-30k and add 30k.
	echo $(( 30000 + ( $RANDOM % 30000 ) )) #arithmetic expansion
}
function find_port () {
	#pass in port number as argument for $1
	echo $(netstat -an | grep $1) #should return an empty string if port not in use
}
function wait_file_exist () {
	#https://stackoverflow.com/a/40047847
	#pass in file name as argument for $1
	#it's a bit weird. i think the timeout is just there so that if it gets created between the test and the inotify, you don't get stuck
	while ! test -f "$1"; do
		echo "waiting... you can check status with 'squeue --me'" >&2 #squeue status/reason is: $(get_waiting_reason)" >&2 #ah, i didnt bring the job id into here, so i can't call it
		inotifywait --quiet --timeout 15 --event create /tmp >/dev/null || {
			(( $? == 2 )) && continue  ## inotify exit status 2 means timeout expired
			echo "unable to sleep with inotifywait; doing unconditional 10-second loop" >&2
			sleep 10
		}
	done
}
function finish_from_file_with_info () {
	#pass the file as $1. file assumed to already exist and have the info in the expected format
	#pass the node name as $2
	#pass 1 at $3 to override coloring

	yellow='\033[1;33m'
	non_color='\033[0m'

	info_file=$1
	jup_node=$2
	if [ -z "$3" ]; then #if expansion of $3 is a null string
		color=$yellow
	else
		color=$non_color
	fi

	line=$(grep http://localhost:.*/?token=.* $info_file | tail -1) || ( echo "something went wrong..." && return ) #grep: we take the last occurance bc it's nice and clean
	port=$(echo $line | grep -Eo "localhost:[0-9]*" | grep -Eo "[0-9]*")
	token=$(echo $line | grep -Eo "token=.*" | awk -F"=" '{ print $NF }') #awk bit: with = as delimiter, extract last field

	echo "On your local machine, you should now be able to run:"
	echo "**********"
	echo -e "$color ssh -t -L $port:localhost:$port $USER@sherlock.stanford.edu ssh -L $port:localhost:$port $jup_node $non_color"
	echo "~~~~~~~~~~"
	echo "Then in your local browser:"
	echo "**********"
	echo -e "$color http://localhost:$port/?token=$token $non_color"
}
function basicjup () {
        echo "starting"
	#args: directory and optionally a container
	#based off info from https://asconfluence.stanford.edu/confluence/display/REGLAB/Sherlock#Sherlock-JupyterNotebook

	#~~static params~~
	default_container=$GROUP_HOME/singularity/cafo.sif #iirc you can leave this blank to run without using a container (assuming you also didn't pass one in from the command line parameter, ofc)
	#~~other static parameters. if the log file isn't in the right location, it wont be able to detect the jupyter notebook. other than that, these are assumed to be constant across runs (nothing bad happens if not, you just might still have a jupyter running it doesnt detect)~~
        script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
	out_file=${script_dir}/basicjup.log
	job_name="basicjup"
	gpu="False" #can set to 0 with --no-gpu

	#~~read args~~ warning, I haven't tested all the code paths! (Less exciting nitpick: the pointing to help thing is basically duplicated)
        #another warning: it's just kludgey how arguments get read. If wanting to add another argument or etc, redo it.
	#~~read 1st arg or offer help~~
	if [ -z "$1" ]; then #if not providing any argument
		echo "Please provide a base dir for jupyter to start in. eg. it could just be \`basicjup .\`. You can also do \`basicjup --help\` for more help. "
		return
	fi
	if [[ $1 = "--help" || $1 = "-h" ]]; then #if asking for help
		echo "Format: basicjup dir [--gpu OR --no-gpu] [singularity container sif file]"
		echo "Examples:"
                echo "\t basicjup ."
                echo "\t basicjup ~ --nogpu"
                echo "basicjup . ~/my_container.sif --gpu"
		echo "Current defaults if not provided: default container is $default_container, gpu is set to $gpu"
                echo "You can change more settings such as the default time by editing the slurm request template in this file."
		return
	fi
	if [ ! -d "$1" ]; then #validate $1 is a directory
		echo "$1 doesn't seem to be a directory, exiting... try \`basicjup --help\` for help."
		return
	fi
	sbatch_chdir=$1
	#~~read 2nd and 3rd args~~
	for arg in $2 $3; do
		if [ $arg = "--no-gpu" ]; then gpu="False"; fi
		if [ $arg = "--gpu" ]; then gpu="True"; fi
	done
	container_arg=''
	for arg in $2 $3; do
		if [ -z "$arg" ] && [ ! $arg = "--no-gpu" ] && [ ! $arg = "--gpu" ]; then #if it exists and isn't the gpu arg
			container_arg=$arg
		fi
	done
	#~~set default container if non specified~~
	if [ -z "$container_arg" ]; then #if it's set
		container=$default_container
	else
		container=$container_arg
	fi
	#~~validate that it's a file~~
	if [ ! -f "$container" ]; then
		echo "$container isn't a file? Exiting... Try \'basicjup --help\' for help."
		return
	fi

	#~~check if there's already an instance running and provide access info if so~~
	job_id_if_exists=$(get_job_id_from_name "$job_name")
	if [ ! -z "$job_id_if_exists" ]; then #if there is a job id returned
		echo "A job with this name already exists!"
		job_id=$job_id_if_exists
		time_remaining=$( time_left $job_id ) #not having a space between j and the job id is actually correct
		echo "Time remaining (if job has started): $time_remaining"
		echo "Do you want to get the port/token for the existing one, or cancel it and request a new one?"
		select onetwo in "1" "2"; do
			case $onetwo in
				1 ) finish_from_file_with_info "${out_file}" $(get_node $job_id); echo "Hope that helped!"; return;; #exits
				2 ) scancel "${job_id}"; echo "Continuing..."; break;;
			esac
		done
	fi

	#~~pick a random port until you find one not in use~~
	port=$(random_port)
	while [[ $(find_port $port) ]]; do #while find_port outputs something (= port is in use) do
		port=$(random_port)
	done
	echo "port: $port"

	#~~cleanup out file now that we don't need it for that earlier case of an already-running job~~
	rm $out_file



	#~~heredoc sbatch~~ modeled after the sbatch file example on https://asconfluence.stanford.edu/confluence/display/REGLAB/Sherlock#Sherlock-JupyterNotebook
	#if you get an unexpected end of file error, make sure indentation in the heredoc is ONLY tabs and no spaces
	gres_line=''
	constraint_line=''
	if [ $gpu = "True" ]; then
		echo "requesting gpu"
		gres_line='SBATCH --gres=gpu:1'
		constraint_line='SBATCH --constraint=GPU_SKU:V100_SXM2'
	fi
	sbatch <<-EOF
	#!/bin/bash
	#SBATCH --job-name=$job_name
	#SBATCH --output=$out_file
	#SBATCH --chdir=$sbatch_chdir
	#
	#$gres_line
	#$constraint_line
	#
	#SBATCH --ntasks=1
	#SBATCH --time=6:00:00
	#SBATCH --mem=16GB
	#SBATCH --cpus-per-task=4
	#SBATCH --partition=deho

	singularity exec --nv $container jupyter-notebook --no-browser --port=$port
	EOF

	#~~wait for everything to fire up~~
	job_id=$(get_job_id_from_name "$job_name") #technically we could parse it from sbatch's output directly, but it's easier to look up
	echo "ran sbatch. job can be canceled with the command scancel $job_id."
	echo "waiting for job to start and the output file to be generated..."
	wait_file_exist $out_file
	echo "file exists, now waiting for jupyter to write port/token info string in it..."
	while ! grep -q http://localhost:.*/?token=.* $out_file; do
		echo "waiting..."
		sleep 10
	done

	#~~provide easy access~~
	finish_from_file_with_info $out_file $(get_node $job_id)
}
echo "$@"
basicjup "$@" #$@ passes all arguments
