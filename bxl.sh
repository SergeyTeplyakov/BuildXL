#!/bin/bash

set -e

# Make sure we are running in our own working directory
pushd "$(dirname "$0")"

MY_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$MY_DIR/Public/Src/Sandbox/MacOs/scripts/env.sh"

declare arg_Positional=()
declare arg_DeployDev=""
declare arg_UseDev=()
declare arg_Minimal=""
declare arg_Internal=""

function findMono() {
    local monoLocation=$(which mono)
    if [[ -z $monoLocation ]]; then
        print_error "Did not find Mono. Please ensure mono is installed per: https://www.mono-project.com/docs/getting-started/install/ and is accessable in your PATH"
        return 1
    else
        export MONO_HOME="$(dirname "$monoLocation")"
    fi
}

function getLkg() {
    local BUILDXL_LKG_NAME="BuildXL.osx-x64"
    local BUILDXL_LKG_VERSION=$(grep "BUILDXL_LKG_VERSION" "$MY_DIR/Shared/Scripts/BuildXLLkgVersion.cmd" | cut -d= -f2 | tr -d '\r')
    local BUILDXL_LKG_FEED_1="https://1essharedassets.pkgs.visualstudio.com/_packaging/BuildXL/nuget/v3/index.json"

    print_info "Nuget Feed: $BUILDXL_LKG_FEED_1"
    print_info "Getting package: $BUILDXL_LKG_NAME.$BUILDXL_LKG_VERSION"

    local _BUILDXL_BOOTSTRAP_OUT="$MY_DIR/Out/BootStrap"
    $MONO_HOME/mono shared/tools/nuget.exe install -OutputDirectory "$_BUILDXL_BOOTSTRAP_OUT" -Source $BUILDXL_LKG_FEED_1 $BUILDXL_LKG_NAME -Version $BUILDXL_LKG_VERSION
    export BUILDXL_BIN="$_BUILDXL_BOOTSTRAP_OUT/$BUILDXL_LKG_NAME.$BUILDXL_LKG_VERSION"
}

function setMinimal() {
    arg_Positional+=(/q:DebugDotNetCoreMac "/f:output='$MY_DIR/Out/bin/debug/osx-x64/*'")
}

function setInternal() {
    arg_Positional+=("/p:[Sdk.BuildXL]microsoftInternal=1")
}

function compileWithBxl() {
    local args=(
        --config "$MY_DIR/config.dsc"
        /sandboxKind:macOsKext
        /p:[Sdk.Deployment]Diagnostics.enabled=true
        /fancyConsoleMaxStatusPips:10
        /nowarn:11319 # DX11319: nuget version mismatch
        "$@"
    )

    if [[ -z "${VSTS_BUILDXL_BIN}" ]]; then
        "$BUILDXL_BIN/bxl.sh" "${args[@]}"
    else
        # Currently only used on VSTS CI to allow for custom BuildXL binary execution
        "$VSTS_BUILDXL_BIN/bxl.sh" "${args[@]}"
    fi
}

function printHelp() {
    echo "${BASH_SOURCE[0]} [--deploy-dev] [--use-dev] [--minimal] [--internal] <other-arguments>"
}

function parseArgs() {
    arg_Positional=()
    while [[ $# -gt 0 ]]; do
        cmd="$1"
        case $cmd in
        --help | -h)
            printHelp
            shift
            return 1
            ;;
        --deploy-dev)
            arg_DeployDev="1"
            shift
            ;;
        --use-dev)
            arg_UseDev="1"
            shift
            ;;
        --minimal)
            arg_Minimal="1"
            shift
            ;;
        --internal)
            arg_Internal="1"
            shift
            ;;
        *)
            arg_Positional+=("$1")
            shift
            ;;
        esac
    done
}

function deployBxl { # (fromDir, toDir)
    local fromDir="$1"
    local toDir="$2"

    mkdir -p "$toDir"
    /usr/bin/rsync -arhq "$fromDir/" "$toDir" --delete
    print_info "Successfully deployed developer build to: $toDir; use it with the '--use-dev' flag now."
}

parseArgs "$@"

findMono

if [[ -n "$arg_UseDev" ]]; then
    if [[ ! -f $MY_DIR/Out/Selfhost/Dev/bxl ]]; then
        print_error "Error: Could not find the dev deployment. Make sure you build with --deploy-dev first."
        exit 1
    fi

    export BUILDXL_BIN=$MY_DIR/Out/Selfhost/Dev
else
    getLkg
fi

if [[ -n "$arg_DeployDev" || -n "$arg_Minimal" ]]; then
    setMinimal
fi

if [[ -n "$arg_Internal" ]]; then
    setInternal
fi

compileWithBxl ${arg_Positional[@]}

if [[ -n "$arg_DeployDev" ]]; then
    deployBxl "$MY_DIR/Out/Bin/debug/osx-x64" "$MY_DIR/Out/Selfhost/Dev"
fi

popd