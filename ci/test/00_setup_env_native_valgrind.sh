#!/usr/bin/env bash
#
# Copyright (c) 2019-2021 The Bitcoin Core developers
# Distributed under the MIT software license, see the accompanying
# file COPYING or http://www.opensource.org/licenses/mit-license.php.

export LC_ALL=C.UTF-8

export DOCKER_NAME_TAG="ubuntu:22.04"
export CONTAINER_NAME=ci_native_valgrind
export PACKAGES="valgrind clang llvm python3-zmq libevent-dev bsdmainutils libboost-dev libboost-test-dev libdb5.3++-dev libminiupnpc-dev libnatpmp-dev libzmq3-dev libsqlite3-dev"
export NO_DEPENDS=1
export GOAL="install"
export GROESTLCOIN_CONFIG="--enable-zmq --with-gui=no CC=clang CXX=clang++"  # TODO enable GUI
