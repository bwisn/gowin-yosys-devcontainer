#!/bin/bash
set -e

CONFIG_FILE="config.json"



get_config() {
    jq -r ".$1" "$CONFIG_FILE"
}

load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Error: $CONFIG_FILE not found!"
        exit 1
    fi

    PROJECT_NAME=$(get_config "project_name")
    TOP_MODULE=$(get_config "top_module")
    CST_FILE=$(get_config "cst_file")
    DEVICE=$(get_config "device")
    SYNTH_FAMILY=$(get_config "synth_family")
    [ "$SYNTH_FAMILY" = "null" ] && SYNTH_FAMILY=""
    PNR_FAMILY=$(get_config "pnr_family")
    PACK_FAMILY=$(get_config "pack_family")
    BOARD=$(get_config "board")
}

resolve_sources() {
    RAW_SOURCES=$(jq -r '.sources[]' "$CONFIG_FILE" 2>/dev/null || echo "")
    SOURCES=""
    for src in $RAW_SOURCES; do
        if [ -d "$src" ]; then
            FILES=$(find "$src" -name "*.v" | tr '\n' ' ')
            SOURCES="$SOURCES $FILES"
        elif [ -f "$src" ]; then
            SOURCES="$SOURCES $src"
        else
            echo "Warning: Source '$src' not found."
        fi
    done
}

synthesize() {
    resolve_sources
    echo ""
    echo "======================================"
    echo "        Step 1: Synthesis Process"
    echo "======================================"
    echo "Project: $PROJECT_NAME"
    echo "Sources: $SOURCES"
    echo "--------------------------------------"

    echo "[1/3] Synthesis (Yosys)..."
    FAMILY_ARG=""
    if [ -n "$SYNTH_FAMILY" ]; then
        FAMILY_ARG="-family $SYNTH_FAMILY"
    fi
    YOSYS_CMD="read_verilog $SOURCES; synth_gowin -top $TOP_MODULE -json ${PROJECT_NAME}.json $FAMILY_ARG"
    yosys -q -p "$YOSYS_CMD" || { echo "Synthesis failed!"; return 1; }

    echo "[2/3] Place & Route (Nextpnr)..."
    NEXTPNR_ARGS="--json ${PROJECT_NAME}.json --write ${PROJECT_NAME}_pnr.json --device $DEVICE --vopt family=$PNR_FAMILY --vopt cst=$CST_FILE"
    nextpnr-himbaechel $NEXTPNR_ARGS > /dev/null 2>&1 || { echo "PnR failed!"; return 1; }

    echo "[3/3] Packing (Gowin Pack)..."
    PACK_ARGS="-d $PACK_FAMILY -o ${PROJECT_NAME}.fs ${PROJECT_NAME}_pnr.json"
    gowin_pack $PACK_ARGS || { echo "Packing failed!"; return 1; }
    
    echo "--------------------------------------"
    echo "Synthesis Complete: ${PROJECT_NAME}.fs"
    echo "======================================"
}

flash() {
    echo ""
    echo "======================================"
    echo "        Step 2: Flash Process"
    echo "======================================"
    if [ ! -f "${PROJECT_NAME}.fs" ]; then
        echo "Error: ${PROJECT_NAME}.fs not found! Run synthesize first."
        return 1
    fi
    echo "Target Board: $BOARD"
    echo "Flashing ${PROJECT_NAME}.fs..."
    OFL_ARGS="-b $BOARD ${PROJECT_NAME}.fs"
    sudo openFPGALoader $OFL_ARGS || echo "Flashing failed (is the cable connected?)"
    echo "======================================"
}

while true; do
    load_config
    if [ -z "$1" ]; then
        echo "--------------------------------------"
        echo "Project: $PROJECT_NAME"
        echo "Board:   $BOARD"
        echo "--------------------------------------"
        echo "Select an action:"
        echo "1) Synthesize Only"
        echo "2) Flash Only"
        echo "3) Synthesize & Flash"
        echo "q) Quit"
        echo "--------------------------------------"
        read -p "Your choice [1-3, q]: " choice
        case $choice in
            1) STAGE="synthesize" ;;
            2) STAGE="flash" ;;
            3) STAGE="all" ;;
            q|Q) exit 0 ;;
            *) echo "Invalid choice"; continue ;;
        esac
    else
        STAGE=$1
    fi

    case $STAGE in
        synthesize|build)
            synthesize
            ;;
        flash)
            flash
            ;;
        all)
            synthesize && flash
            ;;
        *)
            echo "Usage: $0 {synthesize|flash|all}"
            exit 1
            ;;
    esac

    if [ -n "$1" ]; then
        break
    fi
done

exit 0
