#!/bin/bash
################################################################################
#   shalarm.sh      |   version 1.7     |   FreeBSD License   |   2018.09.14
#   James Hendrie   |   hendrie.james@gmail.com
################################################################################

##  Script version
VERSION="1.7"

##  Set these to whatever works for you; alternately, don't touch them and just
##  make sure that 'findMediaPlayer' and 'findSoundFile' are both set to 1
soundFile="ring.wav"                    #   Sound file used as your alarm tone
mediaPlayer=""                          #   Default media player to play sound
mediaPlayerOptions=""                   #   Options passed to the media player
defaultPrefix="/usr"                    #   Default prefix
debugMode=0                             #   If 1, print a few variables and exit


##  Variables used later in the script
findMediaPlayer=1               #   If 1, search for media players to use
mediaPlayerPID=0                #   PID of media player program
ringTheAlarm=0                  #   If 1, ring the alarm (it's set to 1 later)
testAlarm=0                     #   If 1, set the alarm to current time +5 secs
checkInterval='.5'              #   Interval to check alarm, in seconds
alarmTimeout=0                  #   Time in seconds (0 or less means no timeout)
snooze=0                        #   If 0, disabled; else, snooze for N seconds
snoozing=0                      #   Currently snoozing
useConfig=1                     #   Whether or not to use a config file
createUserConfig=1              #   Whether or not to copy the config file to
                                #   ~/.config/shalarm/shalarm.cfg if that file
                                #   doesn't already exist
##  Just for funsies
printAlarmMessage=1             #   Print a message when the alarm is ringing
alarmMessage="WAKE UP!"         #   The message to print
messageRepeat=0                 #   If 0, do not repeat.  If 1, do repeat.


##  We trap SIGINT (ctrl-c) and execute 'control_c' function if it's issued
trap control_c SIGINT



##  This function tests the currently selected media player, if any
function test_media_player
{
    ##  First, just check if whatever they've supplied works
    if [[ -x "$mediaPlayer" ]]; then
        return 0
    fi

    ## If they've set something but it ain't executing
    if [[ ! -z $mediaPlayer ]]; then
        if [[ -x "$(which ${mediaPlayer})" ]]; then

            ##  Yay we found it
            mediaPlayer="$(which ${mediaPlayer})"
            return 0
        else

            ##  No luck
            echo "Cannot find media player $mediaPlayer"
            bummerMan=1
            return 1
        fi
    else
        return 1
    fi
}

##  This function goes through an array of commonly installed media players, and
##  if it finds one, sets that as the media player to use.  If it can't find
##  any, then it errors out.
function find_media_player
{
    ##  An array of commonly installed media players
    commonMediaPlayers=('mplayer' 'mpv' 'mplayer2' 'play' 'aplay' 'cvlc')

        ##  Check each media player until we find one
        for cmp in ${commonMediaPlayers[@]}; do

            ##  We'll just do this here for convenience
            player="$(which ${cmp})"

            ##  Test it
            if [[ -x "$player" ]]; then

                ##  Let the user know their weird, off-brand media player
                ##  doesn't work
                if [[ ! -z $bummerMan ]]; then
                    echo "using $player instead"
                    unset bummerMan
                fi

                ##  Set it to God's Own media player, whatever it is
                mediaPlayer="$player"

                ##  Return out of the loop
                return 0;
            fi
        done

    ##  If we don't find one, tell the user and exit the program
    echo "Error:  Can't find a media player to use" 1>&2
    echo "Try installing 'play', 'aplay' or 'mplayer'" 1>&2
    exit 1
}


##  This function checks two directories for the file 'ring.wav':  The current
##  directory, and /usr/local/share/shalarm.  If it finds it in either, it sets
##  the soundfile to that.  Otherwise, it errors out.
function find_sound_file
{
    soundFile=0

    ##  Look in the default install directory for ring.wav.  Failing that,
    ##  check the present working directory using 'ls'
    if [ ! -e "$defaultPrefix/share/shalarm/ring.wav" ]; then
        for f in $( ls ); do
            if [ $f == "ring.wav" ]; then
                soundFile=$(readlink -f $f)
            fi
        done
    else
        soundFile="$defaultPrefix/share/shalarm/ring.wav"
    fi

    ##  If we can't find a sound file, tell the user and exit the program
    if [ $soundFile == 0 ]; then
        echo "Error:  Cannot find file 'ring.wav'" 1>&2
        exit
    fi
}


##  This function tells the script what to do if it catches a SIGINT
function control_c
{
    ##  If snoozing isn't enabled, just quit
    if [[ ! $snooze -gt 0 ]]; then
        echo -e "\nExiting\n"
        exit 0

    ##  If it is, and the alarm isn't ringing, quit.  If the alarm IS
    ##  ringing, then snooze.
    else
        if [[ $ringTheAlarm -eq 1 ]]; then
            echo -e "\nSnoozing for $snooze seconds\n"
            start_snoozing
        else
            echo -e "\nExiting\n"
            exit 0
        fi

    fi
}


##  This function gets the current time using 'date', and cuts it into the
##  proper variables
function get_current_time
{
    ##  Get the current time
    currentTimeUnix=$(date +%s)
    currentTime=$(date -d "@$currentTimeUnix" +'%H:%M:%S')
}


##  Generic function to print an "I don't understand that time string" message
function print_time_error
{
    echo "Error:  Improper time format" 1>&2
    echo "Use 'shalarm --help' for more info" 1>&2
}


##  We set the alarm time, and also check to make sure that the time string was
##  of the proper length.  After that, we double-check the other alarm time
##  variables to ensure that those, too, are of proper length
function set_alarm_time
{
    get_current_time

    if alarmTimeUnix=$(date -d "$1" +%s); then

        # Try to add 1 day if alarm time is too early
        if [[ "$alarmTimeUnix" -lt "$currentTimeUnix" ]]; then
            (( alarmTimeUnix += 24 * 60 * 60 ))
        fi

        if [[ "$alarmTimeUnix" -lt "$currentTimeUnix" ]]; then
            echo "Error:  Alarm is set to: $(date -d "$1")" 1>&2
            echo " ...... Which is earlier than now: $(date)" 1>&2
            exit
        fi

        alarmTime=$(date -d "@$alarmTimeUnix" +'%H:%M:%S')
    else
        print_time_error
        exit
    fi
}


##  This function just sets the alarm to five seconds past whatever the current
##  system time (as taken from 'date') is
function set_test_alarm
{
    ##  Get the current time
    get_current_time

    ##  Set the alarm time to five seconds past whatever the current time is
    set_alarm_time "+5 sec"

}



##  This function resets the alarm to $snooze seconds ahead of whatever
##  the current time is (when it's activated)
function add_snooze_interval
{
    get_current_time

    set_alarm_time "+$snooze sec"

}


##  This function uses the system call to 'ring the alarm' -- in other words,
##  use the media player to play the sound file over and over
function ring_alarm
{
    if [[ $mediaPlayerPID -eq 0 ]] || [[ ! -e "/proc/$mediaPlayerPID" ]]; then

        ##  Set it so that we're not currently snoozing
        let snoozing=0

        ##  If we're printing a message, then... print it
        if [ $printAlarmMessage == 1 ]; then
            ##  If alarm message is set to fortune, print a short fortune
            if [ "${alarmMessage^^}" == "FORTUNE" ]; then
                if [ $messageRepeat == 1 ]; then
                    echo -e "$(fortune -s)\n"
                else
                    if [ $messageRepeat == 0 ]; then
                        echo -e "$(fortune -s)\n"
                        messageRepeat=2
                    fi
                fi
            else
                if [ $messageRepeat == 1 ]; then
                    echo -e "$alarmMessage"
                else
                    if [ $messageRepeat == 0 ]; then
                        echo -e "$alarmMessage"
                        messageRepeat=2
                    fi
                fi
            fi
        fi

        ##  Issue the system call, sending all output to /dev/null to keep
        ##  things nice and clean.
        if [[ "$mediaPlayerOptions" = "" ]]; then
            exec "$mediaPlayer" "$soundFile" &> /dev/null &
        else
            exec "$mediaPlayer" "$mediaPlayerOptions" "$soundFile" &>/dev/null &
        fi

        ##  Grab the PID so that we can kill it later if we need to
        mediaPlayerPID=$!
    fi
}


function start_snoozing
{
    ##  Set this variable because we needs it man, we needs it
    let snoozing=1

    ##  Halt the alarm ringing
    ringTheAlarm=0

    ##  Kill the media player if it's running
    if [[ -e "/proc/$mediaPlayerPID" ]]; then
        kill $mediaPlayerPID
    fi

    ##  Add the snooze interval
    add_snooze_interval
}


##  Every second, we check to see if the alarm time is equal to the current time
##  and if it is, we ring the alarm
function alarm_check
{
    ##  Fetch the current system time
    get_current_time

    ##  If the current time is equal to the alarm time, set the alarm to ring
    if [ "$alarmTimeUnix" -eq "$currentTimeUnix" ]; then
        ringTheAlarm=1
    fi

    ##  If the ringTheAlarm variable is set to 1, ring the alarm
    if [ $ringTheAlarm == 1 ]; then
        ring_alarm
    fi
}


##  Function to print the usage information
function print_usage
{
    echo -e "Usage:  shalarm [OPTION] TIME\n"
}


##  Function to print the help information
function print_help
{
    echo -e "Usage:  shalarm TIME\n"
    echo -e "TIME is a time string, parsed by \`date -d\`."
    echo -e "For example, ten PM may be formatted as follows:\n"
    echo -e "   22:00:00"
    echo -e "   22:00"
    echo -e "   22"
    echo -e "   2200\n"
    echo -e "As an aside, formatting it as '10:00' will get you ten AM, and"
    echo -e "'10 pm' won't work.\n"
    echo -e "Arguments:"
    echo "  -h or --help:       Print this help screen"
    echo "  -v or --version:    Print version and author info"
    echo "  -t or --test:       Test alarm set to 5 seconds in the future"
    echo "  -d or --debug:      Check out what's going wrong (or right)"
    echo "  --snooze N:         Enable snooze, set interval to N seconds"
    echo "  --timeout N:        Enable timeout, set limit to N seconds"
}

##  Function to print program and author information
function print_version
{
    echo -e "shalarm version ${VERSION}, written by James Hendrie,"
    echo -e "with contributions from Ilya Pikulin and stormdragon2976."
    echo -e "Licensed under the FreeBSD License"
}


##  This is just a function to print out some stuff that might be of interest
##  to people having trouble getting this to work.
function print_debug_info
{

    ##  Echo the values of a few key variables, formatted in a fancy way because
    ##  I am an asshole who does that kind of thing
    echo -e "\n\n###############################################"
    echo -e "                DEBUG INFO                     "
    echo -e "###############################################"
    echo -e "\nMedia player:\t\t\t$mediaPlayer"
    echo -e "Sound file:\t\t\t$soundFile"
    if [[ $printAlarmMessage -eq 1 ]]; then
        echo -e "PrintAlarmMessage:\t\tYes"
    else
        echo -e "PrintAlarmMessage:\t\tNo"
    fi
    echo -e "Message:\t\t\t$alarmMessage"

    ##  Check for the existence of /etc/shalarm.cfg and report
    echo -n "/etc/shalarm.cfg:  "
    if [ -e "/etc/shalarm.cfg" ]; then
        echo -e "\t\tDOES exist"
    else
        echo -e "\t\tDOES NOT exist"
    fi

    ##  Check for the existence of ~/.config/shalarm/shalarm.cfg and report
    echo -n "~/.config/shalarm/shalarm.cfg:"
    if [ -e "$(readlink -f ~/.config/shalarm/shalarm.cfg)" ]; then
        echo -e "\tDOES exist"
    else
        echo -e "\tDOES NOT exist"
    fi

    ##  Snooze info
    if [[ $snooze -eq 0 ]]; then
        echo -e "Snooze enabled:\t\t\tNo"
    else
        echo -e "Snooze enabled:\t\t\tYes"
        echo -e "Snooze interval:\t\t$snooze seconds"
    fi

    ##  Alarm timeout info
    if [[ $alarmTimeout -gt 0 ]]; then
        echo -e "Alarm timeout:\t\t\t$alarmTimeout seconds"
    else
        echo -e "Alarm timeout:\t\t\tNo"
    fi

    ##  Just to create some space at the bottom of the screen
    echo -e ""  ##  Yeah, enjoy that superflous -e you sons of bitches

}


##  This function will copy the config file from /etc to ~/.config/shalarm
function copy_user_config
{
    ##  Check to make sure the default config exists
    if [ ! -e "/etc/shalarm.cfg" ]; then
        echo "Error:  File does not exist (/etc/shalarm.cfg)" 1>&2
        echo "        Cannot copy it to ~/.config/shalarm/shalarm.cfg" 1>&2
    ##  And that it can be read from
    elif [ ! -r "/etc/shalarm.cfg" ]; then
        echo "Error:  Cannot read from /etc/shalarm.cfg" 1>&2
    ##  If it passes both tests, we begin the copying process
    else
        ##  Check to make sure we can write to the ~/.config directory
        if [ ! -w "$(readlink -f ~/.config)" ]; then
            echo "Error:  Cannot write to ~/.config/shalarm/shalarm.cfg" 1>&2
        else
            ##  Make the directory if need be
            if [ ! -e "$(readlink -f ~/.config/shalarm)" ]; then
                mkdir -p "$(readlink -f ~/.config/shalarm)"
            fi
            ##  Finally, copy the file to the user's ~/.config/shalarm directory
            cp "/etc/shalarm.cfg" "$(readlink -f ~/.config/shalarm/shalarm.cfg)"
        fi
    fi
}


##  This function sets the options according to the config file that's read
function set_options
{
    ##  We see if we're creating a user config, assuming it doesn't exist
    if [ $createUserConfig == 1 ]; then
        if [[ ! -e "$HOME/.config/shalarm/shalarm.cfg" ]]; then
            copy_user_config
        fi
    fi

    ##  Copy the values in the original variables, since we may revert back
    oldMediaPlayer=$mediaPlayer
    oldMediaPlayerOptions=$mediaPlayerOptions
    oldAlarmMessage=$alarmMessage
    oldPrintAlarmMessage=$printAlarmMessage
    oldSnooze=$snooze
    oldAlarmTimeout=$alarmTimeout

    ##  If we can read from the user's config, then use that
    if [[ -r "$HOME/.config/shalarm/shalarm.cfg" ]]; then
        source "$HOME/.config/shalarm/shalarm.cfg"

    ##  Otherwise, use the default config
    elif [ -r "/etc/shalarm.cfg" ]; then
        source "/etc/shalarm.cfg"
    fi

    ##  And now, we check a bunch of values to make sure they aren't set to
    ##  'DEFAULT'.  If they are, we restore them to their previous values

    ##  Media player we're using
    if [ "$mediaPlayer" == "DEFAULT" ]; then
        mediaPlayer=$oldMediaPlayer
    fi

    ##  Media player options
    if [ "$mediaPlayerOptions" == "DEFAULT" ]; then
        mediaPlayerOptions=$oldMediaPlayerOptions
    fi

    ##  Sound file to play
    if [ "$soundFile" == "DEFAULT" ]; then
        find_sound_file
    fi

    ##  Do we want to print an alarm message?
    if [ "$printAlarmMessage" == "DEFAULT" ]; then
        printAlarmMessage=$oldPrintAlarmMessage
    fi

    ##  Which alarm message to print?
    if [ "$alarmMessage" == "DEFAULT" ]; then
        alarmMessage=$oldAlarmMessage
    fi

    ##  Is snooze enabled?
    if [[ "$snooze" = "DEFAULT" ]]; then
        let snooze=0
    fi

    ##  How long will the alarm ring before the script just kills itself
    ##  0 or less means never, more than 0 means N seconds
    if [[ "$alarmTimeout" = "DEFAULT" ]]; then
        let snoozeTimeout=0
    fi

}


function timeout_check
{
    ##  Get the current time
    get_current_time

    ##  Check for timeout
    if [[ $(( currentTimeUnix - alarmTimeUnix )) -gt $alarmTimeout ]]; then
        kill $mediaPlayerPID
        echo "Alarm timeout reached ($alarmTimeout seconds)"
        echo "Exiting"
        exit 0
    fi

}


################################################################################

##  Check the number of args
if [[ $# -lt 1 ]]; then
    print_usage
    echo -e "\nUse 'shalarm --help' for more info" 1>&2

    exit 1
fi


##  Process the arguments
OPTS=$(getopt -n "$0" -o hvtd -l "help,version,test,debug,snooze:,timeout:" -- "$@")

if [[ $? -ne 0 ]]; then
    echo "ERROR:  Could not process arguments" 1>&2
    exit 1
fi

eval set -- "$OPTS"


while true; do

    case "$1" in
        -h|--help)
            print_help
            exit 0
            shift;;

        -v|--version)
            print_version
            exit 0
            shift;;

        -t|--test)
            let testAlarm=1
            shift;;

        -d|--debug)
            let debugMode=1
            shift;;

        -s|--snooze)
            if [[ $2 = *[[:digit:]]* ]]; then
                forceSnooze=$2
            fi
            shift 2;;

        -t|--timeout)
            if [[ $2 = *[[:digit:]]* ]]; then
                forceAlarmTimeout=$2
            fi
            shift 2;;

        --)
            shift
            break;;
    esac
done



##  If we're looking for a config file, set options according to that
if [ $useConfig == 1 ]; then
    set_options
fi


##  If appropriate, find the media player
if [ $findMediaPlayer == 1 ]; then

    ##  Test to see if their media player works
    test_media_player

    if [[ $? -eq 1 ]]; then
        find_media_player
    fi
fi


##  Here we test to see if the user passed snooze/timeout values through the
##  command line; if so, those take precedence over defaults / config settings
if [[ ! -z $forceSnooze ]]; then
    let snooze=$forceSnooze
fi

if [[ ! -z $forceAlarmTimeout ]]; then
    let alarmTimeout=$forceAlarmTimeout
fi




##  If this is a test, use the test function.  Otherwise, operate as normal.
if [ $testAlarm == 1 ]; then
    set_test_alarm
else
    if [ $debugMode == 1 ]; then
        print_debug_info
        exit
    else
        set_alarm_time "$1"
    fi
fi


########################################        MAIN LOOP

##  We double-check to make sure that $mediaPlayer and $soundFile exist
if [ ! -r "$soundFile" ]; then

    ##  Now we try to find the default
    echo -n "Error:  Can't read from '$soundFile'" 1>&2
    find_sound_file

    ##  If we can't, bail out
    if [[ ! -r "$soundFile" ]]; then
        echo -e "\nError:  Cannot read from file '$soundFile', aborting." 1>&2
        exit 1
    fi

    echo ", using default." 1>&2
fi


if [ ! -e "$mediaPlayer" ]; then
    echo "Error:  Cannot find media player $mediaPlayer" 1>&2
    exit
elif [ ! -x "$mediaPlayer" ]; then
    echo "Error:  Lack execution permission for media player $mediaPlayer" 1>&2
    exit
fi


##  Tell the user what's up
if [ $testAlarm == 1 ]; then
    echo -e "\nTest alarm is ACTIVE ($(date -d "@$alarmTimeUnix"))"
else
    echo -e "\nAlarm is ACTIVE and set to $(date -d "@$alarmTimeUnix")"
fi

##  Print how much time is left until the alarm
get_current_time
leastSecond=$(( alarmTimeUnix - currentTimeUnix ))
leastHour=$(( $leastSecond / (60 * 60) ))
leastSecond=$(( $leastSecond - $leastHour * (60 * 60) ))
leastMinute=$(( $leastSecond / 60 ))
leastSecond=$(( $leastSecond - $leastMinute * 60 ))

if [[ "$leastHour" != "0" ]]; then
    leastHour="${leastHour}h "
else
    leastHour=""
fi
if [[ "$leastMinute" != "0" || "$leastHour" != "" ]]; then
    leastMinute="${leastMinute}m "
else
    leastMinute=""
fi
leastSecond="${leastSecond}s "

echo -e "   ${leastHour}${leastMinute}${leastSecond}left to sleep\n"
unset leastHour leastSecond leastMinute
#  ------------------------------------

if [[ $alarmTimeout -gt 0 ]]; then
    echo "(Alarm timeout:  $alarmTimeout seconds)"
fi

echo -e "   Use CTRL-C to quit\n"

if [[ $snooze -gt 0 ]]; then
    echo "Snooze is enabled:  If alarm is ringing,"
    echo -e "CTRL-C once to snooze, twice to quit\n"
fi



##  Do an alarm check every $checkInterval seconds (1 by default)
while true; do
    ##  Do the alarm check, daddy-o
    alarm_check

    ##  Check for alarm timeout
    if [[ $alarmTimeout -gt 0 ]]; then
        timeout_check
    fi

    ##  Sleep for $checkInterval seconds
    sleep $checkInterval
done
