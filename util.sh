#!/bin/bash
#********************************************************************
# Software License Agreement (BSD License)
#
#  Copyright (c) 2016, University of Colorado, Boulder
#  All rights reserved.
#
#  Redistribution and use in source and binary forms, with or without
#  modification, are permitted provided that the following conditions
#  are met:
#
#   * Redistributions of source code must retain the above copyright
#     notice, this list of conditions and the following disclaimer.
#   * Redistributions in binary form must reproduce the above
#     copyright notice, this list of conditions and the following
#     disclaimer in the documentation and/or other materials provided
#     with the distribution.
#   * Neither the name of the Univ of CO, Boulder nor the names of its
#     contributors may be used to endorse or promote products derived
#     from this software without specific prior written permission.
#
#  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
#  "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
#  LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
#  FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
#  COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
#  INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
#  BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
#  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
#  CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
#  LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
#  ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
#  POSSIBILITY OF SUCH DAMAGE.
#********************************************************************/

# Author: Dave Coleman <dave@dav.ee>, Robert Haschke
# Desc: Utility functions used to make CI work better in Travis

#######################################
export TRAVIS_FOLD_COUNTER=0
TRAVIS_GLOBAL_TIMEOUT=${TRAVIS_GLOBAL_TIMEOUT:-49}  # 50min minus slack
TRAVIS_GLOBAL_START_TIME=${TRAVIS_GLOBAL_START_TIME:-$(date +%s)}


#######################################
# Start a Travis fold with timer
#
# Arguments:
#   travis_fold_name: name of line
#   command: action to run
#######################################
function travis_time_start {
    TRAVIS_START_TIME=$(date +%s%N)
    TRAVIS_TIME_ID=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 8 | head -n 1)
    TRAVIS_FOLD_NAME=$1
    local COMMAND=${@:2} # all arguments except the first

    # Start fold
    echo -e "\e[0Ktravis_fold:start:$TRAVIS_FOLD_NAME"
    # Output command being executed
    echo -e "\e[0Ktravis_time:start:$TRAVIS_TIME_ID\e[34m$COMMAND\e[0m"
}

#######################################
# Wraps up the timer section on Travis CI (that's started mostly by travis_time_start function).
#
# Arguments:
#   travis_fold_name: name of line
#######################################
function travis_time_end {
    if [ -z $TRAVIS_START_TIME ]; then
        echo '[travis_time_end] var TRAVIS_START_TIME is not set. You need to call `travis_time_start` in advance.';
        return;
    fi
    local TRAVIS_END_TIME=$(date +%s%N)

    # Output Time
    echo -e "travis_time:end:$TRAVIS_TIME_ID:start=$TRAVIS_START_TIME,finish=$TRAVIS_END_TIME,duration=$(($TRAVIS_END_TIME - $TRAVIS_START_TIME))\e[0K"
    # End fold
    echo -e -n "travis_fold:end:$TRAVIS_FOLD_NAME\e[0m"

    unset TRAVIS_START_TIME
    unset TRAVIS_TIME_ID
    unset TRAVIS_FOLD_NAME
}

#######################################
# Display command in Travis console and fold output in dropdown section
#
# Arguments: commands to run
# Return: exit status of the command
#######################################
function travis_run_impl() {
  local commands=$@

  let "TRAVIS_FOLD_COUNTER += 1"
  travis_time_start moveit_ci.$TRAVIS_FOLD_COUNTER $commands
  # actually run commands, eval needed to handle multiple commands!
  eval $commands
  result=$?
  travis_time_end
  return $result
}

#######################################
# Run passed commands and exit if the last one fails
function travis_run() {
  travis_run_impl $@ || exit $?
}

#######################################
# Same as travis_run but ignore any error
function travis_run_true() {
  travis_run_impl $@ || true
}

#######################################
# Same as travis_run, but issue some output regularly to indicate that the process is still alive
# from: https://github.com/travis-ci/travis-build/blob/d63c9e95d6a2dc51ef44d2a1d96d4d15f8640f22/lib/travis/build/script/templates/header.sh
function travis_run_wait() {
  local timeout=$1 # in minutes

  if [[ $timeout =~ ^[0-9]+$ ]]; then
    # looks like an integer, so we assume it's a timeout
    shift
  else
    # default value
    timeout=20
  fi
  # limit to remaining time
  local remaining=$(( $TRAVIS_GLOBAL_TIMEOUT - ($(date +%s) - $TRAVIS_GLOBAL_START_TIME) / 60 ))
  if [ $remaining -le $timeout ] ; then timeout=$remaining; fi

  local commands=$@
  let "TRAVIS_FOLD_COUNTER += 1"
  travis_time_start moveit_ci.$TRAVIS_FOLD_COUNTER $commands

  # Disable bash's job control messages
  set +m
  # actually run commands, eval needed to handle multiple commands!
  eval $commands &
  local cmd_pid=$!

  # Start jigger process, taking care of the timeout and '.' outputs
  travis_jigger $cmd_pid $timeout $commands &
  local jigger_pid=$!

  # Wait for main command to finish
  wait $cmd_pid 2>/dev/null
  local result=$?
  # If main process finished before jigger, stop the jigger too
  # https://stackoverflow.com/questions/81520/how-to-suppress-terminated-message-after-killing-in-bash
  kill $jigger_pid 2> /dev/null && wait $! 2> /dev/null

  echo
  travis_time_end

  test $result -eq 0 || exit $result
}

#######################################
function travis_jigger() {
  local cmd_pid=$1
  shift
  local timeout=$1
  shift
  local count=0

  while [ $count -lt $timeout ]; do
    count=$(($count + 1))
    sleep 60 # wait 60s
    echo -ne "."
  done

  echo -e "\n\033[31;1mTimeout (${timeout} minutes) reached. Terminating \"$@\"\033[0m\n"
  echo -e "\033[33;1mTry again. Having saved cache results, Travis will probably succeed next time.\033[0m\n"
  kill -9 $cmd_pid
}
